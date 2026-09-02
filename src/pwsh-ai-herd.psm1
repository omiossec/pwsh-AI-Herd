#Requires -Version 7.0

Set-StrictMode -Version Latest

<#
    Module loader.

    Dot-sources, in order: class -> private -> public, then exports only the public
    functions. Order matters: classes must exist before any function that types a
    parameter with them, so name class files with a numeric prefix (00-, 10-, ...)
    when one class depends on another.
#>

$script:ModuleRoot = $PSScriptRoot

$classFile   = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'class')   -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object -Property FullName)
$privateFile = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'private') -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object -Property FullName)
$publicFile  = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'public')  -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object -Property FullName)

foreach ($file in $classFile + $privateFile + $publicFile) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to import '$($file.FullName)': $($_.Exception.Message)"
    }
}

if ($publicFile.Count -gt 0) {
    Export-ModuleMember -Function $publicFile.BaseName
}
