function Close-Frame {
    <#
    .SYNOPSIS
        Kills the frame's process tree, removes the frame from the window, re-layouts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Frame
    )

    $Frame.Process.Dispose()
    [void]$script:Frames.Remove($Frame)
    $script:FrameContainer.Remove($Frame.View)
    Set-FrameLayout
}
