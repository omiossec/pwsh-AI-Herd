BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.ps1')
}

Describe 'Get-AiGrid' {

    BeforeEach {
        $script:projectDir = Join-Path -Path $TestDrive -ChildPath "project-$(New-Guid)"
        [void](New-Item -Path $script:projectDir -ItemType Directory -Force)

        $script:grids = @(
            New-TestGridRecord -Directory $script:projectDir -PaneCount 2
            New-TestGridRecord -Directory $script:projectDir -PaneCount 4
        )
    }

    Context 'listing every grid' {

        BeforeEach {
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { $grids }
        }

        It 'returns the recorded grids' {
            @(Get-AiGrid).Count | Should -Be 2
        }

        It 'asks for all of them, not one directory' {
            Get-AiGrid | Out-Null

            Should -Invoke -ModuleName pwsh-ai-herd Read-HerdGrid -ParameterFilter {
                -not $Directory -and -not $Path
            }
        }

        It 'passes the records through untouched' {
            (Get-AiGrid)[0].Panes.Count | Should -Be 2
        }
    }

    Context 'one project' {

        BeforeEach {
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { $grids[0] } -ParameterFilter { $Directory }
        }

        It 'asks for that directory only' {
            Get-AiGrid -WorkingDirectory $script:projectDir | Out-Null

            Should -Invoke -ModuleName pwsh-ai-herd Read-HerdGrid -ParameterFilter {
                $Directory -eq $script:projectDir
            }
        }

        It 'resolves a relative directory first' {
            Push-Location -Path $TestDrive
            try {
                Get-AiGrid -WorkingDirectory (Split-Path -Path $script:projectDir -Leaf) | Out-Null
            }
            finally { Pop-Location }

            Should -Invoke -ModuleName pwsh-ai-herd Read-HerdGrid -ParameterFilter {
                $Directory -eq $script:projectDir
            }
        }

        It 'returns nothing when that project has no grid' {
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { $null } -ParameterFilter { $Directory }

            Get-AiGrid -WorkingDirectory $script:projectDir | Should -BeNullOrEmpty
        }
    }

    Context 'feeding Resume-AiGrid' {

        It 'returns records carrying the Path that Resume-AiGrid binds to' {
            $withPath = $script:grids[0]
            $withPath | Add-Member -NotePropertyName 'Path' -NotePropertyValue 'C:\state\a.json' -Force
            Mock -ModuleName pwsh-ai-herd Read-HerdGrid { $withPath }

            (Get-AiGrid).Path | Should -Be 'C:\state\a.json'
        }
    }
}
