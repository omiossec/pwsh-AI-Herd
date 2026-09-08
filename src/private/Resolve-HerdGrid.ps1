function Resolve-HerdGrid {
    <#
    .SYNOPSIS
        Finds the grid a command should act on.

    .DESCRIPTION
        Resolution order: an explicit -Path, then the grid whose record contains the pane the
        caller is typing in ($env:WEZTERM_PANE, set inside every wezterm pane), then the grid
        launched from -Directory (default: the current location). Throws when nothing matches.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter()]
        [string]$Directory
    )

    if ($Path) {
        $grid = Read-HerdGrid -Path $Path
        if (-not $grid) { throw "No grid file at $Path." }
        return $grid
    }

    if ($env:WEZTERM_PANE -and -not $Directory) {
        $paneId = [int]$env:WEZTERM_PANE
        $grid = Read-HerdGrid | Where-Object { $paneId -in @($_.Panes.PaneId) } | Select-Object -First 1
        if ($grid) { return $grid }
    }

    if (-not $Directory) {
        $Directory = if ($PWD.Provider.Name -eq 'FileSystem') { $PWD.ProviderPath } else { [Environment]::CurrentDirectory }
    }
    $Directory = (Resolve-Path -Path $Directory).ProviderPath

    $grid = Read-HerdGrid -Directory $Directory
    if (-not $grid) {
        throw "No grid was launched from $Directory. Run Start-AiGrid there first, or pass -Path."
    }
    return $grid
}
