BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.ps1')

    function Set-GitMock {
        param([int]$ExitCode = 0)

        $global:HerdGitCalls    = [System.Collections.Generic.List[object]]::new()
        $global:HerdGitExitCode = $ExitCode

        Mock -ModuleName pwsh-ai-herd git {
            $global:HerdGitCalls.Add(@($args))
            $global:LASTEXITCODE = $global:HerdGitExitCode
            return 'git output'
        }
    }

    function Get-GitCall {
        param([string]$Contains)
        , @($global:HerdGitCalls | Where-Object { ($_ -join ' ') -like "*$Contains*" })
    }
}

AfterAll {
    Remove-Variable -Name 'HerdGitCalls', 'HerdGitExitCode' -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Remove-AiGridWorktree' {

    BeforeEach {
        $script:projectDir = Join-Path -Path $TestDrive -ChildPath "project-$(New-Guid)"
        [void](New-Item -Path $script:projectDir -ItemType Directory -Force)

        $script:worktreeRoot = Join-Path -Path $TestDrive -ChildPath "wt-$(New-Guid)"
        $script:grid = New-TestGridRecord -Directory $script:projectDir -PaneCount 2 `
            -Worktree $script:worktreeRoot -Branch 'herd/demo'

        foreach ($pane in $script:grid.Panes) {
            [void](New-Item -Path $pane.Worktree -ItemType Directory -Force)
        }

        Mock -ModuleName pwsh-ai-herd Resolve-HerdGrid { $grid }
        Mock -ModuleName pwsh-ai-herd Save-HerdGrid { 'C:\state\grid.json' }
        Set-GitMock
    }

    Context 'removing the worktrees' {

        BeforeEach {
            Remove-AiGridWorktree -Confirm:$false
        }

        It 'removes one worktree per agent' {
            (Get-GitCall -Contains 'worktree remove').Count | Should -Be 2
        }

        It 'runs git in the project repository' {
            (Get-GitCall -Contains 'worktree remove')[0] | Should -Contain $script:projectDir
        }

        It 'clears the worktree from the grid record' {
            $script:grid.Panes.Worktree | Should -Be @($null, $null)
        }

        It 'saves the updated record so a reopen runs in the project directory' {
            Should -Invoke -ModuleName pwsh-ai-herd Save-HerdGrid
        }

        It 'does not force by default, so uncommitted work is protected' {
            (Get-GitCall -Contains 'worktree remove')[0] | Should -Not -Contain '--force'
        }

        It 'keeps the branches, because merging back is a deliberate step' {
            (Get-GitCall -Contains 'branch -D').Count | Should -Be 0
        }

        It 'keeps the branch name in the record' {
            $script:grid.Panes[0].Branch | Should -Not -BeNullOrEmpty
        }
    }

    Context 'forcing' {

        It 'passes the force flag to git' {
            Remove-AiGridWorktree -Force -Confirm:$false

            (Get-GitCall -Contains 'worktree remove')[0] | Should -Contain '--force'
        }
    }

    Context 'deleting the branches too' {

        BeforeEach {
            Remove-AiGridWorktree -DeleteBranch -Confirm:$false
        }

        It 'deletes one branch per agent' {
            (Get-GitCall -Contains 'branch -D').Count | Should -Be 2
        }

        It 'names the recorded branch' {
            (Get-GitCall -Contains 'branch -D')[0] | Should -Contain 'herd/demo-1'
        }

        It 'clears the branch from the record' {
            $script:grid.Panes.Branch | Should -Be @($null, $null)
        }
    }

    Context 'a worktree that is already gone from disk' {

        It 'prunes the stale registration instead of removing' {
            foreach ($pane in $script:grid.Panes) {
                Remove-Item -Path $pane.Worktree -Recurse -Force
            }

            Remove-AiGridWorktree -Confirm:$false

            (Get-GitCall -Contains 'worktree prune').Count  | Should -BeGreaterThan 0
            (Get-GitCall -Contains 'worktree remove').Count | Should -Be 0
        }
    }

    Context 'when git refuses' {

        BeforeEach {
            Set-GitMock -ExitCode 128
        }

        It 'warns instead of throwing' {
            { Remove-AiGridWorktree -Confirm:$false 3>$null } | Should -Not -Throw
        }

        It 'keeps the worktree in the record so it is not lost' {
            Remove-AiGridWorktree -Confirm:$false 3>$null

            $script:grid.Panes[0].Worktree | Should -Not -BeNullOrEmpty
        }

        It 'does not save a record it could not act on' {
            Remove-AiGridWorktree -Confirm:$false 3>$null

            Should -Not -Invoke -ModuleName pwsh-ai-herd Save-HerdGrid
        }
    }

    Context 'a grid with no worktrees' {

        BeforeEach {
            $script:grid = New-TestGridRecord -Directory $script:projectDir -PaneCount 2
            Mock -ModuleName pwsh-ai-herd Resolve-HerdGrid { $grid }
            Set-GitMock
        }

        It 'does nothing' {
            Remove-AiGridWorktree -Confirm:$false

            $global:HerdGitCalls.Count | Should -Be 0
        }

        It 'does not rewrite the record' {
            Remove-AiGridWorktree -Confirm:$false

            Should -Not -Invoke -ModuleName pwsh-ai-herd Save-HerdGrid
        }
    }

    Context 'WhatIf' {

        It 'removes nothing' {
            Remove-AiGridWorktree -WhatIf

            (Get-GitCall -Contains 'worktree remove').Count | Should -Be 0
        }

        It 'leaves the worktrees on disk' {
            Remove-AiGridWorktree -WhatIf

            Test-Path -Path $script:grid.Panes[0].Worktree | Should -BeTrue
        }
    }
}
