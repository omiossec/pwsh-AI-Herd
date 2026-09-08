BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.ps1')
}

Describe 'Save-HerdGrid' {

    BeforeEach {
        $script:gridFile = Join-Path -Path $TestDrive -ChildPath 'grid.json'
        Mock -ModuleName pwsh-ai-herd Get-HerdGridPath { $gridFile }

        $script:grid = New-TestGridRecord -Directory 'C:\work\project' -PaneCount 2
    }

    Context 'writing the record' {

        It 'returns the path it wrote to' {
            InModuleScope pwsh-ai-herd -Parameters @{ g = $script:grid } {
                param($g)
                Save-HerdGrid -Grid $g
            } | Should -Be $script:gridFile
        }

        It 'creates the file' {
            InModuleScope pwsh-ai-herd -Parameters @{ g = $script:grid } {
                param($g)
                Save-HerdGrid -Grid $g
            } | Out-Null

            Test-Path -Path $script:gridFile | Should -BeTrue
        }

        It 'writes valid JSON' {
            InModuleScope pwsh-ai-herd -Parameters @{ g = $script:grid } {
                param($g)
                Save-HerdGrid -Grid $g
            } | Out-Null

            { Get-Content -Path $script:gridFile -Raw | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'keys the file on the project directory' {
            InModuleScope pwsh-ai-herd -Parameters @{ g = $script:grid } {
                param($g)
                Save-HerdGrid -Grid $g
            } | Out-Null

            Should -Invoke -ModuleName pwsh-ai-herd Get-HerdGridPath -ParameterFilter {
                $Directory -eq 'C:\work\project'
            }
        }
    }

    Context 'what the record contains' {

        BeforeEach {
            InModuleScope pwsh-ai-herd -Parameters @{ g = $script:grid } {
                param($g)
                Save-HerdGrid -Grid $g
            } | Out-Null

            $script:written = Get-Content -Path $script:gridFile -Raw | ConvertFrom-Json
        }

        It 'keeps the project directory' {
            $script:written.Directory | Should -Be 'C:\work\project'
        }

        It 'keeps the layout' {
            $script:written.Columns | Should -Be 2
            $script:written.Rows    | Should -Be 1
        }

        It 'keeps one entry per pane' {
            @($script:written.Panes).Count | Should -Be 2
        }

        It 'keeps the session id, which is the durable identity of an agent' {
            $script:written.Panes[0].SessionId | Should -Be $script:grid.Panes[0].SessionId
        }

        It 'stamps the save time' {
            $script:written.Saved | Should -Not -BeNullOrEmpty
        }

        It 'stamps a round-trippable timestamp' {
            { [datetimeoffset]::Parse($script:written.Saved) } | Should -Not -Throw
        }
    }

    Context 'overwriting' {

        It 'replaces the previous record rather than appending' {
            $save = {
                param($g)
                Save-HerdGrid -Grid $g
            }

            InModuleScope pwsh-ai-herd -Parameters @{ g = $script:grid } $save | Out-Null
            $script:grid.Columns = 3
            InModuleScope pwsh-ai-herd -Parameters @{ g = $script:grid } $save | Out-Null

            (Get-Content -Path $script:gridFile -Raw | ConvertFrom-Json).Columns | Should -Be 3
        }

        It 'updates the save stamp on the object it was given' {
            $before = $script:grid.Saved
            Start-Sleep -Milliseconds 20

            InModuleScope pwsh-ai-herd -Parameters @{ g = $script:grid } {
                param($g)
                Save-HerdGrid -Grid $g
            } | Out-Null

            $script:grid.Saved | Should -Not -Be $before
        }
    }

    Context 'input validation' {

        It 'requires a grid' {
            { InModuleScope pwsh-ai-herd { Save-HerdGrid -Grid $null } } | Should -Throw
        }
    }
}
