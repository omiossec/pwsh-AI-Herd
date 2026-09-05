function Get-HerdGridPath {
    <#
    .SYNOPSIS
        Returns the grid file that records the grid launched from a given project directory.

    .DESCRIPTION
        One grid per project: the file name is the MD5 of the normalised directory path, so
        relaunching in the same folder overwrites the previous record.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Directory
    )

    $normalised = $Directory.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($IsWindows) {
        $normalised = $normalised.ToLowerInvariant()
    }

    $md5  = [System.Security.Cryptography.MD5]::Create()
    $hash = $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalised))
    $md5.Dispose()
    $key  = [BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant()

    return Join-Path -Path (Get-HerdStatePath -ChildPath 'grids') -ChildPath "$key.json"
}
