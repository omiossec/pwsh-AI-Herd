BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.ps1')

    function Write-GridFile {
        param([string]$Path, [string]$Directory, [int]$PaneCount = 2)

        $record = New-TestGridRecord -Directory $Directory -PaneCount $PaneCount
        $record | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding utf8
        return $Path
    }
}

Describe 'Read-HerdGrid' {

    BeforeEach {
        $script:gridDir = Join-Path -Path $TestDrive -ChildPath "grids-$(New-Guid)"
        [void](New-Item -Path $script:gridDir -ItemType Directory -Force)

        $script:projectDir = Join-Path -Path $TestDrive -ChildPath "project-$(New-Guid)"
        [void](New-Item -Path $script:projectDir -ItemType Directory -Force)

        Mock -ModuleName pwsh-ai-herd Get-HerdStatePath { $gridDir }
    }

    Context 'reading one record by path' {

        It 'returns the record' {
            $file = Write-GridFile -Path (Join-Path $script:gridDir 'a.json') -Directory $script:projectDir

            $result = InModuleScope pwsh-ai-herd -Parameters @{ p = $file } {
                param($p)
                Read-HerdGrid -Path $p
            }

            $result.Directory | Should -Be $script:projectDir
        }

        It 'adds the file path to the record so callers can save it back' {
            $file = Write-GridFile -Path (Join-Path $script:gridDir 'a.json') -Directory $script:projectDir

            (InModuleScope pwsh-ai-herd -Parameters @{ p = $file } {
                param($p)
                Read-HerdGrid -Path $p
            }).Path | Should -Be $file
        }

        It 'returns nothing for a file that does not exist' {
            InModuleScope pwsh-ai-herd -Parameters @{ p = (Join-Path $script:gridDir 'missing.json') } {
                param($p)
                Read-HerdGrid -Path $p
            } | Should -BeNullOrEmpty
        }
    }

    Context 'reading the record of a project directory' {

        It 'looks the file up by project directory' {
            $file = Write-GridFile -Path (Join-Path $script:gridDir 'b.json') -Directory $script:projectDir
            Mock -ModuleName pwsh-ai-herd Get-HerdGridPath { $file }

            (InModuleScope pwsh-ai-herd -Parameters @{ d = $script:projectDir } {
                param($d)
                Read-HerdGrid -Directory $d
            }).Directory | Should -Be $script:projectDir
        }

        It 'returns nothing when that project has no grid' {
            Mock -ModuleName pwsh-ai-herd Get-HerdGridPath { Join-Path $gridDir 'nope.json' }

            InModuleScope pwsh-ai-herd -Parameters @{ d = $script:projectDir } {
                param($d)
                Read-HerdGrid -Directory $d
            } | Should -BeNullOrEmpty
        }
    }

    Context 'listing every record' {

        It 'returns one record per file' {
            Write-GridFile -Path (Join-Path $script:gridDir 'a.json') -Directory $script:projectDir | Out-Null
            Write-GridFile -Path (Join-Path $script:gridDir 'b.json') -Directory $script:projectDir | Out-Null

            @(InModuleScope pwsh-ai-herd { Read-HerdGrid }).Count | Should -Be 2
        }

        It 'returns the most recently saved grid first' {
            $first = Write-GridFile -Path (Join-Path $script:gridDir 'a.json') -Directory $script:projectDir
            Start-Sleep -Milliseconds 1100
            $second = Write-GridFile -Path (Join-Path $script:gridDir 'b.json') -Directory $script:projectDir

            (@(InModuleScope pwsh-ai-herd { Read-HerdGrid })[0]).Path | Should -Be $second
        }

        It 'skips a grid whose project directory has been deleted' {
            Write-GridFile -Path (Join-Path $script:gridDir 'gone.json') -Directory (Join-Path $TestDrive 'deleted') | Out-Null

            @(InModuleScope pwsh-ai-herd { Read-HerdGrid }).Count | Should -Be 0
        }

        It 'returns nothing when no grid has ever been saved' {
            @(InModuleScope pwsh-ai-herd { Read-HerdGrid }).Count | Should -Be 0
        }
    }

    Context 'damaged records' {

        It 'warns and skips a file that is not JSON' {
            Set-Content -Path (Join-Path $script:gridDir 'broken.json') -Value 'not json at all'
            Write-GridFile -Path (Join-Path $script:gridDir 'good.json') -Directory $script:projectDir | Out-Null

            $warnings = @()
            $result = InModuleScope pwsh-ai-herd { Read-HerdGrid } -WarningVariable warnings 3>$null

            @($result).Count | Should -Be 1
        }

        It 'does not throw on a damaged record' {
            Set-Content -Path (Join-Path $script:gridDir 'broken.json') -Value '{ oops'

            { InModuleScope pwsh-ai-herd { Read-HerdGrid } 3>$null } | Should -Not -Throw
        }
    }

    Context 'the shape of the record' {

        It 'keeps the panes countable even for a single-pane grid' {
            # ConvertFrom-Json turns a one-element array into a bare object; the function
            # normalises it back so callers can index and count it.
            $file = Write-GridFile -Path (Join-Path $script:gridDir 'one.json') -Directory $script:projectDir -PaneCount 1

            $result = InModuleScope pwsh-ai-herd -Parameters @{ p = $file } {
                param($p)
                Read-HerdGrid -Path $p
            }

            @($result.Panes).Count | Should -Be 1
            $result.Panes[0].Index | Should -Be 0
        }

        It 'round-trips a record written by Save-HerdGrid' {
            $file = Join-Path $script:gridDir 'roundtrip.json'
            Mock -ModuleName pwsh-ai-herd Get-HerdGridPath { $file }
            $grid = New-TestGridRecord -Directory $script:projectDir -PaneCount 3

            InModuleScope pwsh-ai-herd -Parameters @{ g = $grid } {
                param($g)
                Save-HerdGrid -Grid $g
            } | Out-Null

            $back = InModuleScope pwsh-ai-herd -Parameters @{ p = $file } {
                param($p)
                Read-HerdGrid -Path $p
            }

            $back.Columns             | Should -Be $grid.Columns
            @($back.Panes).Count      | Should -Be 3
            $back.Panes[2].SessionId  | Should -Be $grid.Panes[2].SessionId
        }
    }
}
