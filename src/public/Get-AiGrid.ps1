function Get-AiGrid {
    <#
    .SYNOPSIS
        Lists the grids recorded by Start-AiGrid, newest first.

    .DESCRIPTION
        One record per project directory. Grids whose directory no longer exists are skipped.
        Pipe a record to Resume-AiGrid to reopen it.

    .PARAMETER WorkingDirectory
        Only the grid recorded for this project directory.

    .EXAMPLE
        Get-AiGrid | Format-Table Saved, Directory, Columns, Rows, @{ n = 'Agents'; e = { $_.Panes.Count } }
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$WorkingDirectory
    )

    if ($WorkingDirectory) {
        Read-HerdGrid -Directory (Resolve-Path -Path $WorkingDirectory).ProviderPath
    }
    else {
        Read-HerdGrid
    }
}
