function New-HerdGrid {
    <#
    .SYNOPSIS
        Builds a wezterm window of N agent panes from a list of pane specs, then records it.

    .DESCRIPTION
        The one builder behind Start-AiGrid and Resume-AiGrid, so launch and reopen cannot
        drift apart. It:
          1. materialises any recorded worktree that is missing on disk (reopen),
          2. opens a new wezterm window with pane 0 (spawn if a GUI runs, start otherwise),
          3. splits the top row into columns, then fills each column top-down, row-major, so
             the last index lands bottom-right, matching the tmux version,
          4. stores the live pane ids in the specs and saves the grid file.

    .PARAMETER Pane
        Ordered pane specs: PSCustomObjects with SessionId, Agent, Effort, Task, Kickoff,
        Worktree, Branch. PaneId is filled in here.

    .PARAMETER Resume
        Reopen mode: agents resume their conversations instead of starting new ones.

    .OUTPUTS
        The grid record that was saved.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Directory,

        [Parameter(Mandatory)]
        [ValidateRange(1, 16)]
        [int]$Columns,

        [Parameter(Mandatory)]
        [ValidateRange(1, 16)]
        [int]$Rows,

        [Parameter(Mandatory)]
        [ValidateCount(1, 64)]
        [psobject[]]$Pane,

        [Parameter()]
        [switch]$Resume
    )

    $count = $Pane.Count
    if ($count -gt $Columns * $Rows) {
        throw "$count panes do not fit a $Columns x $Rows grid."
    }

    #region per-pane working directory and command
    $cwd     = [string[]]::new($count)
    $command = [object[]]::new($count)
    for ($i = 0; $i -lt $count; $i++) {
        $spec = $Pane[$i]
        if ($spec.Worktree -and -not (Test-Path -Path $spec.Worktree -PathType Container) -and $spec.Branch) {
            try {
                [void](New-HerdWorktree -Repository $Directory -Path $spec.Worktree -Branch $spec.Branch)
            }
            catch {
                Write-Warning "$($_.Exception.Message) Pane $i runs in $Directory instead."
                $spec.Worktree = $null
            }
        }
        $cwd[$i]     = if ($spec.Worktree) { $spec.Worktree } else { $Directory }
        $command[$i] = Get-AgentPaneCommand -Agent $spec.Agent -SessionId $spec.SessionId -Effort $spec.Effort `
            -Task $spec.Task -Kickoff $spec.Kickoff -Index $i -Resume:$Resume
    }
    #endregion

    #region pane 0: new window
    $known        = @(Get-WezTermPane -Quiet | ForEach-Object { [int]$_.pane_id })
    $muxReachable = $null -ne (Get-WezTermSocket) -and $null -ne (Invoke-WezTermCli -Arguments @('list') -Quiet)

    if ($muxReachable) {
        $first = [int](Invoke-WezTermCli -Arguments (@('spawn', '--new-window', '--cwd', $cwd[0], '--') + $command[0]))
    }
    else {
        # Launch the GUI executable itself rather than the `wezterm` console proxy: the proxy
        # exits as soon as it has handed over, and on Windows the GUI did not survive that.
        # ProcessStartInfo.ArgumentList quotes each element correctly on every platform, which
        # Start-Process -ArgumentList does not guarantee for arguments containing spaces.
        $wezterm = Get-WezTermPath
        $gui = Join-Path -Path (Split-Path -Path $wezterm -Parent) -ChildPath ('wezterm-gui' + [IO.Path]::GetExtension($wezterm))
        if (-not (Test-Path -Path $gui -PathType Leaf)) { $gui = $wezterm }
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new($gui)
        $startInfo.UseShellExecute = $false
        foreach ($argument in (@('start', '--cwd', $cwd[0], '--') + $command[0])) {
            $startInfo.ArgumentList.Add([string]$argument)
        }
        [void][System.Diagnostics.Process]::Start($startInfo)
        $first = Wait-WezTermPane -KnownPaneId $known
    }
    $Pane[0] | Add-Member -NotePropertyName 'PaneId' -NotePropertyValue $first -Force
    #endregion

    #region columns: split the top row left to right
    $columnTop = [int[]]::new($Columns)
    $columnTop[0] = $first
    for ($c = 1; $c -lt $Columns; $c++) {
        if ($c -ge $count) { break }
        # New pane takes (remaining columns)/(remaining columns + 1) of the pane being split.
        $remaining = $Columns - $c
        $percent   = [int][Math]::Round(100 * $remaining / ($remaining + 1))
        $id = [int](Invoke-WezTermCli -Arguments (@('split-pane', '--pane-id', $columnTop[$c - 1], '--right', '--percent', $percent, '--cwd', $cwd[$c], '--') + $command[$c]))
        $columnTop[$c] = $id
        $Pane[$c] | Add-Member -NotePropertyName 'PaneId' -NotePropertyValue $id -Force
    }
    $columnBottom = [int[]]$columnTop.Clone()
    #endregion

    #region rows: fill each column top-down, row-major
    # Columns 0..full-1 hold $Rows panes, the rest hold $Rows-1 (a partially filled last row).
    $full  = $count - $Columns * ($Rows - 1)
    $index = $Columns
    for ($r = 1; $r -lt $Rows; $r++) {
        for ($c = 0; $c -lt $Columns; $c++) {
            if ($index -ge $count) { break }
            $rowsInColumn = if ($c -lt $full) { $Rows } else { $Rows - 1 }
            if ($r -ge $rowsInColumn) { continue }
            $percent = [int][Math]::Round(($rowsInColumn - $r) * 100 / ($rowsInColumn - $r + 1))
            $id = [int](Invoke-WezTermCli -Arguments (@('split-pane', '--pane-id', $columnBottom[$c], '--bottom', '--percent', $percent, '--cwd', $cwd[$index], '--') + $command[$index]))
            $columnBottom[$c] = $id
            $Pane[$index] | Add-Member -NotePropertyName 'PaneId' -NotePropertyValue $id -Force
            $index++
        }
    }
    #endregion

    [void](Invoke-WezTermCli -Arguments @('activate-pane', '--pane-id', $first) -Quiet)

    $grid = [PSCustomObject]@{
        Version   = 1
        Directory = $Directory
        Columns   = $Columns
        Rows      = $Rows
        Saved     = $null
        Panes     = @($Pane)
    }
    $path = Save-HerdGrid -Grid $grid
    $grid | Add-Member -NotePropertyName 'Path' -NotePropertyValue $path -Force
    return $grid
}
