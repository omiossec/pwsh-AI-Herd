function New-HerdWorktree {
    <#
    .SYNOPSIS
        Creates (or reuses) a git worktree on its own branch for one agent.

    .DESCRIPTION
        Idempotent: an existing directory is returned untouched, an existing branch is checked
        out rather than recreated, a new branch is created from the repository HEAD.

    .OUTPUTS
        PSCustomObject with Path and Branch.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Repository,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Branch
    )

    & git -C $Repository rev-parse --is-inside-work-tree 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "$Repository is not a git repository; worktree isolation needs one."
    }

    if (Test-Path -Path $Path -PathType Container) {
        return [PSCustomObject]@{ Path = $Path; Branch = $Branch }
    }

    $parent = Split-Path -Path $Path -Parent
    if (-not (Test-Path -Path $parent -PathType Container)) {
        [void](New-Item -Path $parent -ItemType Directory -Force)
    }

    & git -C $Repository show-ref --verify --quiet "refs/heads/$Branch" 2>&1 | Out-Null
    $output = if ($LASTEXITCODE -eq 0) {
        & git -C $Repository worktree add -q $Path $Branch 2>&1
    }
    else {
        & git -C $Repository worktree add -q -b $Branch $Path 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        throw "git worktree add failed for $Branch : $($output -join ' ')"
    }

    return [PSCustomObject]@{ Path = $Path; Branch = $Branch }
}
