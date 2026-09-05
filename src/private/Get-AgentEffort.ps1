function Get-AgentEffort {
    <#
    .SYNOPSIS
        Spreads reasoning effort over the panes of a grid.

    .DESCRIPTION
        Same distribution as agentic-config: the last pane runs low, roughly a quarter run
        medium, the rest run at the default level. A single pane always runs default.

    .OUTPUTS
        string[] of 'default' | 'medium' | 'low', one per pane, in pane order.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 64)]
        [int]$Count
    )

    if ($Count -eq 1) {
        return [string[]]@('default')
    }

    $low    = 1
    $medium = [int][Math]::Floor(($Count + 2) / 4)
    if ($Count - $low - $medium -lt 1) { $medium = $Count - $low - 1 }
    if ($medium -lt 0) { $medium = 0 }

    $result = for ($position = 0; $position -lt $Count; $position++) {
        if     ($position -ge $Count - $low)           { 'low' }
        elseif ($position -ge $Count - $low - $medium) { 'medium' }
        else                                           { 'default' }
    }
    return [string[]]$result
}
