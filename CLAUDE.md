# pwsh-ai-herd

PowerShell 7 module that runs up to 6 **independent CLI processes** side by side inside a
single console window. The intended payload is coding agents (Claude Code, Codex, ...): the
module herds the agent processes, brokers input/output to each one, and can create a git
worktree per agent so the agents do not fight over the same working tree.

## Current state

Working module, one public command. The prototype script that this grew out of has been
folded into `src/` and deleted from the root.

```
src/
  pwsh-ai-herd.psd1        manifest (FunctionsToExport = Start-AiHerd)
  pwsh-ai-herd.psm1        loader: dot-sources class -> private -> public, exports public
  class/
    00-FrameProcess.ps1    Add-Type of the C# child-process wrapper
  private/
    Test-ConsoleGuiTools.ps1  is ConsoleGuiTools installed? (bool, optional -MinimumVersion)
    Format-AgentEvent.ps1  one stream-json line -> display lines
    Get-EventContent.ps1   strict-mode-safe $event.message.content
    Get-EventSummary.ps1   arbitrary payload -> one short line
    Import-TerminalGui.ps1 loads Terminal.Gui/NStack at run time
    Split-CommandLine.ps1  executable + argument string
    New-Frame.ps1          starts a process, builds its FrameView
    Close-Frame.ps1        kills the process tree, drops the frame
    Set-FrameLayout.ps1    grid placement
    Send-FrameInput.ps1    stdin write
    Update-Frame.ps1       120 ms pump (queue -> view)
    Update-FrameView.ps1   redraw one frame's list
  public/
    Start-AiHerd.ps1       the entry point: builds the window, runs the Terminal.Gui loop
```

Rules that fall out of the loader:

- **One function per file, file name == function name.** `Export-ModuleMember` uses the
  public file base names, so a mismatch silently fails to export.
- `FunctionsToExport` in the manifest is the real gate — add each new public function name
  there too, or it will not be visible after `Import-Module`.
- Class load order is file-name order, hence the `00-` prefix. Prefix new class files when
  one depends on another.

Validate a change with:

```powershell
Test-ModuleManifest -Path ./src/pwsh-ai-herd.psd1
Import-Module ./src/pwsh-ai-herd.psd1 -Force
```

`Import-Module` compiles the C# type, so it catches most breakage without a terminal.
`Start-AiHerd` itself needs a real console (see below).

`Invoke-ScriptAnalyzer -Path ./src -Recurse` is clean apart from three accepted warnings:
`PSUseShouldProcessForStateChangingFunctions` on the internal TUI helpers,
`PSReviewUnusedParameter` on the `param($MainLoop)` that the `Func[MainLoop,bool]` timer
signature requires, and `PSUseSingularNouns` on `Test-ConsoleGuiTools`, whose noun is the
literal module name.

## Requirements

- PowerShell **7.0+** only. Windows PowerShell 5.1 is not supported (`#Requires -Version 7.0`).
- `Microsoft.PowerShell.ConsoleGuiTools` must be installed — it is not used as a module, it
  is used as a **delivery vehicle for `Terminal.Gui.dll` and `NStack.dll`**, which the script
  `Add-Type`s directly from the module base directory.
  `Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser`
- Cross-platform: Windows, Linux, macOS.

Run it with `Import-Module ./src/pwsh-ai-herd.psd1; Start-AiHerd` in a real terminal. It
cannot be exercised from a non-interactive/redirected session — `Terminal.Gui` takes over the console, so do not
try to "test" it by piping output; validate changes by reading the code and, when a real run
is needed, ask the user to run it.

## Architecture

Three layers, and the boundary between them is the important part:

1. **`FrameHost.FrameProcess` (inline C#, `src/class/00-FrameProcess.ps1`).**
   Wraps one `System.Diagnostics.Process` with all three streams redirected. `OutputDataReceived`
   / `ErrorDataReceived` fire on .NET thread-pool threads where **PowerShell script blocks cannot
   run** (no runspace). That is why the reader callbacks are C# and only enqueue into a
   `ConcurrentQueue<string>`. stderr lines are prefixed with `! `. Keep any new stream handling
   on this side of the fence.
2. **The pump.** `Update-Frame` runs every 120 ms via `Application.MainLoop.AddTimeout`, on the
   UI thread, so PowerShell is safe there. It drains each queue into the frame's line list,
   trims to `$script:MaxLine` (300), and notes process exit once (`ExitNoted`). It must return
   `$true` or the timeout stops firing.
3. **The `Terminal.Gui` views.** One `FrameView` per frame containing a `ListView` (output),
   a `TextField` (stdin), `[Send]` and `[Close]`. `Set-FrameLayout` places frames on a
   `ceil(sqrt(n))`-column grid using `Pos::Percent` / `Dim::Percent`, with the last column and
   last row using `Dim::Fill()` to absorb rounding.

State lives in module scope, shared by every module function and reset at the top of each
`Start-AiHerd` run: `$script:Frames` (list of frame PSCustomObjects), `$script:FrameContainer`,
`$script:MaxFrame` (6), `$script:MaxLine` (300).

### Gotchas

- Event handlers that capture a variable **must** use `.GetNewClosure()`. For `$frame` in
  `New-Frame`, without it every button acts on the last-created frame. For `$commandField` in
  `Start-AiHerd` it matters even more now that the code is a function and not a top-level
  script: the variable is a local, so the handler would see nothing when the event fires later.
- **`.GetNewClosure()` drops the module session state.** A closure cannot resolve
  module-private functions by name — Terminal.Gui surfaces `The term 'Send-FrameInput' is not
  recognized...` — and `$script:` state reads back empty. Capture the command outside the
  handler (`$sendCommand = Get-Command -Name 'Send-FrameInput'`) and call it as
  `& $sendCommand -Frame $frame`: invoking the `FunctionInfo` runs the function in its own
  module scope. Scriptblocks used *without* `.GetNewClosure()` keep module scope, which is why
  the `AddTimeout` `Update-Frame` delegate works as written.
- Closing a frame calls `Process.Kill(entireProcessTree: true)`; the `finally` block does the
  same for all remaining frames and then `Application::Shutdown()`. Never add an early `exit`
  path that skips it, or child agents survive the host.
- Pipes, not a PTY. Line-oriented CLIs work; full-screen TUI programs (vim, htop) will not
  render. Coding agents must therefore be launched in their non-interactive / print / stream
  modes, not their full-screen UI. A bare `claude` sees the redirected stdin, takes it for a
  piped one-shot prompt, and exits 1 with `no stdin data received`.
- Frames have a `Protocol`, derived in `New-Frame` from whether the command line contains
  `--input-format stream-json`. `StreamJson` frames wrap what you type in a user-message
  envelope on the way in (`Send-FrameInput`) and run each output line through
  `Format-AgentEvent` on the way out; `Text` frames pass both through untouched.
- A child process inherits the *host process* directory, which is not the PowerShell location
  the user sees. `Start-AiHerd` resolves `$PWD` into `$script:WorkingDirectory` and every
  frame starts there; the window title shows which directory is in play.
- Editing `src/class/00-FrameProcess.ps1` needs a **new shell** to take effect: the
  `-as [type]` guard means `Import-Module -Force` reuses the type already compiled into the
  session.
- `Split-CommandLine` is deliberately simple: leading `"..."` for a quoted executable, first
  space otherwise. It does not do full shell tokenization.

## Planned scope (not implemented yet)

- Agent argument presets. Claude is done: `claude --print --verbose --input-format
  stream-json --output-format stream-json`, the only mode of the three that keeps stdin open
  across turns. Copilot and Codex are still the bare executables — `copilot -p` and
  `codex exec` read one prompt to EOF, so a multi-turn frame needs something else (their ACP
  / MCP server modes are the likely route).
- Permissions in a Claude frame. Non-interactive means no permission prompt can be answered,
  so a tool call needing approval is refused; the flags (`--permission-mode`,
  `--allowedTools`) have to be typed into the top bar for now.
- Git worktree management: create a worktree per agent on request, launch the agent with that
  worktree as its working directory, and clean it up when the frame closes. `FrameProcess`
  now takes a working directory (third constructor argument) and `New-Frame` has a
  `-WorkingDirectory` parameter, so the remaining work is creating and removing the worktrees.
- The C# namespace is still `FrameHost` from the prototype; rename it when nothing else is
  in flight, keeping the `-as [type]` guard (`Add-Type` cannot redefine a type in a session,
  so a stale name lingers until the shell restarts).

## Conventions

Match the existing script; it is consistent and deliberate:

- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` at the top.
- Approved verbs, singular nouns, `[CmdletBinding()]`, comment-based help on every function,
  `[OutputType()]` where there is output.
- Parameters declared with `[Parameter(Mandatory)]` and validation attributes
  (`ValidateNotNullOrEmpty`, `ValidateCount`).
- `#region` / `#endregion` blocks for the major sections.
- Single quotes unless interpolating; full parameter names at call sites (`-Path`, `-Frame`);
  aligned `=` in assignment runs.
- `[void]` to discard, not `| Out-Null`.
