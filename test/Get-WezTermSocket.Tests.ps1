BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    function Get-Socket {
        InModuleScope pwsh-ai-herd { Get-WezTermSocket }
    }

    # Sockets live in the runtime directory; the tests below stand in for its contents. The
    # canned values go through globals: a mock body bound to a module cannot see the locals of
    # the function that declared it.
    function Set-FakeRuntime {
        param(
            [string[]]$GuiSocket = @(),
            [bool]$MuxSocketExists = $false,
            [object[]]$LiveProcess = @()
        )

        $global:HerdFakeSockets = @($GuiSocket | ForEach-Object {
            [PSCustomObject]@{ Name = $_; FullName = "/runtime/$_"; LastWriteTime = [datetime]'2026-01-01' }
        })
        $global:HerdFakeProcesses = @($LiveProcess)
        $global:HerdFakeMuxSocket = $MuxSocketExists

        Mock -ModuleName pwsh-ai-herd Get-Process { $global:HerdFakeProcesses } -ParameterFilter { $Name }
        Mock -ModuleName pwsh-ai-herd Get-ChildItem { $global:HerdFakeSockets } -ParameterFilter { $Filter -eq 'gui-sock-*' }
        Mock -ModuleName pwsh-ai-herd Test-Path { $true } -ParameterFilter { $PathType -eq 'Container' }
        Mock -ModuleName pwsh-ai-herd Test-Path { $global:HerdFakeMuxSocket } -ParameterFilter { $PathType -ne 'Container' }
    }
}

Describe 'Get-WezTermSocket' {

    BeforeEach {
        $script:savedSocket = $env:WEZTERM_UNIX_SOCKET
        Remove-Item -Path Env:WEZTERM_UNIX_SOCKET -ErrorAction SilentlyContinue
    }

    AfterEach {
        if ($script:savedSocket) { $env:WEZTERM_UNIX_SOCKET = $script:savedSocket }
        else { Remove-Item -Path Env:WEZTERM_UNIX_SOCKET -ErrorAction SilentlyContinue }

        Remove-Variable -Name 'HerdFakeSockets', 'HerdFakeProcesses', 'HerdFakeMuxSocket' `
            -Scope Global -ErrorAction SilentlyContinue
    }

    Context 'inside a wezterm pane' {

        It 'uses the socket wezterm already exported' {
            $env:WEZTERM_UNIX_SOCKET = '/run/user/1000/wezterm/gui-sock-77'

            Get-Socket | Should -Be '/run/user/1000/wezterm/gui-sock-77'
        }

        It 'does not go looking on disk' {
            $env:WEZTERM_UNIX_SOCKET = '/run/wezterm/gui-sock-77'
            Mock -ModuleName pwsh-ai-herd Get-ChildItem { @() }

            Get-Socket | Out-Null

            Should -Not -Invoke -ModuleName pwsh-ai-herd Get-ChildItem
        }
    }

    Context 'from an ordinary console with a GUI running' {

        It 'finds the socket of the running GUI' {
            Set-FakeRuntime -GuiSocket @('gui-sock-4242') `
                -LiveProcess @([PSCustomObject]@{ Id = 4242; ProcessName = 'wezterm-gui' })

            Get-Socket | Should -Be '/runtime/gui-sock-4242'
        }

        It 'ignores a socket left behind by a dead GUI' {
            Set-FakeRuntime -GuiSocket @('gui-sock-999') `
                -LiveProcess @([PSCustomObject]@{ Id = 4242; ProcessName = 'wezterm-gui' })

            Get-Socket | Should -BeNullOrEmpty
        }

        It 'picks the most recent socket when several GUIs run' {
            Set-FakeRuntime -GuiSocket @('gui-sock-1', 'gui-sock-2') -LiveProcess @(
                [PSCustomObject]@{ Id = 1; ProcessName = 'wezterm-gui' }
                [PSCustomObject]@{ Id = 2; ProcessName = 'wezterm-gui' }
            )
            $global:HerdFakeSockets[1].LastWriteTime = [datetime]'2026-06-01'

            Get-Socket | Should -Be '/runtime/gui-sock-2'
        }
    }

    Context 'with only a headless multiplexer server' {

        It 'falls back to the mux socket when such a server is running' {
            Set-FakeRuntime -MuxSocketExists $true `
                -LiveProcess @([PSCustomObject]@{ Id = 7; ProcessName = 'wezterm-mux-server' })

            Get-Socket | Should -BeLike '*sock'
        }

        It 'ignores a stale mux socket file when no server is running' {
            Set-FakeRuntime -MuxSocketExists $true -LiveProcess @()

            Get-Socket | Should -BeNullOrEmpty
        }
    }

    Context 'with nothing running' {

        It 'returns nothing rather than a path that cannot be reached' {
            Set-FakeRuntime

            Get-Socket | Should -BeNullOrEmpty
        }

        It 'survives a missing runtime directory' {
            Mock -ModuleName pwsh-ai-herd Get-Process { @() } -ParameterFilter { $Name }
            Mock -ModuleName pwsh-ai-herd Test-Path { $false }

            { Get-Socket } | Should -Not -Throw
        }
    }

    Context 'on the real machine' {

        It 'returns either nothing or an existing path' {
            $result = Get-Socket

            if ($result) { Test-Path -Path $result | Should -BeTrue }
            else { $result | Should -BeNullOrEmpty }
        }
    }
}
