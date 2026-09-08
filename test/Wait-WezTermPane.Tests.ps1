BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    function Wait-Pane {
        param([int[]]$Known = @(), [int]$TimeoutSecond = 2)
        InModuleScope pwsh-ai-herd -Parameters @{ k = $Known; t = $TimeoutSecond } {
            param($k, $t)
            Wait-WezTermPane -KnownPaneId $k -TimeoutSecond $t
        }
    }
}

Describe 'Wait-WezTermPane' {

    Context 'when a new pane appears' {

        It 'returns the id of the pane that was not there before' {
            Mock -ModuleName pwsh-ai-herd Get-WezTermPane {
                @([PSCustomObject]@{ pane_id = 5 })
            }

            Wait-Pane -Known @() | Should -Be 5
        }

        It 'ignores panes that were already open' {
            Mock -ModuleName pwsh-ai-herd Get-WezTermPane {
                @(
                    [PSCustomObject]@{ pane_id = 1 }
                    [PSCustomObject]@{ pane_id = 2 }
                    [PSCustomObject]@{ pane_id = 9 }
                )
            }

            Wait-Pane -Known @(1, 2) | Should -Be 9
        }

        It 'picks the lowest new id, which is the first pane of the new window' {
            Mock -ModuleName pwsh-ai-herd Get-WezTermPane {
                @(
                    [PSCustomObject]@{ pane_id = 12 }
                    [PSCustomObject]@{ pane_id = 10 }
                    [PSCustomObject]@{ pane_id = 11 }
                )
            }

            Wait-Pane -Known @() | Should -Be 10
        }

        It 'returns an integer, ready for the split calls that follow' {
            Mock -ModuleName pwsh-ai-herd Get-WezTermPane { @([PSCustomObject]@{ pane_id = '5' }) }

            Wait-Pane -Known @() | Should -BeOfType [int]
        }

        It 'polls quietly, so a not-yet-running wezterm is not an error' {
            Mock -ModuleName pwsh-ai-herd Get-WezTermPane { @([PSCustomObject]@{ pane_id = 5 }) }

            Wait-Pane -Known @() | Out-Null

            Should -Invoke -ModuleName pwsh-ai-herd Get-WezTermPane -ParameterFilter { $Quiet }
        }
    }

    Context 'when the window is slow to open' {

        It 'keeps polling until the pane shows up' {
            $global:HerdPollCount = 0
            Mock -ModuleName pwsh-ai-herd Get-WezTermPane {
                $global:HerdPollCount++
                if ($global:HerdPollCount -lt 3) { return @() }
                return @([PSCustomObject]@{ pane_id = 8 })
            }

            Wait-Pane -Known @() | Should -Be 8
            $global:HerdPollCount | Should -BeGreaterOrEqual 3

            Remove-Variable -Name 'HerdPollCount' -Scope Global -ErrorAction SilentlyContinue
        }
    }

    Context 'when the window never opens' {

        BeforeAll {
            Mock -ModuleName pwsh-ai-herd Get-WezTermPane { @() }
        }

        It 'gives up rather than hanging forever' {
            { Wait-Pane -Known @() -TimeoutSecond 1 } | Should -Throw
        }

        It 'says how long it waited' {
            { Wait-Pane -Known @() -TimeoutSecond 1 } | Should -Throw -ExpectedMessage '*1 s*'
        }

        It 'gives up when every pane it sees was already known' {
            Mock -ModuleName pwsh-ai-herd Get-WezTermPane { @([PSCustomObject]@{ pane_id = 3 }) }

            { Wait-Pane -Known @(3) -TimeoutSecond 1 } | Should -Throw
        }
    }

    Context 'input validation' {

        It 'rejects a timeout of zero' {
            { Wait-Pane -Known @() -TimeoutSecond 0 } | Should -Throw
        }
    }
}
