function Add-AiGridAgent {
    <#
    .SYNOPSIS
        Adds one agent pane to a running grid and records it.

    .DESCRIPTION
        The counterpart of `gadd`. The new pane is split off the grid's last pane (bottom),
        starts in the project directory (or a fresh worktree with -Worktree) and gets a pinned
        session id like the others, so Resume-AiGrid brings it back too.

        The grid is found from the pane you type in ($env:WEZTERM_PANE) or from the current
        directory; pass -Path to target another one.

    .PARAMETER Agent
        Claude (default), Codex or Copilot.

    .PARAMETER Task
        A label shown in the pane title (and the herd_task wezterm user var).

    .PARAMETER Kickoff
        First prompt sent to the new agent.

    .PARAMETER Worktree
        Isolate the new agent in its own git worktree, like Start-AiGrid -Worktree.

    .PARAMETER Path
        Grid file to add to, as returned by Get-AiGrid.

    .EXAMPLE
        Add-AiGridAgent -Agent Codex -Task review
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([psobject])]
    param(
        [Parameter()]
        [ValidateSet('Claude', 'Codex', 'Copilot')]
        [string]$Agent = 'Claude',

        [Parameter()]
        [string]$Task,

        [Parameter()]
        [string]$Kickoff,

        [Parameter()]
        [switch]$Worktree,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $ErrorActionPreference = 'Stop'

    $grid  = Resolve-HerdGrid -Path $Path
    $live  = @(Get-WezTermPane | ForEach-Object { [int]$_.pane_id })
    $index = $grid.Panes.Count

    $anchor = @($grid.Panes | Where-Object { $_.PaneId -in $live } | Select-Object -Last 1)
    if ($anchor.Count -eq 0) {
        throw 'None of the recorded panes is open in the running wezterm. Use Resume-AiGrid to reopen the grid first.'
    }

    if (-not $PSCmdlet.ShouldProcess("pane $($anchor[0].PaneId)", "split and start $Agent")) {
        return
    }

    $spec = [PSCustomObject]@{
        Index     = $index
        SessionId = [guid]::NewGuid().ToString()
        Agent     = $Agent
        Effort    = 'default'
        Task      = $Task
        Kickoff   = $Kickoff
        Worktree  = $null
        Branch    = $null
        PaneId    = $null
    }

    if ($Worktree) {
        $safeName = (Split-Path -Path $grid.Directory -Leaf) -replace '[^A-Za-z0-9_-]', '_'
        $session  = '{0}-{1}' -f $safeName, [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $wt = New-HerdWorktree -Repository $grid.Directory `
            -Path (Join-Path -Path (Get-HerdStatePath -ChildPath 'worktrees') -ChildPath "$session/$($index + 1)") `
            -Branch "herd/$session-$($index + 1)"
        $spec.Worktree = $wt.Path
        $spec.Branch   = $wt.Branch
    }

    $cwd     = if ($spec.Worktree) { $spec.Worktree } else { $grid.Directory }
    $command = Get-AgentPaneCommand -Agent $Agent -SessionId $spec.SessionId -Task $Task -Kickoff $Kickoff -Index $index

    $spec.PaneId = [int](Invoke-WezTermCli -Arguments (@('split-pane', '--pane-id', $anchor[0].PaneId, '--bottom', '--cwd', $cwd, '--') + $command))

    $grid.Panes = @($grid.Panes) + $spec
    if ($grid.Panes.Count -gt $grid.Columns * $grid.Rows) {
        $grid.Rows = [int][Math]::Ceiling($grid.Panes.Count / $grid.Columns)
    }
    [void](Save-HerdGrid -Grid $grid)
    return $spec
}
