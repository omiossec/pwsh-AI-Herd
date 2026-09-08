BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
}

Describe 'Get-GridGeometry' {

    Context 'auto layout from a count' {

        It 'lays <Count> agents out as <Columns> x <Rows>' -TestCases @(
            @{ Count = 1; Columns = 1; Rows = 1 }
            @{ Count = 2; Columns = 2; Rows = 1 }
            @{ Count = 3; Columns = 2; Rows = 2 }
            @{ Count = 4; Columns = 2; Rows = 2 }
            @{ Count = 5; Columns = 3; Rows = 2 }
            @{ Count = 6; Columns = 3; Rows = 2 }
            @{ Count = 7; Columns = 3; Rows = 3 }
            @{ Count = 9; Columns = 3; Rows = 3 }
            @{ Count = 10; Columns = 4; Rows = 3 }
        ) {
            $result = InModuleScope pwsh-ai-herd -Parameters @{ n = $Count } {
                param($n)
                Get-GridGeometry -Count $n
            }

            $result.Count   | Should -Be $Count
            $result.Columns | Should -Be $Columns
            $result.Rows    | Should -Be $Rows
        }

        It 'never produces a portrait grid, so a wide terminal is used first' {
            1..16 | ForEach-Object {
                $result = InModuleScope pwsh-ai-herd -Parameters @{ n = $_ } {
                    param($n)
                    Get-GridGeometry -Count $n
                }
                $result.Columns | Should -BeGreaterOrEqual $result.Rows -Because "$_ agents should not be taller than wide"
            }
        }

        It 'always leaves room for every agent' {
            1..16 | ForEach-Object {
                $result = InModuleScope pwsh-ai-herd -Parameters @{ n = $_ } {
                    param($n)
                    Get-GridGeometry -Count $n
                }
                ($result.Columns * $result.Rows) | Should -BeGreaterOrEqual $_
            }
        }

        It 'wastes at most one row of cells' {
            1..16 | ForEach-Object {
                $result = InModuleScope pwsh-ai-herd -Parameters @{ n = $_ } {
                    param($n)
                    Get-GridGeometry -Count $n
                }
                (($result.Columns * $result.Rows) - $_) | Should -BeLessThan $result.Columns
            }
        }
    }

    Context 'explicit matrix' {

        It 'uses the requested columns and rows unchanged' {
            $result = InModuleScope pwsh-ai-herd { Get-GridGeometry -Columns 3 -Rows 1 }

            $result.Columns | Should -Be 3
            $result.Rows    | Should -Be 1
        }

        It 'derives the agent count from the matrix' {
            $result = InModuleScope pwsh-ai-herd { Get-GridGeometry -Columns 4 -Rows 2 }

            $result.Count | Should -Be 8
        }

        It 'allows a portrait matrix when it was asked for explicitly' {
            $result = InModuleScope pwsh-ai-herd { Get-GridGeometry -Columns 1 -Rows 4 }

            $result.Columns | Should -Be 1
            $result.Rows    | Should -Be 4
            $result.Count   | Should -Be 4
        }

        It 'requires both Columns and Rows' {
            { InModuleScope pwsh-ai-herd { Get-GridGeometry -Columns 3 } } | Should -Throw
        }
    }

    Context 'input validation' {

        It 'rejects a count of <Value>' -TestCases @(
            @{ Value = 0 }
            @{ Value = -1 }
            @{ Value = 65 }
        ) {
            { InModuleScope pwsh-ai-herd -Parameters @{ n = $Value } {
                param($n)
                Get-GridGeometry -Count $n
            } } | Should -Throw
        }

        It 'rejects a matrix dimension above 16' {
            { InModuleScope pwsh-ai-herd { Get-GridGeometry -Columns 17 -Rows 1 } } | Should -Throw
        }
    }
}
