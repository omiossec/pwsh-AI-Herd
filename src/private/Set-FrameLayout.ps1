function Set-FrameLayout {
    <#
    .SYNOPSIS
        Lays the current frames out in a grid (1x1, 2x1, 2x2, 3x2, ...).
    #>
    [CmdletBinding()]
    param()

    $count = $script:Frames.Count
    if ($count -eq 0) {
        $script:FrameContainer.SetNeedsDisplay()
        return
    }

    $columnCount = [int][Math]::Ceiling([Math]::Sqrt($count))
    $rowCount    = [int][Math]::Ceiling($count / $columnCount)

    for ($i = 0; $i -lt $count; $i++) {
        $column = $i % $columnCount
        $row    = [int][Math]::Floor($i / $columnCount)
        $view   = $script:Frames[$i].View

        $view.X = [Terminal.Gui.Pos]::Percent(100.0 * $column / $columnCount)
        $view.Y = [Terminal.Gui.Pos]::Percent(100.0 * $row / $rowCount)

        # Let the last column/row absorb the rounding leftovers of Percent().
        $view.Width  = if ($column -eq $columnCount - 1) { [Terminal.Gui.Dim]::Fill() }
                       else { [Terminal.Gui.Dim]::Percent(100.0 / $columnCount) }
        $view.Height = if ($row -eq $rowCount - 1) { [Terminal.Gui.Dim]::Fill() }
                       else { [Terminal.Gui.Dim]::Percent(100.0 / $rowCount) }
    }

    $script:FrameContainer.LayoutSubviews()
    $script:FrameContainer.SetNeedsDisplay()
}
