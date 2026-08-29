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
        therefore be started in their non-interactive / streaming mode.

    .PARAMETER Command
        Zero to six command lines to start immediately, one frame per command line.
        The first token is the executable, the rest is passed as arguments.
        Quote the executable ("...") if its path contains spaces.

    .EXAMPLE
        Start-AiHerd

        Starts the host with an empty layout; add frames from the top bar.

    .EXAMPLE
        Start-AiHerd -Command 'ping 127.0.0.1', 'pwsh -NoProfile -Command "1..999 | ForEach-Object { $_; Start-Sleep 1 }"'

        Starts the host with two frames already running.

    .NOTES
        Prerequisite (once): Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateCount(0, 6)]
        [string[]]$Command = @()
    )

    $ErrorActionPreference = 'Stop'

    Import-TerminalGui

    # Module-scope state, shared with the private frame functions. Reset on every run.
    $script:MaxFrame = 6
    $script:MaxLine  = 300      # scroll-back kept per frame
    $script:Frames   = [System.Collections.Generic.List[psobject]]::new()

    try {
        [Terminal.Gui.Application]::Init()
        $top = [Terminal.Gui.Application]::Top

        $window = [Terminal.Gui.Window]::new("AI Herd | pwsh $($PSVersionTable.PSVersion) | max $script:MaxFrame frames")

        # --- top bar: command input + [Add frame] + [Quit] -----------------------
        $topBar        = [Terminal.Gui.FrameView]::new('New frame command')
        $topBar.X      = 0
        $topBar.Y      = 0
        $topBar.Width  = [Terminal.Gui.Dim]::Fill()
        $topBar.Height = 3

        $defaultCommand = if ($IsWindows) { 'ping -t 127.0.0.1' } else { 'ping 127.0.0.1' }

        $commandField       = [Terminal.Gui.TextField]::new($defaultCommand)
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
        # still see it when Terminal.Gui raises the event later.
        $addButton.add_Clicked({
            $commandLine = $commandField.Text.ToString()
            if (-not [string]::IsNullOrWhiteSpace($commandLine)) {
                New-Frame -CommandLine $commandLine
            }
        }.GetNewClosure())

        $quitButton.add_Clicked({
            [Terminal.Gui.Application]::RequestStop()
        })

        # Frames requested on the command line
        foreach ($commandLine in $Command) {
            New-Frame -CommandLine $commandLine
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
