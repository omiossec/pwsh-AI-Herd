BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.ps1')

    function Set-PaneMock {
        param([int[]]$LivePaneId = @(0, 1))

        $global:HerdCliCalls = [System.Collections.Generic.List[object]]::new()
        $global:HerdLivePanes = @($LivePaneId | ForEach-Object { [PSCustomObject]@{ pane_id = $_ } })

        Mock -ModuleName pwsh-ai-herd Get-WezTermPane { $global:HerdLivePanes }
        Mock -ModuleName pwsh-ai-herd Invoke-WezTermCli { $global:HerdCliCalls.Add(@($Arguments)); return '' }
    }

    function Get-SentText {
        , @($global:HerdCliCalls | Where-Object { $_ -notcontains '--no-paste' })
    }

    function Get-EnterKey {
        , @($global:HerdCliCalls | Where-Object { $_ -contains '--no-paste' })
    }
}

AfterAll {
    Remove-Variable -Name 'HerdCliCalls', 'HerdLivePanes' -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Send-AiGridText' {

    BeforeEach {
        $script:projectDir = Join-Path -Path $TestDrive -ChildPath "project-$(New-Guid)"
        [void](New-Item -Path $script:projectDir -ItemType Directory -Force)

        $script:grid = New-TestGridRecord -Directory $script:projectDir -PaneCount 2
        Mock -ModuleName pwsh-ai-herd Resolve-HerdGrid { $grid }
        Set-PaneMock -LivePaneId @(0, 1)
    }

    Context 'broadcasting to every pane' {

        BeforeEach {
            Send-AiGridText -Text 'run the tests' -Confirm:$false
        }

        It 'types the text into each pane' {
            (Get-SentText).Count | Should -Be 2
        }

        It 'sends the text the caller gave' {
            (Get-SentText)[0] | Should -Contain 'run the tests'
        }

        It 'addresses each pane by id' {
            (Get-SentText)[0] | Should -Contain 0
            (Get-SentText)[1] | Should -Contain 1
        }

        It 'presses Enter afterwards so the agent acts on it' {
            (Get-EnterKey).Count | Should -Be 2
        }

        It 'sends a carriage return as the Enter key' {
            (Get-EnterKey)[0] | Should -Contain "`r"
        }

        It 'sends the Enter key raw, not as a paste' {
            (Get-EnterKey)[0] | Should -Contain '--no-paste'
        }
    }

    Context 'without pressing Enter' {

        It 'leaves the text sitting in the prompt' {
            Send-AiGridText -Text 'draft only' -NoEnter -Confirm:$false

            (Get-SentText).Count | Should -Be 2
            (Get-EnterKey).Count | Should -Be 0
        }
    }

    Context 'targeting some panes' {

        It 'sends only to the panes named' {
            Send-AiGridText -Text 'you only' -PaneIndex 1 -Confirm:$false

            (Get-SentText).Count | Should -Be 1
            (Get-SentText)[0]    | Should -Contain 1
        }

        It 'accepts several indexes' {
            $script:grid = New-TestGridRecord -Directory $script:projectDir -PaneCount 4
            Mock -ModuleName pwsh-ai-herd Resolve-HerdGrid { $grid }
            Set-PaneMock -LivePaneId @(0, 1, 2, 3)

            Send-AiGridText -Text 'two of you' -PaneIndex 0, 2 -Confirm:$false

            (Get-SentText).Count | Should -Be 2
        }

        It 'sends nothing when no pane matches' {
            Send-AiGridText -Text 'nobody' -PaneIndex 99 -Confirm:$false

            (Get-SentText).Count | Should -Be 0
        }
    }

    Context 'panes that have been closed' {

        It 'skips a pane that is no longer open' {
            Set-PaneMock -LivePaneId @(0)

            Send-AiGridText -Text 'hello' -Confirm:$false

            (Get-SentText).Count | Should -Be 1
        }

        It 'does nothing at all when the window has been closed' {
            Set-PaneMock -LivePaneId @()

            Send-AiGridText -Text 'hello' -Confirm:$false

            (Get-SentText).Count | Should -Be 0
        }

        It 'does not throw when every pane is gone' {
            Set-PaneMock -LivePaneId @()

            { Send-AiGridText -Text 'hello' -Confirm:$false } | Should -Not -Throw
        }
    }

    Context 'the pipeline' {

        It 'accepts the text from the pipeline' {
            'from the pipeline' | Send-AiGridText -Confirm:$false

            (Get-SentText)[0] | Should -Contain 'from the pipeline'
        }
    }

    Context 'WhatIf' {

        It 'sends nothing' {
            Send-AiGridText -Text 'hello' -WhatIf

            (Get-SentText).Count | Should -Be 0
        }
    }

    Context 'input validation' {

        It 'requires text' {
            { Send-AiGridText -Text '' -Confirm:$false } | Should -Throw
        }
    }
}
