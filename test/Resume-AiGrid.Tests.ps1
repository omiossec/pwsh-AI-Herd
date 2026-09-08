BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.ps1')

    function Set-BuilderMock {
        $global:HerdBuildArgs = $null
        Mock -ModuleName pwsh-ai-herd New-HerdGrid {
            $global:HerdBuildArgs = @{
                Directory = $Directory
                Columns   = $Columns
                Rows      = $Rows
                Pane      = @($Pane)
                Resume    = [bool]$Resume
            }
            return [PSCustomObject]@{ Directory = $Directory; Panes = @($Pane) }
        }
    }
}

AfterAll {
    Remove-Variable -Name 'HerdBuildArgs' -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Resume-AiGrid' {

    BeforeEach {
        Set-BuilderMock

        $script:projectDir = Join-Path -Path $TestDrive -ChildPath "project-$(New-Guid)"
        [void](New-Item -Path $script:projectDir -ItemType Directory -Force)

        $script:grid = New-TestGridRecord -Directory $script:projectDir -PaneCount 3 -Columns 3 -Rows 1
        $script:grid | Add-Member -NotePropertyName 'Path' -NotePropertyValue 'C:\state\grid.json' -Force

        Mock -ModuleName pwsh-ai-herd Resolve-HerdGrid { $grid }
    }

    Context 'reopening the grid of the current project' {

        BeforeEach {
            Resume-AiGrid -WorkingDirectory $script:projectDir -Confirm:$false | Out-Null
        }

        It 'resumes rather than starting fresh conversations' {
            $global:HerdBuildArgs.Resume | Should -BeTrue
        }

        It 'reopens the same number of panes' {
            $global:HerdBuildArgs.Pane.Count | Should -Be 3
        }

        It 'restores the saved layout' {
            $global:HerdBuildArgs.Columns | Should -Be 3
            $global:HerdBuildArgs.Rows    | Should -Be 1
        }

        It 'reuses the recorded project directory' {
            $global:HerdBuildArgs.Directory | Should -Be $script:projectDir
        }

        It 'keeps every session id, so each pane resumes its own conversation' {
            $global:HerdBuildArgs.Pane.SessionId | Should -Be $script:grid.Panes.SessionId
        }

        It 'clears the pane ids left over from the previous wezterm' {
            # They identify panes inside one running wezterm and mean nothing in a new one.
            $global:HerdBuildArgs.Pane.PaneId | Should -Be @($null, $null, $null)
        }
    }

    Context 'choosing which grid' {

        It 'reopens the grid file it was given' {
            Resume-AiGrid -Path 'C:\state\grid.json' -Confirm:$false | Out-Null

            Should -Invoke -ModuleName pwsh-ai-herd Resolve-HerdGrid -ParameterFilter {
                $Path -eq 'C:\state\grid.json'
            }
        }

        It 'accepts a grid from the pipeline by its path' {
            $script:grid | Resume-AiGrid -Confirm:$false | Out-Null

            $global:HerdBuildArgs.Directory | Should -Be $script:projectDir
        }

        It 'defaults to the current location' {
            Push-Location -Path $script:projectDir
            try { Resume-AiGrid -Confirm:$false | Out-Null }
            finally { Pop-Location }

            Should -Invoke -ModuleName pwsh-ai-herd Resolve-HerdGrid
        }
    }

    Context 'when the project is gone' {

        It 'refuses rather than reopening agents in the wrong place' {
            $missing = Join-Path -Path $TestDrive -ChildPath 'deleted-project'
            Mock -ModuleName pwsh-ai-herd Resolve-HerdGrid {
                New-TestGridRecord -Directory $missing -PaneCount 1
            }

            { Resume-AiGrid -Confirm:$false } | Should -Throw -ExpectedMessage '*gone*'
        }
    }

    Context 'WhatIf' {

        It 'opens nothing' {
            Resume-AiGrid -WorkingDirectory $script:projectDir -WhatIf | Out-Null

            Should -Not -Invoke -ModuleName pwsh-ai-herd New-HerdGrid
        }
    }
}
