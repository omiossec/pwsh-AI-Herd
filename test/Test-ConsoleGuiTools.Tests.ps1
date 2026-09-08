BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
}

Describe 'Test-ConsoleGuiTools' {

    Context 'when the module is not installed' {

        BeforeAll {
            Mock -ModuleName pwsh-ai-herd Get-Module { @() } -ParameterFilter { $ListAvailable }
        }

        It 'reports false' {
            InModuleScope pwsh-ai-herd { Test-ConsoleGuiTools } | Should -BeFalse
        }

        It 'reports false for any minimum version too' {
            InModuleScope pwsh-ai-herd { Test-ConsoleGuiTools -MinimumVersion '0.1.0' } | Should -BeFalse
        }
    }

    Context 'when the module is installed' {

        BeforeAll {
            Mock -ModuleName pwsh-ai-herd Get-Module {
                @([PSCustomObject]@{ Name = 'Microsoft.PowerShell.ConsoleGuiTools'; Version = [version]'0.7.7' })
            } -ParameterFilter { $ListAvailable }
        }

        It 'reports true' {
            InModuleScope pwsh-ai-herd { Test-ConsoleGuiTools } | Should -BeTrue
        }

        It 'reports true for an older minimum version' {
            InModuleScope pwsh-ai-herd { Test-ConsoleGuiTools -MinimumVersion '0.7.0' } | Should -BeTrue
        }

        It 'reports true for exactly the installed version' {
            InModuleScope pwsh-ai-herd { Test-ConsoleGuiTools -MinimumVersion '0.7.7' } | Should -BeTrue
        }

        It 'reports false for a newer minimum version' {
            InModuleScope pwsh-ai-herd { Test-ConsoleGuiTools -MinimumVersion '1.0.0' } | Should -BeFalse
        }

        It 'never imports the module, it only checks availability' {
            InModuleScope pwsh-ai-herd { Test-ConsoleGuiTools } | Out-Null

            Should -Invoke -ModuleName pwsh-ai-herd Get-Module -ParameterFilter { $ListAvailable }
        }
    }

    Context 'several versions side by side' {

        BeforeAll {
            Mock -ModuleName pwsh-ai-herd Get-Module {
                @(
                    [PSCustomObject]@{ Version = [version]'0.6.0' }
                    [PSCustomObject]@{ Version = [version]'0.7.7' }
                )
            } -ParameterFilter { $ListAvailable }
        }

        It 'is satisfied when any installed version meets the minimum' {
            InModuleScope pwsh-ai-herd { Test-ConsoleGuiTools -MinimumVersion '0.7.0' } | Should -BeTrue
        }

        It 'returns a plain boolean, not the matching module objects' {
            InModuleScope pwsh-ai-herd { Test-ConsoleGuiTools -MinimumVersion '0.6.0' } |
                Should -BeOfType [bool]
        }
    }

    Context 'the real machine' {

        It 'returns a boolean either way' {
            InModuleScope pwsh-ai-herd { Test-ConsoleGuiTools } | Should -BeOfType [bool]
        }
    }
}
