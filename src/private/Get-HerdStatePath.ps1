function Get-HerdStatePath {
    <#
    .SYNOPSIS
        Returns the directory where grid files and worktrees are kept, creating it if needed.

    .DESCRIPTION
        %LOCALAPPDATA%\pwsh-ai-herd on Windows, $XDG_STATE_HOME/pwsh-ai-herd (default
        ~/.local/state/pwsh-ai-herd) elsewhere.

    .PARAMETER ChildPath
        Optional sub-directory ('grids', 'worktrees', ...) appended to the root.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$ChildPath
    )

    if ($IsWindows) {
        $root = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'pwsh-ai-herd'
    }
    else {
        $base = if ($env:XDG_STATE_HOME) { $env:XDG_STATE_HOME } else { Join-Path -Path $HOME -ChildPath '.local/state' }
        $root = Join-Path -Path $base -ChildPath 'pwsh-ai-herd'
    }

    if ($ChildPath) {
        $root = Join-Path -Path $root -ChildPath $ChildPath
    }

    if (-not (Test-Path -Path $root -PathType Container)) {
        [void](New-Item -Path $root -ItemType Directory -Force)
    }

    return $root
}
