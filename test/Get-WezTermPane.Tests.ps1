BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    $script:PaneJson = @'
[
  { "window_id": 0, "tab_id": 0, "pane_id": 1, "workspace": "default",
    "size": { "rows": 24, "cols": 80 }, "title": "Claude Code", "cwd": "file:///C:/work/" },
  { "window_id": 0, "tab_id": 0, "pane_id": 2, "workspace": "default",
    "size": { "rows": 24, "cols": 80 }, "title": "Claude Code", "cwd": "file:///C:/work/" }
]
'@

    function Get-Panes {
        param([switch]$Quiet)
        InModuleScope pwsh-ai-herd -Parameters @{ q = [bool]$Quiet } {
            param($q)
            , @(Get-WezTermPane -Quiet:$q)
        }
    }
}

Describe 'Get-WezTermPane' {

    Context 'with panes open' {

        BeforeAll {
            Mock -ModuleName pwsh-ai-herd Invoke-WezTermCli { $script:PaneJson }
        }

        It 'asks wezterm for the pane list as JSON' {
            Get-Panes | Out-Null

            Should -Invoke -ModuleName pwsh-ai-herd Invoke-WezTermCli -ParameterFilter {
                $Arguments -contains 'list' -and $Arguments -contains '--format' -and $Arguments -contains 'json'
            }
        }

        It 'returns one object per pane' {
            (Get-Panes).Count | Should -Be 2
        }

        It 'exposes the pane id' {
            (Get-Panes)[0].pane_id | Should -Be 1
        }

        It 'exposes the window id, which groups the panes of one grid' {
            (Get-Panes)[1].window_id | Should -Be 0
        }

        It 'exposes the nested size' {
            (Get-Panes)[0].size.rows | Should -Be 24
        }

        It 'exposes the working directory' {
            (Get-Panes)[0].cwd | Should -BeLike 'file:///*'
        }
    }

    Context 'with no wezterm running' {

        It 'returns an empty collection when the CLI says nothing' {
            Mock -ModuleName pwsh-ai-herd Invoke-WezTermCli { '' }

            (Get-Panes).Count | Should -Be 0
        }

        It 'returns an empty collection when the CLI returns null' {
            Mock -ModuleName pwsh-ai-herd Invoke-WezTermCli { $null }

            (Get-Panes).Count | Should -Be 0
        }

        It 'passes Quiet through so a probe does not throw' {
            Mock -ModuleName pwsh-ai-herd Invoke-WezTermCli { $null }

            Get-Panes -Quiet | Out-Null

            Should -Invoke -ModuleName pwsh-ai-herd Invoke-WezTermCli -ParameterFilter { $Quiet }
        }
    }

    Context 'a single pane' {

        It 'still returns a countable collection' {
            Mock -ModuleName pwsh-ai-herd Invoke-WezTermCli { '[{ "pane_id": 7 }]' }

            $result = Get-Panes

            $result.Count      | Should -Be 1
            $result[0].pane_id | Should -Be 7
        }
    }
}
