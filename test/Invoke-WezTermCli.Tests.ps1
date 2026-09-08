BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.ps1')

    function Invoke-Cli {
        param([string[]]$Arguments, [switch]$Quiet)
        InModuleScope pwsh-ai-herd -Parameters @{ a = $Arguments; q = [bool]$Quiet } {
            param($a, $q)
            Invoke-WezTermCli -Arguments $a -Quiet:$q
        }
    }
}

Describe 'Invoke-WezTermCli' {

    Context 'a successful call' {

        BeforeEach {
            $script:fake = New-FakeWezTerm -Path (Join-Path -Path $TestDrive -ChildPath 'wezterm') -Emit '42'
            Mock -ModuleName pwsh-ai-herd Get-WezTermPath { $fake } -ParameterFilter { $true }
            Mock -ModuleName pwsh-ai-herd Get-WezTermSocket { 'C:\fake\gui-sock-1' }
        }

        It 'returns the standard output of wezterm' {
            Invoke-Cli -Arguments @('list') | Should -Be '42'
        }

        It 'trims the trailing newline the CLI writes' {
            Invoke-Cli -Arguments @('list') | Should -Not -Match '\r?\n$'
        }

        It 'always calls the cli subcommand' {
            Invoke-Cli -Arguments @('list') | Out-Null

            (Get-FakeWezTermCall -ScriptPath $script:fake)[0] | Should -BeLike 'cli *'
        }

        It 'passes --no-auto-start so a headless mux server is never created' {
            # Without it, probing for a running wezterm silently starts an invisible server and
            # the whole grid is spawned into it.
            Invoke-Cli -Arguments @('list') | Out-Null

            (Get-FakeWezTermCall -ScriptPath $script:fake)[0] | Should -BeLike '*--no-auto-start*'
        }

        It 'forwards the caller arguments in order' {
            Invoke-Cli -Arguments @('split-pane', '--pane-id', '3', '--right') | Out-Null

            (Get-FakeWezTermCall -ScriptPath $script:fake)[0] |
                Should -BeLike '*split-pane --pane-id 3 --right'
        }
    }

    Context 'the multiplexer socket' {

        BeforeEach {
            $script:fake = New-FakeWezTerm -Path (Join-Path -Path $TestDrive -ChildPath 'wezterm') -Emit 'ok'
            Mock -ModuleName pwsh-ai-herd Get-WezTermPath { $fake } -ParameterFilter { $true }
        }

        It 'restores the previous socket variable afterwards' {
            Mock -ModuleName pwsh-ai-herd Get-WezTermSocket { 'C:\fake\gui-sock-9' }
            $env:WEZTERM_UNIX_SOCKET = 'original-value'

            Invoke-Cli -Arguments @('list') | Out-Null

            $env:WEZTERM_UNIX_SOCKET | Should -Be 'original-value'
            Remove-Item -Path Env:WEZTERM_UNIX_SOCKET -ErrorAction SilentlyContinue
        }

        It 'leaves the variable unset when it was unset before' {
            Mock -ModuleName pwsh-ai-herd Get-WezTermSocket { 'C:\fake\gui-sock-9' }
            Remove-Item -Path Env:WEZTERM_UNIX_SOCKET -ErrorAction SilentlyContinue

            Invoke-Cli -Arguments @('list') | Out-Null

            $env:WEZTERM_UNIX_SOCKET | Should -BeNullOrEmpty
        }

        It 'still runs when no socket can be found' {
            Mock -ModuleName pwsh-ai-herd Get-WezTermSocket { $null }

            Invoke-Cli -Arguments @('list') | Should -Be 'ok'
        }
    }

    Context 'a failing call' {

        BeforeEach {
            $script:fake = New-FakeWezTerm -Path (Join-Path -Path $TestDrive -ChildPath 'wezterm') `
                -FailWith 1 -ErrorText 'no wezterm running'
            Mock -ModuleName pwsh-ai-herd Get-WezTermPath { $fake } -ParameterFilter { $true }
            Mock -ModuleName pwsh-ai-herd Get-WezTermSocket { $null }
        }

        It 'throws by default' {
            { Invoke-Cli -Arguments @('list') } | Should -Throw
        }

        It 'names the failing subcommand' {
            { Invoke-Cli -Arguments @('split-pane') } | Should -Throw -ExpectedMessage '*split-pane*'
        }

        It 'reports the exit code' {
            { Invoke-Cli -Arguments @('list') } | Should -Throw -ExpectedMessage '*exit 1*'
        }

        It 'includes what wezterm wrote to stderr' {
            { Invoke-Cli -Arguments @('list') } | Should -Throw -ExpectedMessage '*no wezterm running*'
        }

        It 'returns nothing instead of throwing when Quiet is used to probe' {
            Invoke-Cli -Arguments @('list') -Quiet | Should -BeNullOrEmpty
        }
    }

    Context 'input validation' {

        It 'requires arguments' {
            { InModuleScope pwsh-ai-herd { Invoke-WezTermCli -Arguments @() } } | Should -Throw
        }
    }
}
