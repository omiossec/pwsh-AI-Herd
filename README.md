# pwsh-ai-herd

Herd your coding agents. A PowerShell 7 module that runs up to **6 independent CLI processes
side by side in a single console window** — one frame per agent (Claude, Codex, or any other
line-oriented CLI), each with its own PID, its own output pane, and its own input line.

```
┌ New frame command ───────────────────────────────────────────────────┐
│ claude --print --verbose --input-form…    [ Add frame ]   [ Quit ]   │
└──────────────────────────────────────────────────────────────────────┘
┌ PID 4812 | claude --print ... ─────┐┌ PID 9134 | codex exec ... ─────┐
│ -- session started | claude-opus-5 ││ Analysing repository…          │
│ > refactor the parser              ││ ! warning: no tests found      │
│ [tool] Read                        ││                                │
│ Found 3 call sites in src/parser.p ││                                │
│ [input________________] Send Close ││ [input______________] Send Close│
└────────────────────────────────────┘└─────────────────────────────────┘
```

## Status

Early, but usable. `Start-AiHerd` hosts the frames, streams output, and forwards input, and
frames start in the directory you launched it from. Claude has a working preset, which makes
a frame a multi-turn conversation. Copilot and Codex are still started as bare executables,
and git worktree isolation is on the roadmap.

## Requirements

- **PowerShell 7.0 or later.** Windows PowerShell 5.1 is not supported.
- **`Microsoft.PowerShell.ConsoleGuiTools`**, which ships the `Terminal.Gui` assemblies the
  UI is built on:

  ```powershell
  Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser
  ```

- A real interactive terminal. Windows, Linux, and macOS are all supported.

## Install

The module is not published to the PowerShell Gallery yet. Clone and import it:

```powershell
git clone https://github.com/omiossec/pwsh-ai-herd.git
Import-Module ./pwsh-ai-herd/src/pwsh-ai-herd.psd1
```

To make it available permanently, copy `src` into a folder **named `pwsh-ai-herd`** on your
`$env:PSModulePath` (the folder name has to match the manifest for auto-discovery):

```powershell
$destination = Join-Path ($env:PSModulePath -split [IO.Path]::PathSeparator)[0] 'pwsh-ai-herd'
Copy-Item -Path ./pwsh-ai-herd/src -Destination $destination -Recurse
Import-Module pwsh-ai-herd
```

## Usage

Start an empty host and add frames from the top bar:

```powershell
Start-AiHerd
```

Start with agent sessions already running — up to six, one frame each:

```powershell
Start-AiHerd -NumberOfSession 3
```

Pick the agent with `-Agent` (`Claude`, `Copilot`, or `Codex`; defaults to `Claude`). Its
executable has to be on `PATH`:

```powershell
Start-AiHerd -NumberOfSession 2 -Agent Codex
```

Every frame starts in your current location, so `cd` to the repository first. Override it with
`-WorkingDirectory`; the directory in play is shown in the window title:

```powershell
Start-AiHerd -NumberOfSession 2 -WorkingDirectory C:\repos\contoso
```

The top bar is pre-filled with the selected agent's command, so **[Add frame]** adds another
session of the same kind. Overwrite the field to run anything else — the first token is the
executable, the rest is passed as arguments, and a path with spaces goes in quotes:

```
"C:\Program Files\Git\bin\git.exe" log --oneline -20
```

### Agents

A coding agent reached through a pipe has to be told not to open its full-screen UI and — if
the frame is to be a conversation rather than a single shot — to keep reading stdin between
turns. `-Agent Claude` therefore starts:

```
claude --print --verbose --input-format stream-json --output-format stream-json
```

In that mode the frame speaks the agent's JSON protocol on both pipes: what you type is
wrapped in a user message on the way in, and the events coming back are rendered as plain
text — assistant replies, `[tool] Read`, `[tool result] ...`, `-- turn complete (1488 ms) --`.
Any command line containing `--input-format stream-json` gets this treatment, including one
you type yourself; everything else is treated as a plain line-oriented CLI.

Two things to know:

- A bare `claude` **will not work**. It sees the redirected stdin, takes it for a piped
  one-shot prompt, and exits with `Warning: no stdin data received`.
- A non-interactive session cannot answer a permission prompt, so a tool call that needs
  approval is refused. Add the flags you want (`--permission-mode`, `--allowedTools`, ...) to
  the command line in the top bar before pressing **[Add frame]**.

`-Agent Copilot` and `-Agent Codex` are still the bare `copilot` and `codex` executables.
Neither has an equivalent stdin protocol yet — `copilot -p` and `codex exec` read a single
prompt to end-of-input — so they behave as one-shot frames for now.

### Controls

| Control | What it does |
| --- | --- |
| **[Add frame]** | Starts the command in the top bar in a new frame (max 6) |
| **[Send]** / <kbd>Enter</kbd> | Writes the frame's input line to that process's stdin |
| **[Close]** | Kills the frame's whole process tree and removes the frame |
| **[Quit]** | Terminates every remaining child process and restores the console |
| <kbd>Tab</kbd> | Moves focus between frames and controls |

Frames are laid out automatically on a grid (1×1, 2×1, 2×2, 3×2) as you add and close them.
Each frame keeps the last 300 lines of scroll-back, and stderr lines are prefixed with `! `.

## Interactive grid (WezTerm backend)

The frame host above talks to agents through pipes, so they run in their non-interactive
mode. The `*-AiGrid` commands take the other route: they drive [WezTerm](https://wezterm.org)
the way [agentic-config](sam/agentic-config) drives tmux. Every agent gets a real terminal
pane, runs its normal full-screen UI, and the PowerShell side only does the herding: layout,
pinned session ids, git worktrees, reopen, broadcast.

Requirements: WezTerm installed (`winget install wez.wezterm`, `brew install --cask wezterm`,
or your distribution's package), `git` for worktrees, and the agent executables on `PATH`.
On Windows on ARM the x64 build runs under emulation.

```powershell
Start-AiGrid                       # 4 Claude agents, 2 x 2, in the current directory
Start-AiGrid -Count 6              # 6 agents, 3 columns x 2 rows
Start-AiGrid -Columns 3 -Rows 1    # explicit matrix
Start-AiGrid -Agent Mixed          # alternate Claude / Codex panes
Start-AiGrid -Worktree             # one git worktree + branch (herd/<session>-<n>) per agent
Start-AiGrid -Kickoff 'Read CLAUDE.md, then wait for instructions.'
```

Every Claude pane is launched with a pinned `--session-id`, and the grid (directory, layout,
one record per pane) is saved per project directory under `%LOCALAPPDATA%\pwsh-ai-herd`
(`$XDG_STATE_HOME/pwsh-ai-herd` elsewhere). That makes the grid reopenable:

```powershell
Get-AiGrid                         # recorded grids, newest first
Resume-AiGrid                      # reopen the grid of the current directory, each pane resuming its conversation
Get-AiGrid | Select-Object -First 1 | Resume-AiGrid
```

Inside a grid (from any pane, or from the project directory):

```powershell
Add-AiGridAgent -Agent Codex -Task review     # add a tracked pane
Send-AiGridText 'Run the tests and report failures only.'   # broadcast a prompt to every pane
Remove-AiGridWorktree                        # remove this grid's worktrees (branches are kept unless -DeleteBranch)
```

Effort is spread like the tmux version: the last pane runs low, roughly a quarter run
medium, the rest run at the default level (`CLAUDE_CODE_EFFORT_LEVEL` for Claude,
`-c model_reasoning_effort` for Codex). Each pane also exports `HERD_SESSION_ID`,
`HERD_AGENT` and `HERD_TASK`, and sets the WezTerm user vars `herd_task` and
`herd_session_id`, so a `wezterm.lua` status bar or Claude hooks can label panes and flag the
ones waiting on you.

## How it works

Each frame owns a `System.Diagnostics.Process` with stdout, stderr, and stdin redirected. The
stream callbacks fire on .NET thread-pool threads, where PowerShell script blocks cannot run,
so the pipe reading lives in a small compiled C# wrapper that pushes lines into a
`ConcurrentQueue<string>`. A 120 ms timer on the Terminal.Gui main loop drains those queues
into the views — which is why the frames stay independent: a busy or hung agent blocks
nothing but its own pane.

### Limitation: pipes, not a PTY

Frames talk to their process through redirected pipes rather than a pseudo-terminal.
Line-oriented programs work well (`ping`, `az`, `terraform`, scripts, REPLs). Full-screen TUI
programs (`vim`, `htop`, and the full-screen UI of the coding agents themselves) will not
render correctly — start agents in their non-interactive, print, or streaming mode.

## Roadmap

- WezTerm grid: a `wezterm.lua` snippet showing pane labels and a "waiting on you" marker
  fed by Claude hooks, squads (preconfigured teams with roles), and jump-to-waiting-pane
- Streaming presets for Copilot and Codex, most likely through their ACP / MCP server modes
- Git worktree per agent in the frame host (the WezTerm grid already has it)
- Permission handling for non-interactive agents, instead of flags typed into the top bar
- Publish to the PowerShell Gallery

## Contributing

Issues and pull requests are welcome. The module layout and its conventions are documented in
[CLAUDE.md](CLAUDE.md): `src/class`, `src/private`, and `src/public`, one function per file
with the file name matching the function name.

`Import-Module -Force` picks up any script change, but **not** a change to the inline C# in
`src/class`: `Add-Type` cannot redefine a type in a running session, so start a new shell
after touching it.

```powershell
Test-ModuleManifest -Path ./src/pwsh-ai-herd.psd1
Import-Module ./src/pwsh-ai-herd.psd1 -Force
Invoke-ScriptAnalyzer -Path ./src -Recurse
```

## License

[MIT](LICENSE) © Olivier Miossec
