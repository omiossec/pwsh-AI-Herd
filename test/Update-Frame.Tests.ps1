BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.ps1')

    # Update-Frame walks the module's frame list, so the fakes have to be installed there.
    function Invoke-Pump {
        param($Frame, [int]$MaxLine = 300)

        InModuleScope pwsh-ai-herd -Parameters @{ f = $Frame; max = $MaxLine } {
            param($f, $max)
            $script:MaxLine = $max
            $script:Frames  = [System.Collections.Generic.List[psobject]]::new()
            $script:Frames.Add($f)
            Update-Frame
        }
    }
}

Describe 'Update-Frame' {

    BeforeEach {
        Mock -ModuleName pwsh-ai-herd Update-FrameView { }
    }

    Context 'the timer contract' {

        It 'returns true so Terminal.Gui keeps the timeout alive' {
            Invoke-Pump -Frame (New-FakeFrame) | Should -BeTrue
        }

        It 'returns true even when there is nothing to do' {
            $frame = New-FakeFrame

            Invoke-Pump -Frame $frame | Should -BeTrue
        }
    }

    Context 'draining a plain text frame' {

        It 'moves queued output into the frame' {
            $frame = New-FakeFrame -Protocol Text
            $frame.Process.Output.Enqueue('first')
            $frame.Process.Output.Enqueue('second')

            Invoke-Pump -Frame $frame | Out-Null

            $frame.Lines | Should -Be @('first', 'second')
        }

        It 'empties the queue' {
            $frame = New-FakeFrame -Protocol Text
            $frame.Process.Output.Enqueue('first')

            Invoke-Pump -Frame $frame | Out-Null

            $frame.Process.Output.Count | Should -Be 0
        }

        It 'leaves stderr markers in place' {
            $frame = New-FakeFrame -Protocol Text
            $frame.Process.Output.Enqueue('! something went wrong')

            Invoke-Pump -Frame $frame | Out-Null

            $frame.Lines[0] | Should -Be '! something went wrong'
        }

        It 'redraws only when something arrived' {
            $frame = New-FakeFrame -Protocol Text

            Invoke-Pump -Frame $frame | Out-Null

            Should -Not -Invoke -ModuleName pwsh-ai-herd Update-FrameView
        }

        It 'redraws once when output arrived' {
            $frame = New-FakeFrame -Protocol Text
            $frame.Process.Output.Enqueue('first')

            Invoke-Pump -Frame $frame | Out-Null

            Should -Invoke -ModuleName pwsh-ai-herd Update-FrameView -Times 1 -Exactly
        }
    }

    Context 'draining a streaming JSON frame' {

        It 'renders an agent event as display text' {
            $frame = New-FakeFrame -Protocol StreamJson
            $frame.Process.Output.Enqueue('{"type":"system","subtype":"init","model":"claude-opus-5"}')

            Invoke-Pump -Frame $frame | Out-Null

            $frame.Lines[0] | Should -Be '-- session started | claude-opus-5 --'
        }

        It 'drops bookkeeping events instead of adding empty lines' {
            $frame = New-FakeFrame -Protocol StreamJson
            $frame.Process.Output.Enqueue('{"type":"stream_event"}')

            Invoke-Pump -Frame $frame | Out-Null

            $frame.Lines.Count | Should -Be 0
        }

        It 'adds every line of a multi-line reply' {
            $frame = New-FakeFrame -Protocol StreamJson
            $agentEvent = @{ type = 'assistant'; message = @{ content = @(@{ type = 'text'; text = "one`ntwo" }) } }
            $frame.Process.Output.Enqueue(($agentEvent | ConvertTo-Json -Depth 10 -Compress))

            Invoke-Pump -Frame $frame | Out-Null

            $frame.Lines | Should -Be @('one', 'two')
        }

        It 'does not redraw for an event that renders to nothing' {
            $frame = New-FakeFrame -Protocol StreamJson
            $frame.Process.Output.Enqueue('{"type":"stream_event"}')

            Invoke-Pump -Frame $frame | Out-Null

            # The queue changed even though no line was added, so a redraw is still requested.
            Should -Invoke -ModuleName pwsh-ai-herd Update-FrameView -Times 1 -Exactly
        }
    }

    Context 'the scroll-back limit' {

        It 'keeps only the newest lines' {
            $frame = New-FakeFrame -Protocol Text
            1..20 | ForEach-Object { $frame.Process.Output.Enqueue("line $_") }

            Invoke-Pump -Frame $frame -MaxLine 5 | Out-Null

            $frame.Lines.Count | Should -Be 5
        }

        It 'drops the oldest lines, not the newest' {
            $frame = New-FakeFrame -Protocol Text
            1..20 | ForEach-Object { $frame.Process.Output.Enqueue("line $_") }

            Invoke-Pump -Frame $frame -MaxLine 5 | Out-Null

            $frame.Lines[-1] | Should -Be 'line 20'
            $frame.Lines[0]  | Should -Be 'line 16'
        }

        It 'leaves a short frame alone' {
            $frame = New-FakeFrame -Protocol Text
            1..3 | ForEach-Object { $frame.Process.Output.Enqueue("line $_") }

            Invoke-Pump -Frame $frame -MaxLine 300 | Out-Null

            $frame.Lines.Count | Should -Be 3
        }
    }

    Context 'a process that has exited' {

        It 'says so in the frame' {
            $frame = New-FakeFrame -HasExited $true -ExitCode 1

            Invoke-Pump -Frame $frame | Out-Null

            $frame.Lines[-1] | Should -Be '-- process exited with code 1 --'
        }

        It 'says so in the title' {
            $frame = New-FakeFrame -HasExited $true -ExitCode 1 -Id 999

            Invoke-Pump -Frame $frame | Out-Null

            $frame.View.Title | Should -BeLike '*exited (1)*'
        }

        It 'keeps the process id in the title' {
            $frame = New-FakeFrame -HasExited $true -Id 999

            Invoke-Pump -Frame $frame | Out-Null

            $frame.View.Title | Should -BeLike 'PID 999*'
        }

        It 'notes the exit once, not on every tick' {
            $frame = New-FakeFrame -HasExited $true

            Invoke-Pump -Frame $frame | Out-Null
            Invoke-Pump -Frame $frame | Out-Null
            Invoke-Pump -Frame $frame | Out-Null

            @($frame.Lines | Where-Object { $_ -like '*process exited*' }).Count | Should -Be 1
        }

        It 'still drains what the process wrote before exiting' {
            $frame = New-FakeFrame -HasExited $true -ExitCode 0
            $frame.Process.Output.Enqueue('final words')

            Invoke-Pump -Frame $frame | Out-Null

            $frame.Lines[0] | Should -Be 'final words'
        }
    }

    Context 'no frames at all' {

        It 'still returns true' {
            InModuleScope pwsh-ai-herd {
                $script:Frames = [System.Collections.Generic.List[psobject]]::new()
                Update-Frame
            } | Should -BeTrue
        }
    }
}
