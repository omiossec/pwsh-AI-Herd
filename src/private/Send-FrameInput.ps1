function Send-FrameInput {
    <#
    .SYNOPSIS
        Writes the frame's input line to the child process stdin.

    .DESCRIPTION
        A 'Text' frame gets the raw line. A 'StreamJson' frame gets the line wrapped in the
        user-message envelope the agent expects on stdin; the frame echoes the typed text,
        not the JSON.
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

    if ($Frame.Protocol -eq 'StreamJson') {
        $payload = @{
            type    = 'user'
            message = @{
                role    = 'user'
                content = @(@{ type = 'text'; text = $text })
            }
        } | ConvertTo-Json -Depth 6 -Compress

        $Frame.Process.SendLine($payload)
    }
    else {
        $Frame.Process.SendLine($text)
    }

    $Frame.Lines.Add("> $text")
    $Frame.Input.Text = ''
    Update-FrameView -Frame $Frame
}
