# pwsh-ai-herd

PowerShell 7 module that runs up to 6 **independent CLI processes** side by side inside a
single console window. The intended payload is coding agents (Claude Code, Codex, ...): the
module herds the agent processes, brokers input/output to each one, and can create a git
worktree per agent so the agents do not fight over the same working tree.

## Current state

Working module with two backends:

- **Frame host** (`Start-AiHerd`): the original Terminal.Gui window with pipe-driven frames.
  Agents run in their non-interactive stream-json mode. Zero external dependency beyond
  ConsoleGuiTools.
- **WezTerm grid** (`*-AiGrid*`): the PowerShell counterpart of `sam/agentic-config`
  (zsh + tmux, kept in the repo as the reference). PowerShell drives `wezterm cli` to build a
  window of real PTY panes, one interactive agent each, and records the grid so it can be
  reopened. This is the direction the project is going; the frame host stays as fallback.

```
src/
  pwsh-ai-herd.psd1        manifest (FunctionsToExport lists every public function)
  pwsh-ai-herd.psm1        loader: dot-sources class -> private -> public, exports public
  class/
    00-FrameProcess.ps1    Add-Type of the C# child-process wrapper (frame host)
  private/                 -- frame host --
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
                           -- WezTerm grid --
    Get-WezTermPath.ps1    locate wezterm (PATH, then default install dirs), throws with hint
    Invoke-WezTermCli.ps1  `wezterm cli <args>` -> stdout; throws on failure; -Quiet probes
    Get-WezTermPane.ps1    `wezterm cli list --format json` as objects
    Wait-WezTermPane.ps1   poll for a pane id not in a known set (after `wezterm start`)
    Get-HerdStatePath.ps1  %LOCALAPPDATA%\pwsh-ai-herd | $XDG_STATE_HOME/pwsh-ai-herd
    Get-HerdGridPath.ps1   grid file for a project dir (md5 of the normalised path)
    Get-GridGeometry.ps1   N -> columns x rows (columns >= rows), or explicit matrix
    Get-AgentEffort.ps1    default/medium/low spread over N panes (last = low)
    Get-AgentPaneCommand.ps1  the ONLY place that knows how to launch/resume each agent
    New-HerdWorktree.ps1   idempotent `git worktree add` on branch herd/<session>-<n>
    New-HerdGrid.ps1       the builder: window + splits + save (launch AND reopen)
    Save-HerdGrid.ps1 / Read-HerdGrid.ps1   grid JSON in and out
    Resolve-HerdGrid.ps1   which grid a command targets (-Path, $env:WEZTERM_PANE, cwd)
  public/
    Start-AiHerd.ps1       frame host entry point
    Start-AiGrid.ps1       sam:   new grid (-Count | -Columns/-Rows, -Agent, -Worktree, -Kickoff)
    Resume-AiGrid.ps1      sr:    reopen a recorded grid, each pane resuming its session
    Get-AiGrid.ps1         list recorded grids
    Add-AiGridAgent.ps1    gadd:  split one more tracked pane off the grid
    Send-AiGridText.ps1    gbcast: paste text + Enter into every live pane
    Remove-AiGridWorktree.ps1  gwt clean: remove the grid's worktrees (-DeleteBranch)
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
`PSUseShouldProcessForStateChangingFunctions` on the internal helpers (TUI ones plus
`New-HerdGrid` / `New-HerdWorktree`; the public `*-AiGrid*` commands carry ShouldProcess
instead, so a private helper prompting too would double the confirmations),
`PSReviewUnusedParameter` on the `param($MainLoop)` that the `Func[MainLoop,bool]` timer
signature requires, and `PSUseSingularNouns` on `Test-ConsoleGuiTools`, whose noun is the
literal module name.

The WezTerm grid logic can be exercised without WezTerm: inside the module scope
(`& (Get-Module pwsh-ai-herd) { ... }`) redefine `Get-WezTermPath`, `Invoke-WezTermCli` and
`Get-WezTermPane` with fakes that hand out pane ids, then call `Start-AiGrid`. The recorded
call sequence for 5 panes must be: spawn, split right 67, split right 50, split bottom 50 on
column 0, split bottom 50 on column 1 (that is the tmux `_grid_build` order).

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

## WezTerm grid architecture

Mirror of `sam/agentic-config/lib/grid.zsh`, with wezterm in the tmux role:

| tmux (agentic-config)                    | here                                              |
| ---------------------------------------- | ------------------------------------------------- |
| `tmux new-session` / `split-window -P`   | `wezterm cli spawn --new-window` / `split-pane` (both print the new pane id) |
| `tmux send-keys`                         | `wezterm cli send-text` (paste) + `--no-paste "\r"` for Enter |
| `@grid_uuid`, `@agent_task` pane options | the grid JSON (per pane: SessionId, Agent, Effort, Task, Worktree, Branch, PaneId) plus `HERD_*` env vars and `herd_*` wezterm user vars set by the pane's own startup script |
| `$TMUX_PANE`                             | `$env:WEZTERM_PANE` (used by `Resolve-HerdGrid`) |
| `; exec zsh` tail                        | the pane runs `pwsh -NoLogo -NoExit -Command <script>` |

Rules that matter:

- **One builder.** `Start-AiGrid` and `Resume-AiGrid` both end in `New-HerdGrid`; the only
  difference is `-Resume`, which `Get-AgentPaneCommand` turns into `claude --resume <id>` /
  `codex resume --last`. Never open panes anywhere else (except the single split in
  `Add-AiGridAgent`).
- **Pane command = pwsh script string.** `Get-AgentPaneCommand` builds a single-quoted-only
  PowerShell line (quotes doubled) so it survives the Windows argument round trip
  pwsh -> wezterm -> pwsh. Do not introduce double quotes into it.
- **Always `wezterm cli --no-auto-start`** (done once, in `Invoke-WezTermCli`). Plain
  `wezterm cli` auto-starts a headless `wezterm-mux-server` when no GUI runs; the reachability
  probe then succeeds and the whole grid is spawned into an invisible server. Seen on the
  first real run.
- **Tell the CLI where the GUI socket is.** From a non-WezTerm console, the 20240203 Windows
  build fails with `failed to connect to Socket("gui-sock-<pid>")` because it resolves that
  name relative to the current directory. `Get-WezTermSocket` picks the live `gui-sock-<pid>`
  (pid checked against running `wezterm-gui` processes; stale files linger) under
  `~/.local/share/wezterm` and `Invoke-WezTermCli` passes it through `WEZTERM_UNIX_SOCKET`
  for the duration of the call. Inside a pane the variable is already set and is used as is.
- **Open a fresh window with `wezterm-gui start`, not `wezterm start`.** The console proxy
  handed over and the GUI did not survive on Windows; launching `wezterm-gui.exe` (sibling of
  `wezterm.exe`) directly works.
- **`wezterm start` is asynchronous and prints nothing**, so a fresh window's first pane is
  found by diffing `wezterm cli list` (`Wait-WezTermPane`). When a GUI is already running,
  `wezterm cli spawn --new-window` is used and prints the id directly.
- **PaneId is live-only.** It identifies a pane inside the current wezterm process; on reopen
  it is reset and re-assigned. SessionId is the durable identity.
- **Layout order** is columns first (top row, left to right), then rows row-major, so the
  last index lands bottom-right. Split percentages are relative to the pane being split:
  column c gets `(remaining)/(remaining+1)`, row r gets `(cnt-r)/(cnt-r+1)`.
- Worktrees live under `<state>/worktrees/<session>/<n>` on branch `herd/<session>-<n>`;
  `Remove-AiGridWorktree` keeps branches unless `-DeleteBranch`, since merging back is manual.

## Planned scope (not implemented yet)

WezTerm grid, in rough priority order:

- `wezterm.lua` snippet: show `herd_task` in the tab/status line and a "waiting" marker set
  by Claude `Stop`/`Notification` hooks (the `pane-tint.sh` equivalent; hooks get
  `HERD_SESSION_ID` and `WEZTERM_PANE` from the pane environment).
- Squads (`squads/<name>/squad.conf` -> label, effort, kickoff per pane); the pane spec
  already carries Task/Kickoff/Effort for it.
- Jump to next waiting pane (`wezterm cli activate-pane`), token total in the status line.
- Not yet verified on a real WezTerm: the whole `*-AiGrid*` path was validated against fakes
  only (see "Current state"). First real run: `Start-AiGrid -Count 2 -WhatIf`, then without.

Frame host:

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
