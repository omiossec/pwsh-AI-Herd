function Start-AiHerd {
    <#
    .SYNOPSIS
        Single-window frame host: run up to 6 independent CLI processes side by side in one console.

    .DESCRIPTION
        A Terminal.Gui TUI (the library ships with the Microsoft.PowerShell.ConsoleGuiTools module)
        that hosts 1 to 6 frames in a single console window. Each frame is meant to hold a coding
        agent (Claude, Codex, ...), but any line-oriented CLI works.

        Each frame:
          - wraps its own child process => own PID, fully independent of the other frames
          - shows the process stdout/stderr live (stderr lines are prefixed with '! ')
          - has an input line + [Send] button to write to the process stdin
          - has a [Close] control that kills the whole process tree and removes the frame

        The top bar lets you type any command line and add a new frame ([Add frame]) or quit
        the host ([Quit], which also terminates every remaining child process).

        Cross-platform: Windows, Linux, macOS. PowerShell 7+ only (no Windows PowerShell 5.1).

        Limitation: frames talk to their process through redirected pipes, not a PTY.
        Line-oriented CLI programs work fine (ping, az, terraform, scripts, REPLs, ...);
        full-screen TUI programs (vim, htop, ...) will not render correctly. Coding agents must
        therefore be started in their non-interactive / streaming mode: a bare 'claude' sees a
        redirected stdin, treats it as a piped one-shot prompt, and exits 1 with
        'no stdin data received' before the TUI ever appears.

    .PARAMETER NumberOfSession
        How many agent sessions to start immediately, 0 to 6, one frame each.
        Defaults to 0, which opens an empty layout you fill from the top bar.

    .PARAMETER WorkingDirectory
        Directory every frame's process starts in. Defaults to the current location.

    .PARAMETER Agent
        Which coding agent CLI the sessions run: Claude, Copilot, or Codex.
        Defaults to Claude. The agent's executable must be on PATH.

        Claude is launched in its streaming JSON mode, which is the only one of the three that
        keeps stdin open for a multi-turn conversation over a pipe. Copilot and Codex have no
        equivalent stdin protocol yet, so they are started bare and read a single prompt.

    .EXAMPLE
        Start-AiHerd

        Starts the host with an empty layout; add frames from the top bar.

    .EXAMPLE
        Start-AiHerd -NumberOfSession 3

        Starts three Claude sessions side by side.

    .EXAMPLE
        Start-AiHerd -NumberOfSession 2 -Agent Codex

        Starts two Codex sessions side by side.

    .EXAMPLE
        Start-AiHerd -NumberOfSession 2 -WorkingDirectory C:\repos\contoso

        Starts two Claude sessions in C:\repos\contoso instead of the current location.

    .NOTES
        Prerequisite (once): Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser

        A Claude frame runs non-interactively, so it cannot answer a permission prompt: any
        tool call that would need approval is refused. Add the permission flags you want to
        the command line in the top bar (--permission-mode, --allowedTools, ...) before
        pressing [Add frame].
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(0, 6)]
        [int]$NumberOfSession = 0,

        [Parameter()]
        [ValidateSet('Claude', 'Copilot', 'Codex')]
        [string]$Agent = 'Claude',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$WorkingDirectory
    )

    $ErrorActionPreference = 'Stop'

    # Agent name => command line started in each frame.
    #
    # Claude: --print is what stops it from trying to open its full-screen UI on a pipe, and
    # the stream-json pair is what keeps stdin open between turns instead of reading one
    # prompt to EOF. --verbose is required by --print with stream-json output.
    $agentCommandLine = @{
        Claude  = 'claude --print --verbose --input-format stream-json --output-format stream-json'
        Copilot = 'copilot'
        Codex   = 'codex'
    }[$Agent]

    Import-TerminalGui

    # A child process inherits the host *process* directory, which is not the PowerShell
    # location: resolve the location here so every frame starts where the user is standing.
    if (-not $PSBoundParameters.ContainsKey('WorkingDirectory')) {
        $WorkingDirectory = if ($PWD.Provider.Name -eq 'FileSystem') { $PWD.ProviderPath } else { [Environment]::CurrentDirectory }
    }
    $WorkingDirectory = (Resolve-Path -Path $WorkingDirectory).ProviderPath

    # Module-scope state, shared with the private frame functions. Reset on every run.
    $script:WorkingDirectory = $WorkingDirectory
    $script:MaxFrame = 6
    $script:MaxLine  = 300      # scroll-back kept per frame
    $script:Frames   = [System.Collections.Generic.List[psobject]]::new()

    try {
        [Terminal.Gui.Application]::Init()
        $top = [Terminal.Gui.Application]::Top

        $window = [Terminal.Gui.Window]::new("AI Herd | $Agent | $WorkingDirectory | max $script:MaxFrame frames")

        # --- top bar: command input + [Add frame] + [Quit] -----------------------
        $topBar        = [Terminal.Gui.FrameView]::new('New frame command')
        $topBar.X      = 0
        $topBar.Y      = 0
        $topBar.Width  = [Terminal.Gui.Dim]::Fill()
        $topBar.Height = 3

        # Pre-filled with the selected agent, so [Add frame] adds one more of the same.
        $commandField       = [Terminal.Gui.TextField]::new($agentCommandLine)
        $commandField.X     = 0
        $commandField.Y     = 0
        $commandField.Width = [Terminal.Gui.Dim]::Fill(24)

        $addButton   = [Terminal.Gui.Button]::new('Add frame')
        $addButton.X = [Terminal.Gui.Pos]::AnchorEnd(23)
        $addButton.Y = 0

        $quitButton   = [Terminal.Gui.Button]::new('Quit')
        $quitButton.X = [Terminal.Gui.Pos]::AnchorEnd(8)
        $quitButton.Y = 0

        $topBar.Add($commandField, $addButton, $quitButton)

        # --- frame grid ----------------------------------------------------------
        $script:FrameContainer        = [Terminal.Gui.View]::new()
        $script:FrameContainer.X      = 0
        $script:FrameContainer.Y      = 3
        $script:FrameContainer.Width  = [Terminal.Gui.Dim]::Fill()
        $script:FrameContainer.Height = [Terminal.Gui.Dim]::Fill()

        $window.Add($topBar, $script:FrameContainer)
        $top.Add($window)

        # $commandField is a local of this function, so the handler needs its own closure to
        # still see it when Terminal.Gui raises the event later. The closure also drops the
        # module session state, so New-Frame is called through its FunctionInfo: by name it
        # would not resolve from the handler.
        $newFrameCommand = Get-Command -Name 'New-Frame'

        $addButton.add_Clicked({
            $commandLine = $commandField.Text.ToString()
            if (-not [string]::IsNullOrWhiteSpace($commandLine)) {
                & $newFrameCommand -CommandLine $commandLine
            }
        }.GetNewClosure())

        $quitButton.add_Clicked({
            [Terminal.Gui.Application]::RequestStop()
        })

        # Sessions requested on the command line
        for ($i = 0; $i -lt $NumberOfSession; $i++) {
            New-Frame -CommandLine $agentCommandLine
        }

        # UI refresh pump: runs on the main loop thread, so PowerShell script blocks are safe here.
        [void][Terminal.Gui.Application]::MainLoop.AddTimeout(
            [TimeSpan]::FromMilliseconds(120),
            [Func[Terminal.Gui.MainLoop, bool]] { param($MainLoop) Update-Frame }
        )

        [Terminal.Gui.Application]::Run($top)
    }
    finally {
        # Terminate every remaining child process tree, then restore the console.
        foreach ($frame in @($script:Frames)) {
            $frame.Process.Dispose()
        }
        $script:Frames.Clear()

        if ([Terminal.Gui.Application]::Driver) {
            [Terminal.Gui.Application]::Shutdown()
        }
    }
}
