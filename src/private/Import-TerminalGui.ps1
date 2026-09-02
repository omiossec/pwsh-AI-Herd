function Import-TerminalGui {
    <#
    .SYNOPSIS
        Loads Terminal.Gui and NStack from the Microsoft.PowerShell.ConsoleGuiTools module base.

    .DESCRIPTION
        ConsoleGuiTools is never imported as a module, it is only the delivery vehicle for the
        two assemblies. Called at run time from Start-AiHerd (not at module import) so that
        importing pwsh-ai-herd stays possible on a machine that does not have it installed.
    #>
    [CmdletBinding()]
    param()

    if ('Terminal.Gui.Application' -as [type]) {
        return
    }

    if (-not (Test-ConsoleGuiTools)) {
        throw ("Module 'Microsoft.PowerShell.ConsoleGuiTools' not found (it ships Terminal.Gui). " +
               'Install it once with: Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser')
    }

    $consoleGuiTools = Get-Module -Name 'Microsoft.PowerShell.ConsoleGuiTools' -ListAvailable |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1

    foreach ($assemblyName in 'NStack.dll', 'Terminal.Gui.dll') {
        $assemblyPath = Join-Path -Path $consoleGuiTools.ModuleBase -ChildPath $assemblyName
        if (Test-Path -Path $assemblyPath) {
            Add-Type -Path $assemblyPath
        }
    }

    if (-not ('Terminal.Gui.Application' -as [type])) {
        throw "Terminal.Gui.dll could not be loaded from '$($consoleGuiTools.ModuleBase)'."
    }
}
