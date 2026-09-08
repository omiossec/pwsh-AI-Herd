function Send-AiGridText {
    <#
    .SYNOPSIS
        Types the same text into every agent pane of a grid (broadcast).

    .DESCRIPTION
        The counterpart of `gbcast`. The text is pasted into each live pane, then Enter is
        sent, so each agent receives it as a prompt. Panes that are no longer open are skipped.

    .PARAMETER Text
        The prompt to send.

    .PARAMETER NoEnter
        Paste the text without pressing Enter afterwards.

    .PARAMETER PaneIndex
        Only these pane indexes (0-based, as recorded by Start-AiGrid). Default: all.

    .PARAMETER Path
        Grid file to target, as returned by Get-AiGrid.

    .EXAMPLE
        Send-AiGridText -Text 'Run the test suite and report failures only.'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Text,

        [Parameter()]
        [switch]$NoEnter,

        [Parameter()]
        [int[]]$PaneIndex,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    process {
        $ErrorActionPreference = 'Stop'

        $grid = Resolve-HerdGrid -Path $Path
        $live = @(Get-WezTermPane | ForEach-Object { [int]$_.pane_id })

        foreach ($spec in $grid.Panes) {
            if ($PaneIndex -and $spec.Index -notin $PaneIndex) { continue }
            if ($spec.PaneId -notin $live) {
                Write-Verbose "Pane $($spec.Index) (wezterm pane $($spec.PaneId)) is not open; skipped."
                continue
            }
            if (-not $PSCmdlet.ShouldProcess("pane $($spec.Index)", 'send text')) { continue }

            [void](Invoke-WezTermCli -Arguments @('send-text', '--pane-id', $spec.PaneId, $Text))
            if (-not $NoEnter) {
                [void](Invoke-WezTermCli -Arguments @('send-text', '--pane-id', $spec.PaneId, '--no-paste', "`r"))
            }
        }
    }
}
