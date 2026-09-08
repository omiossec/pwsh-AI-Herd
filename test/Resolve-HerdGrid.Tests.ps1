BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.ps1')
}

Describe 'Resolve-HerdGrid' {

    BeforeEach {
        $script:savedPane = $env:WEZTERM_PANE
        Remove-Item -Path Env:WEZTERM_PANE -ErrorAction SilentlyContinue

        $script:projectDir = Join-Path -Path $TestDrive -ChildPath "project-$(New-Guid)"
        [void](New-Item -Path $script:projectDir -ItemType Directory -Force)

        $script:grid = New-TestGridRecord -Directory $script:projectDir -PaneCount 2
    }

    AfterEach {
        if ($script:savedPane) { $env:WEZTERM_PANE = $script:savedPane }
        else { Remove-Item -Path Env:WEZTERM_PANE -ErrorAction SilentlyContinue }
    }

    Context 'an explicit grid file' {

        It 'returns the record at that path' {
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { $grid } -ParameterFilter { $Path }

            (InModuleScope pwsh-ai-herd { Resolve-HerdGrid -Path 'C:\some\grid.json' }).Directory |
                Should -Be $script:projectDir
        }

        It 'wins over the pane the caller is sitting in' {
            $env:WEZTERM_PANE = '1'
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { $grid } -ParameterFilter { $Path }

            InModuleScope pwsh-ai-herd { Resolve-HerdGrid -Path 'C:\some\grid.json' } | Out-Null

            Should -Not -Invoke -ModuleName pwsh-ai-herd Read-HerdGrid -ParameterFilter { -not $Path }
        }

        It 'throws when the file does not exist' {
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { $null }

            { InModuleScope pwsh-ai-herd { Resolve-HerdGrid -Path 'C:\missing.json' } } |
                Should -Throw -ExpectedMessage '*No grid file*'
        }
    }

    Context 'from inside a pane of the grid' {

        It 'finds the grid that owns the current pane' {
            $env:WEZTERM_PANE = '1'
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { $grid }

            (InModuleScope pwsh-ai-herd { Resolve-HerdGrid }).Directory | Should -Be $script:projectDir
        }

        It 'falls back to the current directory when the pane belongs to no known grid' {
            $env:WEZTERM_PANE = '99'
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { $grid } -ParameterFilter { $Directory }
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { @() } -ParameterFilter { -not $Directory }

            (InModuleScope pwsh-ai-herd { Resolve-HerdGrid }).Directory | Should -Be $script:projectDir
        }

        It 'ignores the pane when a directory was named explicitly' {
            $env:WEZTERM_PANE = '1'
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { $grid } -ParameterFilter { $Directory }

            InModuleScope pwsh-ai-herd -Parameters @{ d = $script:projectDir } {
                param($d)
                Resolve-HerdGrid -Directory $d
            } | Out-Null

            Should -Invoke -ModuleName pwsh-ai-herd Read-HerdGrid -ParameterFilter { $Directory }
        }
    }

    Context 'from the project directory' {

        It 'reads the record of that directory' {
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { $grid } -ParameterFilter { $Directory }

            InModuleScope pwsh-ai-herd -Parameters @{ d = $script:projectDir } {
                param($d)
                Resolve-HerdGrid -Directory $d
            } | Out-Null

            Should -Invoke -ModuleName pwsh-ai-herd Read-HerdGrid -ParameterFilter {
                $Directory -eq $script:projectDir
            }
        }

        It 'resolves a relative directory to a full path' {
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { $grid } -ParameterFilter { $Directory }

            Push-Location -Path $TestDrive
            try {
                InModuleScope pwsh-ai-herd -Parameters @{ d = (Split-Path -Path $script:projectDir -Leaf) } {
                    param($d)
                    Resolve-HerdGrid -Directory $d
                } | Out-Null
            }
            finally { Pop-Location }

            Should -Invoke -ModuleName pwsh-ai-herd Read-HerdGrid -ParameterFilter {
                $Directory -eq $script:projectDir
            }
        }
    }

    Context 'when nothing matches' {

        It 'throws' {
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { $null }

            { InModuleScope pwsh-ai-herd -Parameters @{ d = $script:projectDir } {
                param($d)
                Resolve-HerdGrid -Directory $d
            } } | Should -Throw
        }

        It 'names the directory it looked in' {
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { $null }

            { InModuleScope pwsh-ai-herd -Parameters @{ d = $script:projectDir } {
                param($d)
                Resolve-HerdGrid -Directory $d
            } } | Should -Throw -ExpectedMessage "*$($script:projectDir)*"
        }

        It 'suggests what to do next' {
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { $null }

            { InModuleScope pwsh-ai-herd -Parameters @{ d = $script:projectDir } {
                param($d)
                Resolve-HerdGrid -Directory $d
            } } | Should -Throw -ExpectedMessage '*Start-AiGrid*'
        }
    }
}
