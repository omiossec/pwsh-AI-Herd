function Wait-WezTermPane {
    <#
    .SYNOPSIS
        Waits for a pane that was not in the known set to appear, and returns its id.

    .DESCRIPTION
        `wezterm start` launches the GUI asynchronously and prints nothing, so the first pane
        of a fresh window has to be discovered by polling `wezterm cli list`.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter()]
        [int[]]$KnownPaneId = @(),

        [Parameter()]
        [ValidateRange(1, 120)]
        [int]$TimeoutSecond = 20
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSecond)
    do {
        $pane = @(Get-WezTermPane -Quiet | Where-Object { $_.pane_id -notin $KnownPaneId })
        if ($pane.Count -gt 0) {
            return [int]($pane | Sort-Object -Property pane_id | Select-Object -First 1).pane_id
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "wezterm did not open a pane within $TimeoutSecond s."
}
