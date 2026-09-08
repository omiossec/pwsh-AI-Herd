BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    function New-Worktree {
        param([string]$Repository = 'C:\repo', [string]$Path = 'C:\wt\1', [string]$Branch = 'herd/demo-1')
        InModuleScope pwsh-ai-herd -Parameters @{ r = $Repository; p = $Path; b = $Branch } {
            param($r, $p, $b)
            New-HerdWorktree -Repository $r -Path $p -Branch $b
        }
    }

    # git is a native command, so the mock has to set $LASTEXITCODE the way git would. The
    # canned exit codes travel through globals, not a closure, so parameter binding still works.
    function Set-GitMock {
        param([int]$RevParse = 0, [int]$ShowRef = 1, [int]$WorktreeAdd = 0)

        $global:HerdGitCalls   = @()
        $global:HerdGitExit    = @{ RevParse = $RevParse; ShowRef = $ShowRef; WorktreeAdd = $WorktreeAdd }

        Mock -ModuleName pwsh-ai-herd git {
            $global:HerdGitCalls += , @($args)
            $joined = $args -join ' '
            if ($joined -like '*rev-parse*')    { $global:LASTEXITCODE = $global:HerdGitExit.RevParse;    return }
            if ($joined -like '*show-ref*')     { $global:LASTEXITCODE = $global:HerdGitExit.ShowRef;     return }
            if ($joined -like '*worktree add*') { $global:LASTEXITCODE = $global:HerdGitExit.WorktreeAdd; return 'add output' }
            $global:LASTEXITCODE = 0
        }
    }
}

AfterAll {
    Remove-Variable -Name 'HerdGitCalls', 'HerdGitExit' -Scope Global -ErrorAction SilentlyContinue
}

Describe 'New-HerdWorktree' {

    Context 'outside a git repository' {

        It 'refuses rather than creating a stray directory' {
            Set-GitMock -RevParse 128
            Mock -ModuleName pwsh-ai-herd Test-Path { $false }

            { New-Worktree } | Should -Throw -ExpectedMessage '*not a git repository*'
        }
    }

    Context 'when the worktree already exists' {

        BeforeEach {
            Set-GitMock
            Mock -ModuleName pwsh-ai-herd Test-Path { $true } -ParameterFilter { $PathType -eq 'Container' }
        }

        It 'returns the existing worktree' {
            (New-Worktree -Path 'C:\wt\1').Path | Should -Be 'C:\wt\1'
        }

        It 'reports the branch it belongs to' {
            (New-Worktree -Branch 'herd/demo-3').Branch | Should -Be 'herd/demo-3'
        }

        It 'does not run git worktree add again' {
            New-Worktree | Out-Null

            @($global:HerdGitCalls | Where-Object { ($_ -join ' ') -like '*worktree add*' }).Count |
                Should -Be 0
        }
    }

    Context 'creating a worktree on a new branch' {

        BeforeEach {
            Set-GitMock -ShowRef 1
            Mock -ModuleName pwsh-ai-herd Test-Path { $false }
            Mock -ModuleName pwsh-ai-herd New-Item { }
        }

        It 'creates the branch as part of adding the worktree' {
            New-Worktree -Path 'C:\wt\2' -Branch 'herd/demo-2' | Out-Null

            $addCall = @($global:HerdGitCalls | Where-Object { ($_ -join ' ') -like '*worktree add*' })[0] -join ' '
            $addCall | Should -BeLike '*-b herd/demo-2*'
        }

        It 'creates the parent directory first' {
            New-Worktree | Out-Null

            Should -Invoke -ModuleName pwsh-ai-herd New-Item
        }

        It 'returns the path and branch it created' {
            $result = New-Worktree -Path 'C:\wt\2' -Branch 'herd/demo-2'

            $result.Path   | Should -Be 'C:\wt\2'
            $result.Branch | Should -Be 'herd/demo-2'
        }
    }

    Context 'reusing a branch that already exists' {

        BeforeEach {
            Set-GitMock -ShowRef 0
            Mock -ModuleName pwsh-ai-herd Test-Path { $false }
            Mock -ModuleName pwsh-ai-herd New-Item { }
        }

        It 'checks the branch out instead of trying to create it again' {
            New-Worktree -Branch 'herd/demo-1' | Out-Null

            $addCall = @($global:HerdGitCalls | Where-Object { ($_ -join ' ') -like '*worktree add*' })[0] -join ' '
            $addCall | Should -Not -BeLike '*-b *'
        }
    }

    Context 'when git fails' {

        It 'reports the branch and what git said' {
            Set-GitMock -WorktreeAdd 128
            Mock -ModuleName pwsh-ai-herd Test-Path { $false }
            Mock -ModuleName pwsh-ai-herd New-Item { }

            { New-Worktree -Branch 'herd/demo-9' } | Should -Throw -ExpectedMessage '*herd/demo-9*'
        }
    }

    Context 'input validation' {

        It 'requires a repository, a path and a branch' {
            { InModuleScope pwsh-ai-herd { New-HerdWorktree -Repository 'C:\r' -Path 'C:\p' } } |
                Should -Throw
        }
    }
}
