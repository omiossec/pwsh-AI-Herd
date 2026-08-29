function New-Frame {
    <#
    .SYNOPSIS
        Starts a child process for the given command line and adds its frame to the grid.

    .NOTES
        The button/key handlers capture $frame, so they must be built with .GetNewClosure():
        without it every handler would act on the last frame created.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CommandLine
    )

    if ($script:Frames.Count -ge $script:MaxFrame) {
        [void][Terminal.Gui.MessageBox]::ErrorQuery('Frame limit', "Maximum of $($script:MaxFrame) frames reached.", 'Ok')
        return
    }

    $parsed = Split-CommandLine -CommandLine $CommandLine
    try {
        $process = [FrameHost.FrameProcess]::new($parsed.FileName, $parsed.Arguments)
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
        ExitNoted   = $false
    }
    $script:Frames.Add($frame)

    $sendButton.add_Clicked({ Send-FrameInput -Frame $frame }.GetNewClosure())
    $closeButton.add_Clicked({ Close-Frame -Frame $frame }.GetNewClosure())

    # Enter inside the input field == [Send]
    $inputField.add_KeyPress({
        param($keyEventArgs)
        if ($keyEventArgs.KeyEvent.Key -eq [Terminal.Gui.Key]::Enter) {
            Send-FrameInput -Frame $frame
            $keyEventArgs.Handled = $true
        }
    }.GetNewClosure())

    $script:FrameContainer.Add($frameView)
    Set-FrameLayout
}
