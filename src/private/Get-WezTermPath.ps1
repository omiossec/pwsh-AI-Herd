function Get-WezTermPath {
    <#
    .SYNOPSIS
        Locates the wezterm CLI executable.

    .DESCRIPTION
        Looks on PATH first, then in the default install locations (the Windows installer does
        not always add itself to PATH). Throws with an install hint when nothing is found,
        because every grid command needs it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $command = Get-Command -Name 'wezterm' -CommandType Application -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidate = @()
    if ($IsWindows) {
        $candidate += Join-Path -Path $env:ProgramFiles -ChildPath 'WezTerm\wezterm.exe'
        if ($env:LOCALAPPDATA) {
            $candidate += Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs\WezTerm\wezterm.exe'
            $candidate += Join-Path -Path $env:LOCALAPPDATA -ChildPath 'wezterm\wezterm.exe'
        }
    }
    elseif ($IsMacOS) {
        $candidate += '/Applications/WezTerm.app/Contents/MacOS/wezterm'
        $candidate += '/opt/homebrew/bin/wezterm'
    }
    else {
        $candidate += '/usr/bin/wezterm', '/usr/local/bin/wezterm', '/var/lib/flatpak/exports/bin/org.wezfurlong.wezterm'
    }

    foreach ($path in $candidate) {
        if (Test-Path -Path $path -PathType Leaf) {
            return $path
        }
    }

    throw 'wezterm was not found. Install WezTerm (https://wezterm.org; on Windows: winget install wez.wezterm) and make sure wezterm is on PATH.'
}
