function Resume-AiGrid {
    <#
    .SYNOPSIS
        Reopens a recorded grid: same layout, each agent resuming its own conversation.

    .DESCRIPTION
        The counterpart of `sr` in agentic-config. Start-AiGrid starts new work; Resume-AiGrid
        returns to work in progress. Claude panes resume by their pinned session id, Codex
        panes continue the most recent session in their directory, Copilot panes use --resume.
        Recorded worktrees that vanished from disk are recreated on their branch.

        Without parameters the grid recorded for the current directory is reopened. Use
        Get-AiGrid to list every recorded grid and pipe one in, or pass its -Path.

    .PARAMETER Path
        A grid file, as returned by Get-AiGrid.

    .PARAMETER WorkingDirectory
        Reopen the grid recorded for this project directory. Defaults to the current location.

    .EXAMPLE
        Resume-AiGrid

    .EXAMPLE
        Get-AiGrid | Select-Object -First 1 | Resume-AiGrid
    #>
    [CmdletBinding(DefaultParameterSetName = 'Directory', SupportsShouldProcess)]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(ParameterSetName = 'Directory')]
        [ValidateNotNullOrEmpty()]
        [string]$WorkingDirectory
    )

    process {
        $ErrorActionPreference = 'Stop'

        $grid = if ($PSCmdlet.ParameterSetName -eq 'Path') {
            Resolve-HerdGrid -Path $Path
        }
        elseif ($WorkingDirectory) {
            Resolve-HerdGrid -Directory $WorkingDirectory
        }
        else {
            Resolve-HerdGrid -Directory (Get-Location).ProviderPath
        }

        if (-not (Test-Path -Path $grid.Directory -PathType Container)) {
            throw "The project directory of this grid is gone: $($grid.Directory)"
        }

        if (-not $PSCmdlet.ShouldProcess($grid.Directory, "reopen a $($grid.Columns) x $($grid.Rows) WezTerm grid of $($grid.Panes.Count) agent(s)")) {
            return
        }

        # Stale live ids from the previous wezterm instance; the builder assigns new ones.
        foreach ($spec in $grid.Panes) {
            $spec.PaneId = $null
        }

        New-HerdGrid -Directory $grid.Directory -Columns $grid.Columns -Rows $grid.Rows -Pane @($grid.Panes) -Resume
    }
}
