BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    function Get-Effort {
        param([int]$Count)
        InModuleScope pwsh-ai-herd -Parameters @{ n = $Count } {
            param($n)
            Get-AgentEffort -Count $n
        }
    }
}

Describe 'Get-AgentEffort' {

    Context 'shape of the result' {

        It 'returns one level per pane' {
            1..16 | ForEach-Object {
                @(Get-Effort -Count $_).Count | Should -Be $_
            }
        }

        It 'only ever returns known levels' {
            1..16 | ForEach-Object {
                Get-Effort -Count $_ | Should -BeIn @('default', 'medium', 'low')
            }
        }

        It 'returns strings even for a single pane, not a bare scalar' {
            $result = Get-Effort -Count 1
            @($result).Count | Should -Be 1
            $result          | Should -BeOfType [string]
        }

        # A one-element result unrolls to a bare string on the way out of the function, so a
        # caller that indexes it without wrapping gets a character instead of a level. That is
        # what breaks Start-AiGrid for a single agent; see Start-AiGrid.Tests.ps1.
        It 'unrolls to a bare string for one pane, so callers must wrap the call in @()' {
            $result = InModuleScope pwsh-ai-herd { Get-AgentEffort -Count 1 }

            $result -is [array] | Should -BeFalse
            $result[0]          | Should -Be 'd'
        }
    }

    Context 'the documented distribution' {

        It 'gives a lone agent the default level' {
            Get-Effort -Count 1 | Should -Be 'default'
        }

        It 'spreads <Count> agents as <Expected>' -TestCases @(
            @{ Count = 2; Expected = @('default', 'low') }
            @{ Count = 3; Expected = @('default', 'medium', 'low') }
            @{ Count = 4; Expected = @('default', 'default', 'medium', 'low') }
            @{ Count = 6; Expected = @('default', 'default', 'default', 'medium', 'medium', 'low') }
        ) {
            Get-Effort -Count $Count | Should -Be $Expected
        }

        It 'always puts the cheapest agent last' {
            2..16 | ForEach-Object {
                $result = @(Get-Effort -Count $_)
                $result[-1] | Should -Be 'low' -Because "the last of $_ panes carries the low effort marker"
            }
        }

        It 'always keeps at least one agent at the default level' {
            1..16 | ForEach-Object {
                @(Get-Effort -Count $_ | Where-Object { $_ -eq 'default' }).Count |
                    Should -BeGreaterThan 0
            }
        }

        It 'runs exactly one agent low' {
            2..16 | ForEach-Object {
                @(Get-Effort -Count $_ | Where-Object { $_ -eq 'low' }).Count | Should -Be 1
            }
        }

        It 'keeps medium to roughly a quarter of the grid' {
            4..16 | ForEach-Object {
                $medium = @(Get-Effort -Count $_ | Where-Object { $_ -eq 'medium' }).Count
                $medium | Should -BeLessOrEqual ([Math]::Ceiling($_ / 3))
            }
        }

        It 'orders the levels from most to least effort' {
            $rank = @{ default = 0; medium = 1; low = 2 }
            2..16 | ForEach-Object {
                $ranks = @(Get-Effort -Count $_ | ForEach-Object { $rank[$_] })
                for ($i = 1; $i -lt $ranks.Count; $i++) {
                    $ranks[$i] | Should -BeGreaterOrEqual $ranks[$i - 1]
                }
            }
        }
    }

    Context 'input validation' {

        It 'rejects a count of <Value>' -TestCases @(
            @{ Value = 0 }
            @{ Value = 65 }
        ) {
            { Get-Effort -Count $Value } | Should -Throw
        }
    }
}
