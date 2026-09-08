BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.ps1')

    function Set-PaneMock {
        param([int[]]$LivePaneId = @(0, 1))

        $global:HerdCliCalls  = [System.Collections.Generic.List[object]]::new()
        $global:HerdLivePanes = @($LivePaneId | ForEach-Object { [PSCustomObject]@{ pane_id = $_ } })

        Mock -ModuleName pwsh-ai-herd Get-WezTermPane { $global:HerdLivePanes }
        Mock -ModuleName pwsh-ai-herd Invoke-WezTermCli {
            $global:HerdCliCalls.Add(@($Arguments))
            return '77'
        }
    }

    function Get-SplitCall {
        , @($global:HerdCliCalls | Where-Object { $_[0] -eq 'split-pane' })
    }
}

AfterAll {
    Remove-Variable -Name 'HerdCliCalls', 'HerdLivePanes' -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Add-AiGridAgent' {

    BeforeEach {
        $script:projectDir = Join-Path -Path $TestDrive -ChildPath "project-$(New-Guid)"
        [void](New-Item -Path $script:projectDir -ItemType Directory -Force)

        $script:grid = New-TestGridRecord -Directory $script:projectDir -PaneCount 2 -Columns 2 -Rows 1
        Mock -ModuleName pwsh-ai-herd Resolve-HerdGrid { $grid }
        Mock -ModuleName pwsh-ai-herd Save-HerdGrid { 'C:\state\grid.json' }
        Set-PaneMock -LivePaneId @(0, 1)
    }

    Context 'adding a pane' {

        BeforeEach {
            $script:result = Add-AiGridAgent -Confirm:$false
        }

        It 'splits once' {
            (Get-SplitCall).Count | Should -Be 1
        }

        It 'splits off the last pane of the grid' {
            (Get-SplitCall)[0] | Should -Contain 1
        }

        It 'splits downwards' {
            (Get-SplitCall)[0] | Should -Contain '--bottom'
        }

        It 'starts the agent in the project directory' {
            (Get-SplitCall)[0] | Should -Contain $script:projectDir
        }

        It 'records the pane id the CLI returned' {
            $script:result.PaneId | Should -Be 77
        }

        It 'gives the new agent its own pinned session id' {
            { [guid]::Parse($script:result.SessionId) } | Should -Not -Throw
        }

        It 'numbers it after the panes already in the grid' {
            $script:result.Index | Should -Be 2
        }

        It 'defaults to Claude' {
            $script:result.Agent | Should -Be 'Claude'
        }

        It 'appends it to the grid record' {
            @($script:grid.Panes).Count | Should -Be 3
        }

        It 'saves the grid so a reopen brings the new agent back too' {
            Should -Invoke -ModuleName pwsh-ai-herd Save-HerdGrid
        }
    }

    Context 'the layout record' {

        It 'grows the row count when the grid is full' {
            # Two columns by one row holds two agents; a third needs a second row.
            Add-AiGridAgent -Confirm:$false | Out-Null

            $script:grid.Rows | Should -Be 2
        }

        It 'leaves the layout alone while there is still room' {
            $script:grid = New-TestGridRecord -Directory $script:projectDir -PaneCount 2 -Columns 2 -Rows 2
            Mock -ModuleName pwsh-ai-herd Resolve-HerdGrid { $grid }

            Add-AiGridAgent -Confirm:$false | Out-Null

            $script:grid.Rows | Should -Be 2
        }
    }

    Context 'choosing the agent' {

        It 'runs the agent asked for' {
            (Add-AiGridAgent -Agent Codex -Confirm:$false).Agent | Should -Be 'Codex'
        }

        It 'records the task label' {
            (Add-AiGridAgent -Task 'reviewer' -Confirm:$false).Task | Should -Be 'reviewer'
        }

        It 'records the kickoff prompt' {
            (Add-AiGridAgent -Kickoff 'review the diff' -Confirm:$false).Kickoff | Should -Be 'review the diff'
        }

        It 'rejects an unknown agent' {
            { Add-AiGridAgent -Agent Gemini -Confirm:$false } | Should -Throw
        }
    }

    Context 'worktree isolation' {

        It 'creates a worktree for the new agent' {
            Mock -ModuleName pwsh-ai-herd New-HerdWorktree {
                [PSCustomObject]@{ Path = $Path; Branch = $Branch }
            }

            $result = Add-AiGridAgent -Worktree -Confirm:$false

            $result.Worktree | Should -Not -BeNullOrEmpty
            $result.Branch   | Should -BeLike 'herd/*'
        }

        It 'starts the agent in that worktree' {
            Mock -ModuleName pwsh-ai-herd New-HerdWorktree {
                [PSCustomObject]@{ Path = $Path; Branch = $Branch }
            }

            $result = Add-AiGridAgent -Worktree -Confirm:$false

            (Get-SplitCall)[0] | Should -Contain $result.Worktree
        }
    }

    Context 'when the grid window has been closed' {

        BeforeEach {
            Set-PaneMock -LivePaneId @()
        }

        It 'refuses rather than splitting an unrelated window' {
            { Add-AiGridAgent -Confirm:$false } | Should -Throw
        }

        It 'suggests reopening the grid' {
            { Add-AiGridAgent -Confirm:$false } | Should -Throw -ExpectedMessage '*Resume-AiGrid*'
        }

        It 'leaves the grid record untouched' {
            try { Add-AiGridAgent -Confirm:$false } catch { }

            @($script:grid.Panes).Count | Should -Be 2
        }
    }

    Context 'when only some panes survive' {

        It 'splits off the last pane that is still open' {
            Set-PaneMock -LivePaneId @(0)

            Add-AiGridAgent -Confirm:$false | Out-Null

            (Get-SplitCall)[0] | Should -Contain 0
        }
    }

    Context 'WhatIf' {

        It 'splits nothing' {
            Add-AiGridAgent -WhatIf | Out-Null

            (Get-SplitCall).Count | Should -Be 0
        }

        It 'does not change the grid record' {
            Add-AiGridAgent -WhatIf | Out-Null

            @($script:grid.Panes).Count | Should -Be 2
        }
    }
}
