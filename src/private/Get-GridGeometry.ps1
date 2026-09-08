function Get-GridGeometry {
    <#
    .SYNOPSIS
        Works out how many columns and rows a grid of N agents needs.

    .DESCRIPTION
        Auto layout picks the smallest square-ish grid with columns >= rows (6 -> 3 x 2).
        An explicit Columns/Rows pair is used as is and fixes the count to Columns * Rows.

    .OUTPUTS
        PSCustomObject with Count, Columns, Rows.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Count')]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Count')]
        [ValidateRange(1, 64)]
        [int]$Count,

        [Parameter(Mandatory, ParameterSetName = 'Matrix')]
        [ValidateRange(1, 16)]
        [int]$Columns,

        [Parameter(Mandatory, ParameterSetName = 'Matrix')]
        [ValidateRange(1, 16)]
        [int]$Rows
    )

    if ($PSCmdlet.ParameterSetName -eq 'Matrix') {
        return [PSCustomObject]@{ Count = $Columns * $Rows; Columns = $Columns; Rows = $Rows }
    }

    $columns = 1
    while ($columns * $columns -lt $Count) { $columns++ }
    $rows = [int][Math]::Ceiling($Count / $columns)

    return [PSCustomObject]@{ Count = $Count; Columns = $columns; Rows = $rows }
}
