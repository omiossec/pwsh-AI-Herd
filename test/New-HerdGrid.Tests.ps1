BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.ps1')

    function New-PaneSpec {
        param([int]$Count = 1, [string]$Agent = 'Claude', [string]$Worktree, [string]$Branch)

        for ($i = 0; $i -lt $Count; $i++) {
            [PSCustomObject]@{
                Index     = $i
                SessionId = [guid]::NewGuid().ToString()
                Agent     = $Agent
                Effort    = 'default'
                Task      = $null
                Kickoff   = $null
                Worktree  = $Worktree
                Branch    = $Branch
                PaneId    = $null
            }
        }
    }

    # Records every wezterm call and hands out increasing pane ids, the way the real CLI does.
    # State goes through globals rather than a closure: GetNewClosure on a mock body stops
    # Pester binding the mocked function's parameters, so $Arguments would arrive empty.
    function Set-WezTermMock {
        param([switch]$NoSocket)

        $global:HerdCliCalls   = [System.Collections.Generic.List[object]]::new()
        $global:HerdNextPaneId = 10
        $global:HerdNoSocket   = [bool]$NoSocket

        Mock -ModuleName pwsh-ai-herd Get-WezTermSocket {
            if ($global:HerdNoSocket) { $null } else { '/run/gui-sock-1' }
        }
        Mock -ModuleName pwsh-ai-herd Get-WezTermPane { @() }
        Mock -ModuleName pwsh-ai-herd Save-HerdGrid { 'C:\state\grid.json' }
        Mock -ModuleName pwsh-ai-herd Invoke-WezTermCli {
            $global:HerdCliCalls.Add(@($Arguments))
            switch ($Arguments[0]) {
                'spawn'      { $global:HerdNextPaneId++; return "$($global:HerdNextPaneId)" }
                'split-pane' { $global:HerdNextPaneId++; return "$($global:HerdNextPaneId)" }
                'list'       { if ($global:HerdNoSocket) { return $null } else { return '[]' } }
                default      { return '' }
            }
        }
    }

    # The leading commas keep these as collections of argument arrays; without them a single
    # match would unroll into its own arguments.
    function Get-CliCall {
        param([string]$Subcommand)
        , @($global:HerdCliCalls | Where-Object { $_[0] -eq $Subcommand })
    }

    # Every call the builder made except the opening reachability probe, so the indexes below
    # line up with the panes: 0 opens the window, 1..n are the splits in order.
    function Get-BuildCall {
        , @($global:HerdCliCalls | Where-Object { $_[0] -ne 'list' })
    }

    # The arguments of one call, flattened for readable assertions.
    function Get-CallText {
        param([int]$Index)
        ((Get-BuildCall)[$Index] | Select-Object -First 8) -join ' '
    }

    function Build-Grid {
        param([hashtable]$Splat)
        InModuleScope pwsh-ai-herd -Parameters @{ splat = $Splat } {
            param($splat)
            New-HerdGrid @splat
        }
    }
}

AfterAll {
    Remove-Variable -Name 'HerdCliCalls', 'HerdNextPaneId', 'HerdNoSocket' `
        -Scope Global -ErrorAction SilentlyContinue
}

Describe 'New-HerdGrid' {

    BeforeEach {
        $script:projectDir = Join-Path -Path $TestDrive -ChildPath "project-$(New-Guid)"
        [void](New-Item -Path $script:projectDir -ItemType Directory -Force)
    }

    Context 'a single agent' {

        BeforeEach {
            Set-WezTermMock
            $script:result = Build-Grid @{
                Directory = $script:projectDir
                Columns   = 1
                Rows      = 1
                Pane      = @(New-PaneSpec -Count 1)
            }
        }

        It 'opens one window' {
            (Get-CliCall -Subcommand 'spawn').Count | Should -Be 1
        }

        It 'never splits' {
            (Get-CliCall -Subcommand 'split-pane').Count | Should -Be 0
        }

        It 'records the pane id the CLI returned' {
            $script:result.Panes[0].PaneId | Should -Be 11
        }

        It 'starts the agent in the project directory' {
            (Get-CliCall -Subcommand 'spawn')[0] | Should -Contain $script:projectDir
        }

        It 'focuses the first pane when it is done' {
            (Get-CliCall -Subcommand 'activate-pane')[0] | Should -Contain 11
        }
    }

    Context 'the split order for a 3 x 2 grid of 5 agents' {

        BeforeEach {
            Set-WezTermMock
            $script:result = Build-Grid @{
                Directory = $script:projectDir
                Columns   = 3
                Rows      = 2
                Pane      = @(New-PaneSpec -Count 5)
            }
        }

        It 'opens the window once and splits four times' {
            (Get-CliCall -Subcommand 'spawn').Count      | Should -Be 1
            (Get-CliCall -Subcommand 'split-pane').Count | Should -Be 4
        }

        It 'builds the top row left to right before filling any column' {
            # This is the order the tmux original uses; it is what makes the last agent land
            # bottom right.
            Get-CallText -Index 1 | Should -BeLike '*--right*'
            Get-CallText -Index 2 | Should -BeLike '*--right*'
            Get-CallText -Index 3 | Should -BeLike '*--bottom*'
            Get-CallText -Index 4 | Should -BeLike '*--bottom*'
        }

        It 'splits each new column off the previous one' {
            Get-CallText -Index 1 | Should -BeLike '*--pane-id 11*'
            Get-CallText -Index 2 | Should -BeLike '*--pane-id 12*'
        }

        It 'gives the second column two thirds of the remaining width' {
            Get-CallText -Index 1 | Should -BeLike '*--percent 67*'
        }

        It 'splits the last column in half' {
            Get-CallText -Index 2 | Should -BeLike '*--percent 50*'
        }

        It 'fills the rows under the first columns, leaving the last column full height' {
            Get-CallText -Index 3 | Should -BeLike '*--pane-id 11*'
            Get-CallText -Index 4 | Should -BeLike '*--pane-id 12*'
        }

        It 'assigns pane ids in agent order' {
            @($script:result.Panes.PaneId) | Should -Be @(11, 12, 13, 14, 15)
        }
    }

    Context 'a full 2 x 2 grid' {

        BeforeEach {
            Set-WezTermMock
            $script:result = Build-Grid @{
                Directory = $script:projectDir
                Columns   = 2
                Rows      = 2
                Pane      = @(New-PaneSpec -Count 4)
            }
        }

        It 'splits three times' {
            (Get-CliCall -Subcommand 'split-pane').Count | Should -Be 3
        }

        It 'splits every column once vertically' {
            # Assigned first: piping the call collection straight into Where-Object would
            # unroll it one level too far and hand the filter the whole collection.
            $splits = Get-CliCall -Subcommand 'split-pane'

            @($splits | Where-Object { $_ -contains '--bottom' }).Count | Should -Be 2
        }
    }

    Context 'the launch command' {

        BeforeEach {
            Set-WezTermMock
            Build-Grid @{
                Directory = $script:projectDir
                Columns   = 1
                Rows      = 1
                Pane      = @(New-PaneSpec -Count 1)
            } | Out-Null
        }

        It 'separates the program from the wezterm flags with a double dash' {
            (Get-CliCall -Subcommand 'spawn')[0] | Should -Contain '--'
        }

        It 'runs the agent through a PowerShell host that survives its exit' {
            $call = (Get-CliCall -Subcommand 'spawn')[0]

            $call | Should -Contain '-NoExit'
        }

        It 'opens the pane in its own window' {
            (Get-CliCall -Subcommand 'spawn')[0] | Should -Contain '--new-window'
        }
    }

    Context 'when no wezterm is running' {

        BeforeEach {
            Set-WezTermMock -NoSocket
            # A path that does not exist, so the launch fails immediately instead of opening a
            # real window during the test run.
            Mock -ModuleName pwsh-ai-herd Get-WezTermPath { Join-Path $TestDrive 'no-such-wezterm.exe' }
            Mock -ModuleName pwsh-ai-herd Wait-WezTermPane { 1 }
        }

        It 'does not try to spawn into a multiplexer it cannot reach' {
            try {
                Build-Grid @{
                    Directory = $script:projectDir
                    Columns   = 1
                    Rows      = 1
                    Pane      = @(New-PaneSpec -Count 1)
                } | Out-Null
            }
            catch { }

            (Get-CliCall -Subcommand 'spawn').Count | Should -Be 0
        }

        It 'launches the GUI executable instead' {
            { Build-Grid @{
                Directory = $script:projectDir
                Columns   = 1
                Rows      = 1
                Pane      = @(New-PaneSpec -Count 1)
            } } | Should -Throw

            Should -Invoke -ModuleName pwsh-ai-herd Get-WezTermPath
        }
    }

    Context 'worktrees' {

        BeforeEach {
            Set-WezTermMock
            $script:worktreePath = Join-Path -Path $TestDrive -ChildPath "wt-$(New-Guid)"
        }

        It 'recreates a recorded worktree that is missing on disk' {
            Mock -ModuleName pwsh-ai-herd New-HerdWorktree {
                [PSCustomObject]@{ Path = $Path; Branch = $Branch }
            }

            Build-Grid @{
                Directory = $script:projectDir
                Columns   = 1
                Rows      = 1
                Pane      = @(New-PaneSpec -Count 1 -Worktree $script:worktreePath -Branch 'herd/demo-1')
                Resume    = $true
            } | Out-Null

            Should -Invoke -ModuleName pwsh-ai-herd New-HerdWorktree -ParameterFilter {
                $Branch -eq 'herd/demo-1'
            }
        }

        It 'does not touch a worktree that is already there' {
            [void](New-Item -Path $script:worktreePath -ItemType Directory -Force)
            Mock -ModuleName pwsh-ai-herd New-HerdWorktree { }

            Build-Grid @{
                Directory = $script:projectDir
                Columns   = 1
                Rows      = 1
                Pane      = @(New-PaneSpec -Count 1 -Worktree $script:worktreePath -Branch 'herd/demo-1')
            } | Out-Null

            Should -Not -Invoke -ModuleName pwsh-ai-herd New-HerdWorktree
        }

        It 'starts the agent in its worktree rather than the project directory' {
            [void](New-Item -Path $script:worktreePath -ItemType Directory -Force)

            Build-Grid @{
                Directory = $script:projectDir
                Columns   = 1
                Rows      = 1
                Pane      = @(New-PaneSpec -Count 1 -Worktree $script:worktreePath -Branch 'herd/demo-1')
            } | Out-Null

            (Get-CliCall -Subcommand 'spawn')[0] | Should -Contain $script:worktreePath
        }

        It 'warns and falls back to the project directory when the worktree cannot be made' {
            Mock -ModuleName pwsh-ai-herd New-HerdWorktree { throw 'git said no' }

            $result = Build-Grid @{
                Directory = $script:projectDir
                Columns   = 1
                Rows      = 1
                Pane      = @(New-PaneSpec -Count 1 -Worktree $script:worktreePath -Branch 'herd/demo-1')
            } 3>$null

            $result.Panes[0].Worktree            | Should -BeNullOrEmpty
            (Get-CliCall -Subcommand 'spawn')[0] | Should -Contain $script:projectDir
        }
    }

    Context 'the grid record' {

        BeforeEach {
            Set-WezTermMock
            $script:result = Build-Grid @{
                Directory = $script:projectDir
                Columns   = 2
                Rows      = 1
                Pane      = @(New-PaneSpec -Count 2)
            }
        }

        It 'is saved' {
            Should -Invoke -ModuleName pwsh-ai-herd Save-HerdGrid
        }

        It 'records the project directory and the layout' {
            $script:result.Directory | Should -Be $script:projectDir
            $script:result.Columns   | Should -Be 2
            $script:result.Rows      | Should -Be 1
        }

        It 'carries the file it was written to' {
            $script:result.Path | Should -Be 'C:\state\grid.json'
        }

        It 'is versioned, so a future format change can be detected' {
            $script:result.Version | Should -Be 1
        }
    }

    Context 'input validation' {

        BeforeEach { Set-WezTermMock }

        It 'refuses more agents than the grid can hold' {
            { Build-Grid @{
                Directory = $script:projectDir
                Columns   = 2
                Rows      = 1
                Pane      = @(New-PaneSpec -Count 3)
            } } | Should -Throw -ExpectedMessage '*do not fit*'
        }

        It 'requires at least one pane' {
            { Build-Grid @{
                Directory = $script:projectDir
                Columns   = 1
                Rows      = 1
                Pane      = @()
            } } | Should -Throw
        }
    }
}
