# Probed at file scope because Pester evaluates -Skip during discovery, before BeforeAll runs.
$script:HasConsoleGuiTools = [bool](Get-Module -Name 'Microsoft.PowerShell.ConsoleGuiTools' -ListAvailable)

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
}

Describe 'Import-TerminalGui' {

    Context 'when ConsoleGuiTools is installed' -Skip:(-not $script:HasConsoleGuiTools) {

        It 'loads without error' {
            { InModuleScope pwsh-ai-herd { Import-TerminalGui } } | Should -Not -Throw
        }

        It 'makes the Terminal.Gui application type available' {
            InModuleScope pwsh-ai-herd { Import-TerminalGui }

            'Terminal.Gui.Application' -as [type] | Should -Not -BeNullOrEmpty
        }

        It 'makes the view types the frame host builds available' {
            InModuleScope pwsh-ai-herd { Import-TerminalGui }

            'Terminal.Gui.FrameView' -as [type] | Should -Not -BeNullOrEmpty
            'Terminal.Gui.ListView'  -as [type] | Should -Not -BeNullOrEmpty
            'Terminal.Gui.TextField' -as [type] | Should -Not -BeNullOrEmpty
        }

        It 'can be called twice, because Add-Type cannot load an assembly twice' {
            {
                InModuleScope pwsh-ai-herd { Import-TerminalGui; Import-TerminalGui }
            } | Should -Not -Throw
        }
    }

    Context 'once the assemblies are loaded' -Skip:(-not $script:HasConsoleGuiTools) {

        It 'returns immediately without looking for the module again' {
            InModuleScope pwsh-ai-herd { Import-TerminalGui }
            Mock -ModuleName pwsh-ai-herd Test-ConsoleGuiTools { $false }

            { InModuleScope pwsh-ai-herd { Import-TerminalGui } } | Should -Not -Throw

            Should -Not -Invoke -ModuleName pwsh-ai-herd Test-ConsoleGuiTools
        }
    }

    Context 'the error when ConsoleGuiTools is missing' {

        It 'is a terminating error that names the module' {
            # The guard is only reachable in a session where Terminal.Gui has not been loaded,
            # so the message itself is checked against the source rather than by calling it.
            $source = Get-Content -Path (Join-Path $PSScriptRoot '../src/private/Import-TerminalGui.ps1') -Raw

            $source | Should -Match 'throw'
            $source | Should -Match 'Microsoft\.PowerShell\.ConsoleGuiTools'
            $source | Should -Match 'Install-Module'
        }

        It 'checks availability before trying to load anything' {
            $source = Get-Content -Path (Join-Path $PSScriptRoot '../src/private/Import-TerminalGui.ps1') -Raw

            $guardIndex = $source.IndexOf('Test-ConsoleGuiTools')
            $loadIndex  = $source.IndexOf('Add-Type')

            $guardIndex | Should -BeLessThan $loadIndex
        }

        It 'loads NStack before Terminal.Gui, which depends on it' {
            $source = Get-Content -Path (Join-Path $PSScriptRoot '../src/private/Import-TerminalGui.ps1') -Raw

            $source.IndexOf('NStack.dll') | Should -BeLessThan $source.IndexOf('Terminal.Gui.dll')
        }
    }
}
