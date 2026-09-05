function Save-HerdGrid {
    <#
    .SYNOPSIS
        Writes a grid record to its per-project JSON file.

    .DESCRIPTION
        The record is what Resume-AiGrid rebuilds from: directory, geometry, and one entry per
        pane (session id, agent, effort, task, worktree, branch, and the live wezterm pane id,
        which is only valid while that wezterm instance runs).

    .OUTPUTS
        The path of the file written.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$Grid
    )

    $Grid.Saved = [DateTimeOffset]::Now.ToString('o')
    $path = Get-HerdGridPath -Directory $Grid.Directory
    $Grid | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding utf8
    return $path
}
