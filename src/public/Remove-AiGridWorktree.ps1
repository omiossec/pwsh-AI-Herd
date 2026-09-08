function Remove-AiGridWorktree {
    <#
    .SYNOPSIS
        Removes the git worktrees a grid created, and optionally their branches.

    .DESCRIPTION
        The counterpart of `gwt clean`. Each recorded worktree is removed with
        `git worktree remove`; a worktree with uncommitted changes is kept unless -Force is
        given. Branches are left alone unless -DeleteBranch is given, since merging the agents'
        work back is a deliberate, manual step. The grid record is updated so a later
        Resume-AiGrid runs those panes in the project directory.

    .PARAMETER Force
        Remove worktrees even when they hold uncommitted changes.

    .PARAMETER DeleteBranch
        Also delete each worktree's branch (git branch -D).

    .PARAMETER Path
        Grid file to clean, as returned by Get-AiGrid.

    .EXAMPLE
        Remove-AiGridWorktree

    .EXAMPLE
        Remove-AiGridWorktree -Force -DeleteBranch
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$DeleteBranch,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $ErrorActionPreference = 'Stop'

    $grid    = Resolve-HerdGrid -Path $Path
    $changed = $false

    foreach ($spec in $grid.Panes) {
        if (-not $spec.Worktree) { continue }

        if (Test-Path -Path $spec.Worktree -PathType Container) {
            if (-not $PSCmdlet.ShouldProcess($spec.Worktree, 'git worktree remove')) { continue }
            $arguments = @('-C', $grid.Directory, 'worktree', 'remove')
            if ($Force) { $arguments += '--force' }
            $output = & git @arguments $spec.Worktree 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Kept $($spec.Worktree): $($output -join ' ')"
                continue
            }
        }
        else {
            & git -C $grid.Directory worktree prune 2>&1 | Out-Null
        }

        if ($DeleteBranch -and $spec.Branch) {
            $output = & git -C $grid.Directory branch -D $spec.Branch 2>&1
            if ($LASTEXITCODE -ne 0) { Write-Warning "Branch $($spec.Branch) not deleted: $($output -join ' ')" }
        }

        $spec.Worktree = $null
        if ($DeleteBranch) { $spec.Branch = $null }
        $changed = $true
    }

    if ($changed) {
        [void](Save-HerdGrid -Grid $grid)
    }
}
