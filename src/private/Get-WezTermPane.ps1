function Get-WezTermPane {
    <#
    .SYNOPSIS
        Lists the panes of the running wezterm (wezterm cli list --format json).

    .PARAMETER Quiet
        Return nothing instead of throwing when no wezterm mux server is reachable, i.e. when
        no wezterm GUI is running.

    .OUTPUTS
        One PSCustomObject per pane: window_id, tab_id, pane_id, workspace, size, title, cwd, ...
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter()]
        [switch]$Quiet
    )

    $json = Invoke-WezTermCli -Arguments @('list', '--format', 'json') -Quiet:$Quiet
    if ([string]::IsNullOrWhiteSpace($json)) {
        return @()
    }
    return @($json | ConvertFrom-Json)
}
