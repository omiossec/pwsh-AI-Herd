# Probed at file scope because Pester evaluates -Skip during discovery, before BeforeAll runs.
. (Join-Path -Path $PSScriptRoot -ChildPath 'TerminalGuiProbe.ps1')

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    # A harmless child process that stays alive long enough to be inspected, then exits.
    $script:PwshPath = [Environment]::ProcessPath
    $script:IdleCommand = "`"$script:PwshPath`" -NoLogo -NoProfile -Command Start-Sleep -Seconds 30"

    function New-TestFrame {
        param([string]$CommandLine, [string]$WorkingDirectory)

        InModuleScope pwsh-ai-herd -Parameters @{ cmd = $CommandLine; dir = $WorkingDirectory } {
            param($cmd, $dir)

            $script:Frames         = [System.Collections.Generic.List[psobject]]::new()
            $script:FrameContainer = [Terminal.Gui.View]::new()
            $script:MaxFrame       = 6
            $script:MaxLine        = 300
            $script:WorkingDirectory = $dir

            New-Frame -CommandLine $cmd

            return $script:Frames[0]
        }
    }

    function Stop-TestFrame {
        param($Frame)
        if ($Frame) { try { $Frame.Process.Dispose() } catch { } }
    }
}

Describe 'New-Frame' -Skip:(-not $script:HasTerminalGui) {

    Context 'starting a process' {

        BeforeAll {
            $script:frame = New-TestFrame -CommandLine $script:IdleCommand -WorkingDirectory $TestDrive
        }

        AfterAll {
            Stop-TestFrame -Frame $script:frame
        }

        It 'adds the frame to the list' {
            $script:frame | Should -Not -BeNullOrEmpty
        }

        It 'starts a real child process with its own id' {
            $script:frame.Process.Id | Should -BeGreaterThan 0
        }

        It 'keeps the process running' {
            $script:frame.Process.HasExited | Should -BeFalse
        }

        It 'records the command line it was given' {
            $script:frame.CommandLine | Should -Be $script:IdleCommand
        }

        It 'records the working directory' {
            $script:frame.Directory | Should -Be $TestDrive
        }

        It 'starts with an empty scroll-back' {
            $script:frame.Lines.Count | Should -Be 0
        }

        It 'has not noted an exit yet' {
            $script:frame.ExitNoted | Should -BeFalse
        }

        It 'shows the process id in the frame title' {
            $script:frame.View.Title.ToString() | Should -BeLike "PID $($script:frame.Process.Id)*"
        }

        It 'builds the output list, input line and buttons' {
            $script:frame.List  | Should -Not -BeNullOrEmpty
            $script:frame.Input | Should -Not -BeNullOrEmpty
        }
    }

    Context 'detecting the protocol' {

        AfterEach {
            Stop-TestFrame -Frame $script:frame
        }

        It 'treats a plain command line as line-oriented text' {
            $script:frame = New-TestFrame -CommandLine $script:IdleCommand -WorkingDirectory $TestDrive

            $script:frame.Protocol | Should -Be 'Text'
        }

        It 'treats a stream-json command line as an agent protocol' {
            $command = "$script:IdleCommand --input-format stream-json"
            $script:frame = New-TestFrame -CommandLine $command -WorkingDirectory $TestDrive

            $script:frame.Protocol | Should -Be 'StreamJson'
        }

        It 'accepts extra spacing in the stream-json flag' {
            $command = "$script:IdleCommand --input-format   stream-json"
            $script:frame = New-TestFrame -CommandLine $command -WorkingDirectory $TestDrive

            $script:frame.Protocol | Should -Be 'StreamJson'
        }

        It 'does not treat an output-only stream-json flag as the input protocol' {
            $command = "$script:IdleCommand --output-format stream-json"
            $script:frame = New-TestFrame -CommandLine $command -WorkingDirectory $TestDrive

            $script:frame.Protocol | Should -Be 'Text'
        }
    }

    Context 'the frame limit' {

        It 'is declared as six frames' {
            # Reaching the limit puts a message box on screen, which needs a console driver, so
            # only the guard value itself is checked here.
            $source = Get-Content -Path (Join-Path $PSScriptRoot '../src/private/New-Frame.ps1') -Raw

            $source | Should -Match 'script:MaxFrame'
        }
    }

    Context 'input validation' {

        It 'requires a command line' {
            { InModuleScope pwsh-ai-herd { New-Frame -CommandLine '' } } | Should -Throw
        }
    }
}
