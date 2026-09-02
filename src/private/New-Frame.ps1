function New-Frame {
    <#
    .SYNOPSIS
        Starts a child process for the given command line and adds its frame to the grid.

    .PARAMETER WorkingDirectory
        Directory the process starts in. Defaults to the location Start-AiHerd was run from:
        a child process otherwise inherits the host process directory, which is not the
        PowerShell location the user sees.

    .NOTES
        The button/key handlers capture $frame, so they must be built with .GetNewClosure():
        without it every handler would act on the last frame created.

        .GetNewClosure() has a price: the closure loses the module session state, so a handler
        cannot resolve module-private functions by name (Terminal.Gui reports 'The term
        Send-FrameInput is not recognized...'). Calling through the FunctionInfo captured in
        the closure runs the function in its own module scope, where the private helpers and
        the $script: state are visible again.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CommandLine,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$WorkingDirectory = $script:WorkingDirectory
    )

    if ($script:Frames.Count -ge $script:MaxFrame) {
        [void][Terminal.Gui.MessageBox]::ErrorQuery('Frame limit', "Maximum of $($script:MaxFrame) frames reached.", 'Ok')
        return
    }

    # Agents launched with --input-format stream-json speak newline-delimited JSON on both
    # pipes; anything else is treated as a plain line-oriented CLI.
    $protocol = if ($CommandLine -match '--input-format\s+stream-json') { 'StreamJson' } else { 'Text' }

    $parsed = Split-CommandLine -CommandLine $CommandLine
    try {
        $process = [FrameHost.FrameProcess]::new($parsed.FileName, $parsed.Arguments, $WorkingDirectory)
    }
    catch {
        $err = $_
        [void][Terminal.Gui.MessageBox]::ErrorQuery('Start failed', $err.Exception.Message, 'Ok')
        return
    }

    $frameView = [Terminal.Gui.FrameView]::new("PID $($process.Id) | $CommandLine")

    $list        = [Terminal.Gui.ListView]::new()
    $list.X      = 0
    $list.Y      = 0
    $list.Width  = [Terminal.Gui.Dim]::Fill()
    $list.Height = [Terminal.Gui.Dim]::Fill(1)

    $inputField       = [Terminal.Gui.TextField]::new('')
    $inputField.X     = 0
    $inputField.Y     = [Terminal.Gui.Pos]::AnchorEnd(1)
    $inputField.Width = [Terminal.Gui.Dim]::Fill(19)

    $sendButton   = [Terminal.Gui.Button]::new('Send')
    $sendButton.X = [Terminal.Gui.Pos]::AnchorEnd(18)
    $sendButton.Y = [Terminal.Gui.Pos]::AnchorEnd(1)

    $closeButton   = [Terminal.Gui.Button]::new('Close')
    $closeButton.X = [Terminal.Gui.Pos]::AnchorEnd(9)
    $closeButton.Y = [Terminal.Gui.Pos]::AnchorEnd(1)

    $frameView.Add($list, $inputField, $sendButton, $closeButton)

    $frame = [PSCustomObject]@{
        Process     = $process
        View        = $frameView
        List        = $list
        Input       = $inputField
        Lines       = [System.Collections.Generic.List[string]]::new()
        CommandLine = $CommandLine
        Protocol    = $protocol
        Directory   = $WorkingDirectory
        ExitNoted   = $false
    }
    $script:Frames.Add($frame)

    $sendCommand  = Get-Command -Name 'Send-FrameInput'
    $closeCommand = Get-Command -Name 'Close-Frame'

    $sendButton.add_Clicked({ & $sendCommand -Frame $frame }.GetNewClosure())
    $closeButton.add_Clicked({ & $closeCommand -Frame $frame }.GetNewClosure())

    # Enter inside the input field == [Send]
    $inputField.add_KeyPress({
        param($keyEventArgs)
        if ($keyEventArgs.KeyEvent.Key -eq [Terminal.Gui.Key]::Enter) {
            & $sendCommand -Frame $frame
            $keyEventArgs.Handled = $true
        }
    }.GetNewClosure())

    $script:FrameContainer.Add($frameView)
    Set-FrameLayout
}
