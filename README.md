# pwsh-ai-herd

Herd your coding agents. A PowerShell 7 module that runs several coding agents (Claude Code,
Codex, Copilot) side by side, each in its own pane, each an independent process, all in one
window.

Two backends, same idea:

| | **WezTerm grid** (`*-AiGrid`) | **Frame host** (`Start-AiHerd`) |
| --- | --- | --- |
| Panes are | real terminals (PTY) | redirected pipes |
| Agents run | their normal full-screen UI | non-interactive / streaming mode |
| Permission prompts | work | cannot be answered |
| Reopen a session | yes, pinned session ids | no |
| Git worktree per agent | yes | not yet |
| Needs | WezTerm installed | `Microsoft.PowerShell.ConsoleGuiTools` |

Start with the grid. The frame host is the fallback when installing WezTerm is not an option,
or when you want line-oriented CLIs other than agents in the panes.

## Status

The WezTerm grid works and is where the project is going: launch, layout, effort spread,
pinned session ids, grid records, broadcast, and git worktree isolation are all in place. It
has been exercised on Windows 11 on ARM with WezTerm 20240203. Reopening a grid, adding a pane
to a live grid, and worktree isolation are implemented but not yet battle-tested.

The frame host is usable and unchanged: Claude has a working streaming preset that makes a
frame a multi-turn conversation, Copilot and Codex are still bare executables.

## Requirements

- **PowerShell 7.0 or later.** Windows PowerShell 5.1 is not supported.
- For the **WezTerm grid**: [WezTerm](https://wezterm.org), and `git` if you want worktree
  isolation.

  ```powershell
  winget install wez.wezterm          # Windows (the x64 build runs under emulation on ARM)
  brew install --cask wezterm         # macOS
  ```

- For the **frame host**: `Microsoft.PowerShell.ConsoleGuiTools`, which ships the
  `Terminal.Gui` assemblies the UI is built on.

  ```powershell
  Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser
  ```

- The agent executables (`claude`, `codex`, `copilot`) on `PATH`.
- Windows, Linux, and macOS are all supported.

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

## The WezTerm grid

`Start-AiGrid` opens a WezTerm window and fills it with agents, one per pane. PowerShell only
does the herding — layout, session ids, worktrees, reopen, broadcast — and WezTerm gives each
agent a real terminal, so Claude Code runs its normal interface: permission prompts, slash
commands, colours, all of it. The design follows *agentic-config*, a zsh and tmux tool that
does the same thing on macOS and Linux, with `wezterm cli` in the role tmux plays there.

```
┌──────────────────────┬──────────────────────┬──────────────────────┐
│ ✳ Claude Code        │ ✳ Claude Code        │ ✳ Claude Code        │
│   default effort     │   default effort     │   medium effort      │
│ ❯ refactor the parser│ ❯ write the tests    │ ❯ review the diff    │
├──────────────────────┼──────────────────────┼──────────────────────┤
│ ✳ Claude Code        │ ✳ Claude Code        │ ✳ Claude Code        │
│   medium effort      │   default effort     │   low effort         │
│ ❯                    │ ❯                    │ ❯                    │
└──────────────────────┴──────────────────────┴──────────────────────┘
                        Start-AiGrid -Count 6
```

### Launch

```powershell
Start-AiGrid                       # 4 Claude agents, 2 x 2, in the current directory
Start-AiGrid -Count 6              # 6 agents, 3 columns x 2 rows
Start-AiGrid -Columns 3 -Rows 1    # explicit matrix
Start-AiGrid -Agent Mixed          # alternate Claude / Codex panes
Start-AiGrid -Worktree             # one git worktree + branch (herd/<session>-<n>) per agent
Start-AiGrid -Kickoff 'Read CLAUDE.md, then wait for instructions.'
```

Auto layout picks the smallest square-ish grid with columns at least equal to rows, so six
agents become three columns by two rows. `cd` to your repository first: the grid takes the
current location as its project directory unless you pass `-WorkingDirectory`.

Effort is spread so a glance shows where the cycles go: the last pane runs low, roughly a
quarter run medium, the rest run at the default level. Claude gets it through
`CLAUDE_CODE_EFFORT_LEVEL`, Codex through `-c model_reasoning_effort`.

### Reopen

Every Claude pane is launched with a pinned `--session-id`, and the grid — project directory,
layout, and one record per pane — is saved under `%LOCALAPPDATA%\pwsh-ai-herd`
(`$XDG_STATE_HOME/pwsh-ai-herd` elsewhere), one record per project. So the whole grid comes
back, each pane resuming its own conversation:

```powershell
Get-AiGrid                         # recorded grids, newest first
Resume-AiGrid                      # reopen the grid of the current directory
Get-AiGrid | Select-Object -First 1 | Resume-AiGrid
```

Codex panes resume the most recent session in their directory (`codex resume --last`) rather
than a pinned id, because the Codex CLI has no equivalent to `--session-id` yet. Recorded
worktrees that vanished from disk are recreated on their branch.

### Inside a grid

These work from any pane of the grid (they find it through `$env:WEZTERM_PANE`) or from the
project directory:

| Command | What it does |
| --- | --- |
| `Add-AiGridAgent` | Splits one more tracked pane off the grid, with `-Agent`, `-Task`, `-Kickoff`, `-Worktree` |
| `Send-AiGridText` | Broadcast: types the same prompt into every live pane and presses Enter (`-NoEnter` to skip, `-PaneIndex` to target some) |
| `Remove-AiGridWorktree` | Removes this grid's worktrees; branches survive unless you pass `-DeleteBranch` |
| `Get-AiGrid` | Lists the recorded grids |

```powershell
Add-AiGridAgent -Agent Codex -Task review
Send-AiGridText 'Run the tests and report failures only.'
Remove-AiGridWorktree -DeleteBranch
```

Every command supports `-WhatIf`, which is the cheapest way to see what a launch would do.

### Worktree isolation

`-Worktree` gives each agent its own git worktree on branch `herd/<session>-<n>`, created
under the module state folder, so agents never fight over the same working tree. Merging their
work back is manual and deliberate: `Remove-AiGridWorktree` removes the worktrees and keeps
the branches unless you ask otherwise.

### Pane identity

Each pane exports `HERD_SESSION_ID`, `HERD_AGENT` and `HERD_TASK`, and publishes the WezTerm
user vars `herd_task` and `herd_session_id`. A `wezterm.lua` status line can read those with
`pane:get_user_vars()` to label panes, and Claude hooks running inside a pane can use them to
flag the agents waiting on you. A ready-made Lua snippet is on the roadmap.

### Troubleshooting

- **The command prints a grid record but no window appears.** An earlier version spawned the
  panes into a headless `wezterm-mux-server`. Update, then check with
  `Get-Process wezterm-mux-server`; kill it if one is lingering.
- **`failed to connect to Socket("gui-sock-...")`.** The WezTerm CLI resolves that socket name
  relative to the current directory when it is not run from inside a pane. The module finds
  the live socket itself, so this should not surface; if it does, run the command from a
  WezTerm pane, where `WEZTERM_UNIX_SOCKET` is already set.
- **`encoding PDU to client` errors during launch.** Harmless. They come from WezTerm while
  the module polls for the new window.

## The frame host

`Start-AiHerd` opens a single Terminal.Gui window holding up to six frames, each wrapping one
child process with its own PID, output pane, and input line. No external terminal needed.

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

```powershell
Start-AiHerd                                        # empty; add frames from the top bar
Start-AiHerd -NumberOfSession 3                     # three Claude sessions
Start-AiHerd -NumberOfSession 2 -Agent Codex        # pick the agent
Start-AiHerd -NumberOfSession 2 -WorkingDirectory C:\repos\contoso
```

The top bar is pre-filled with the selected agent's command, so **[Add frame]** adds another
session of the same kind. Overwrite the field to run anything else — the first token is the
executable, the rest is passed as arguments, and a path with spaces goes in quotes:

```
"C:\Program Files\Git\bin\git.exe" log --oneline -20
```

### Agents through a pipe

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
  the command line in the top bar before pressing **[Add frame]**. If you need prompts to
  work, use the WezTerm grid instead.

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

## How it works

**The grid** is a thin PowerShell layer over `wezterm cli`. One builder creates the window and
every split, so launching and reopening a grid cannot drift apart, and one function knows how
each agent is started or resumed. Panes run `pwsh -NoExit`, so a pane survives its agent
exiting and stays available for a restart. WezTerm pane ids are live-only; the durable
identity of an agent is its pinned session id in the grid record.

**The frame host** gives each frame a `System.Diagnostics.Process` with stdout, stderr, and
stdin redirected. The stream callbacks fire on .NET thread-pool threads, where PowerShell
script blocks cannot run, so the pipe reading lives in a small compiled C# wrapper that pushes
lines into a `ConcurrentQueue<string>`. A 120 ms timer on the Terminal.Gui main loop drains
those queues into the views — which is why the frames stay independent: a busy or hung agent
blocks nothing but its own pane.

### Limitation: pipes, not a PTY

This applies to the frame host only. Frames talk to their process through redirected pipes
rather than a pseudo-terminal. Line-oriented programs work well (`ping`, `az`, `terraform`,
scripts, REPLs). Full-screen TUI programs (`vim`, `htop`, and the full-screen UI of the coding
agents themselves) will not render correctly — start agents in their non-interactive, print,
or streaming mode, or use the WezTerm grid.

## Roadmap

- A `wezterm.lua` snippet: pane labels from `herd_task`, and a "waiting on you" marker fed by
  Claude hooks
- Squads: preconfigured teams where each agent arrives with a role and a kickoff prompt
- Jump to the next pane waiting on you, and a token total in the status line
- Streaming presets for Copilot and Codex, most likely through their ACP / MCP server modes
- Git worktree per agent in the frame host (the grid already has it)
- Permission handling for non-interactive agents, instead of flags typed into the top bar
- Publish to the PowerShell Gallery

## Contributing

Issues and pull requests are welcome. The module layout and its conventions are documented in
[CLAUDE.md](CLAUDE.md): `src/class`, `src/private`, and `src/public`, one function per file
with the file name matching the function name. CLAUDE.md also records the WezTerm gotchas
found on Windows, which are worth reading before touching that backend.

`Import-Module -Force` picks up any script change, but **not** a change to the inline C# in
`src/class`: `Add-Type` cannot redefine a type in a running session, so start a new shell
after touching it.

```powershell
Test-ModuleManifest -Path ./src/pwsh-ai-herd.psd1
Import-Module ./src/pwsh-ai-herd.psd1 -Force
Invoke-ScriptAnalyzer -Path ./src -Recurse
./test/Invoke-Test.ps1
```

There is a Pester 5 test per function under [test](test), documented in
[test/README.md](test/README.md). The suite needs neither WezTerm nor a console: the wezterm
command line and git are faked, so `Start-AiGrid` can be exercised by asserting on the calls it
would have made.

## License

[MIT](LICENSE) © Olivier Miossec
