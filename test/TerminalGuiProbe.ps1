<#
    Sets $script:HasTerminalGui for the test files that need real Terminal.Gui views.

    Dot-sourced at FILE scope, not from a BeforeAll block: Pester evaluates the -Skip argument
    of a Describe during discovery, and anything a BeforeAll sets is not there yet. Probing in
    the wrong place silently skips every test in the file.

    The probe mirrors Import-TerminalGui rather than calling it, so it does not depend on the
    module having been imported yet at discovery time. Views construct without
    Application.Init, so loading the assemblies is enough and no console is taken over.
#>

$script:HasTerminalGui = $null -ne ('Terminal.Gui.Application' -as [type])

if (-not $script:HasTerminalGui) {
    $consoleGuiTools = Get-Module -Name 'Microsoft.PowerShell.ConsoleGuiTools' -ListAvailable |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1

    if ($consoleGuiTools) {
        try {
            foreach ($assemblyName in 'NStack.dll', 'Terminal.Gui.dll') {
                $assemblyPath = Join-Path -Path $consoleGuiTools.ModuleBase -ChildPath $assemblyName
                if (Test-Path -Path $assemblyPath) {
                    Add-Type -Path $assemblyPath -ErrorAction Stop
                }
            }
            $script:HasTerminalGui = $null -ne ('Terminal.Gui.Application' -as [type])
        }
        catch {
            $script:HasTerminalGui = $false
        }
    }
}
