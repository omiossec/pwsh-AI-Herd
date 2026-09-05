function Read-HerdGrid {
    <#
    .SYNOPSIS
        Loads grid records from disk.

    .DESCRIPTION
        -Path reads one file. -Directory reads the record of the grid launched from that
        project directory. With neither, every record whose project directory still exists is
        returned, newest first. Missing records yield nothing rather than an error.

    .OUTPUTS
        Grid PSCustomObjects (see Save-HerdGrid), each with an extra Path property.
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Directory')]
        [ValidateNotNullOrEmpty()]
        [string]$Directory
    )

    $file = switch ($PSCmdlet.ParameterSetName) {
        'Path'      { Get-Item -Path $Path -ErrorAction SilentlyContinue }
        'Directory' { Get-Item -Path (Get-HerdGridPath -Directory $Directory) -ErrorAction SilentlyContinue }
        default     { Get-ChildItem -Path (Get-HerdStatePath -ChildPath 'grids') -Filter '*.json' -File | Sort-Object -Property LastWriteTime -Descending }
    }

    foreach ($item in @($file)) {
        if (-not $item) { continue }
        try {
            $grid = Get-Content -Path $item.FullName -Raw | ConvertFrom-Json
        }
        catch {
            Write-Warning "Skipping unreadable grid file $($item.FullName): $($_.Exception.Message)"
            continue
        }
        if ($PSCmdlet.ParameterSetName -eq 'All' -and -not (Test-Path -Path $grid.Directory -PathType Container)) {
            continue
        }
        # ConvertFrom-Json yields a single object for a one-element array; keep Panes a list.
        $grid.Panes = @($grid.Panes)
        $grid | Add-Member -NotePropertyName 'Path' -NotePropertyValue $item.FullName -Force
        $grid
    }
}
