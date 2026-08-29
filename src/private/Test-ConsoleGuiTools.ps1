function Test-ConsoleGuiTools {
    <#
    .SYNOPSIS
        Tests whether the Microsoft.PowerShell.ConsoleGuiTools module is installed.

    .DESCRIPTION
        Returns $true when the module is available on this machine, $false otherwise.
        ConsoleGuiTools is never imported by pwsh-ai-herd; it is only the delivery vehicle for
        the Terminal.Gui and NStack assemblies, so availability is checked with
        Get-Module -ListAvailable rather than by importing it.

    .PARAMETER MinimumVersion
        Optional lowest acceptable module version. Versions below it count as not installed.

    .EXAMPLE
        Test-ConsoleGuiTools

        Returns $true if any version of the module is installed.

    .EXAMPLE
        Test-ConsoleGuiTools -MinimumVersion '0.7.7'

        Returns $true only if version 0.7.7 or later is installed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [version]$MinimumVersion
    )

    $module = @(Get-Module -Name 'Microsoft.PowerShell.ConsoleGuiTools' -ListAvailable -ErrorAction SilentlyContinue)

    if ($module.Count -eq 0) {
        return $false
    }

    if ($PSBoundParameters.ContainsKey('MinimumVersion')) {
        return [bool]($module | Where-Object { $_.Version -ge $MinimumVersion })
    }

    return $true
}
