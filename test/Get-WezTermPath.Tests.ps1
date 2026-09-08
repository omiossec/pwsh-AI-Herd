BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
}

Describe 'Get-WezTermPath' {

    Context 'when wezterm is on PATH' {

        BeforeAll {
            Mock -ModuleName pwsh-ai-herd Get-Command {
                [PSCustomObject]@{ Source = '/usr/local/bin/wezterm' }
            } -ParameterFilter { $Name -eq 'wezterm' }
        }

        It 'returns the resolved executable' {
            InModuleScope pwsh-ai-herd { Get-WezTermPath } | Should -Be '/usr/local/bin/wezterm'
        }

        It 'does not go looking on disk' {
            Mock -ModuleName pwsh-ai-herd Test-Path { $true }

            InModuleScope pwsh-ai-herd { Get-WezTermPath } | Out-Null

            Should -Not -Invoke -ModuleName pwsh-ai-herd Test-Path
        }
    }

    Context 'when wezterm is installed but not on PATH' {

        BeforeAll {
            Mock -ModuleName pwsh-ai-herd Get-Command { $null } -ParameterFilter { $Name -eq 'wezterm' }
        }

        It 'finds the default install location' {
            Mock -ModuleName pwsh-ai-herd Test-Path { $true }

            InModuleScope pwsh-ai-herd { Get-WezTermPath } | Should -Match 'wezterm'
        }

        It 'returns the first candidate that exists' {
            # Only the second candidate is present, so the first must be skipped.
            $script:seen = @()
            Mock -ModuleName pwsh-ai-herd Test-Path {
                $global:HerdSeenPath += @($Path)
                return ($global:HerdSeenPath.Count -ge 2)
            }
            $global:HerdSeenPath = @()

            $result = InModuleScope pwsh-ai-herd { Get-WezTermPath }

            $result | Should -Be $global:HerdSeenPath[1]
            Remove-Variable -Name 'HerdSeenPath' -Scope Global -ErrorAction SilentlyContinue
        }
    }

    Context 'when wezterm is missing' {

        BeforeAll {
            Mock -ModuleName pwsh-ai-herd Get-Command { $null } -ParameterFilter { $Name -eq 'wezterm' }
            Mock -ModuleName pwsh-ai-herd Test-Path { $false }
        }

        It 'throws rather than returning a path that does not work' {
            { InModuleScope pwsh-ai-herd { Get-WezTermPath } } | Should -Throw
        }

        It 'names the tool in the error' {
            { InModuleScope pwsh-ai-herd { Get-WezTermPath } } |
                Should -Throw -ExpectedMessage '*wezterm*'
        }

        It 'tells the user how to install it' {
            { InModuleScope pwsh-ai-herd { Get-WezTermPath } } |
                Should -Throw -ExpectedMessage '*wezterm.org*'
        }
    }
}
