function Update-FrameView {
    <#
    .SYNOPSIS
        Refreshes one frame's output list and keeps it scrolled to the bottom.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Frame
    )

    $Frame.List.SetSource($Frame.Lines.ToArray())

    $visible = $Frame.List.Bounds.Height
    if ($visible -gt 0 -and $Frame.Lines.Count -gt $visible) {
        $Frame.List.TopItem = $Frame.Lines.Count - $visible
    }
    $Frame.List.SetNeedsDisplay()
}
