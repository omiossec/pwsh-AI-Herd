function Send-FrameInput {
    <#
    .SYNOPSIS
        Writes the frame's input line to the child process stdin.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Frame
    )

    if ($Frame.Process.HasExited) {
        return
    }

    $text = $Frame.Input.Text.ToString()
    $Frame.Process.SendLine($text)
    $Frame.Lines.Add("> $text")
    $Frame.Input.Text = ''
    Update-FrameView -Frame $Frame
}
