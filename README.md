# pwsh-ai-herd

Herd your coding agents. A PowerShell 7 module that runs up to **6 independent CLI processes
side by side in a single console window** — one frame per agent (Claude, Codex, or any other
line-oriented CLI), each with its own PID, its own output pane, and its own input line.

```
┌ New frame command ───────────────────────────────────────────────────┐
│ claude -p "refactor the parser"          [ Add frame ]   [ Quit ]    │
└──────────────────────────────────────────────────────────────────────┘
┌ PID 4812 | claude -p ... ──────────┐┌ PID 9134 | codex exec ... ─────┐
│ Reading src/parser.ps1             ││ Analysing repository…          │
│ Found 3 call sites                 ││ ! warning: no tests found      │
│ > yes, go ahead                    ││                                │
│                                    ││                                │
│ [input________________] Send Close ││ [input______________] Send Close│
└────────────────────────────────────┘└─────────────────────────────────┘
```

## Status

Early. `Start-AiHerd` works today: it hosts the frames, streams output, and forwards input.
Agent presets and git worktree isolation are on the roadmap, not implemented yet.

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

Start with frames already running — up to six command lines, one frame each:

```powershell
Start-AiHerd -Command 'ping 127.0.0.1', 'pwsh -NoProfile -File ./watch.ps1'
```

Quote the executable if its path contains spaces; everything after the first token is passed
through as arguments:

```powershell
Start-AiHerd -Command '"C:\Program Files\Git\bin\git.exe" log --oneline -20'
```

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

- Agent presets, so you can say `claude` or `codex` instead of a raw command line
- Git worktree per agent: create it on request, run the agent there, clean it up on close
- Publish to the PowerShell Gallery

## Contributing

Issues and pull requests are welcome. The module layout and its conventions are documented in
[CLAUDE.md](CLAUDE.md): `src/class`, `src/private`, and `src/public`, one function per file
with the file name matching the function name.

```powershell
Test-ModuleManifest -Path ./src/pwsh-ai-herd.psd1
Import-Module ./src/pwsh-ai-herd.psd1 -Force
Invoke-ScriptAnalyzer -Path ./src -Recurse
```

## License

[MIT](LICENSE) © Olivier Miossec
