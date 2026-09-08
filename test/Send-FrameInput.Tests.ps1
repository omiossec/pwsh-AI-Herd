BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.ps1')

    function Send-Input {
        param($Frame)
        InModuleScope pwsh-ai-herd -Parameters @{ f = $Frame } {
            param($f)
            Send-FrameInput -Frame $f
        }
    }
}

Describe 'Send-FrameInput' {

    BeforeEach {
        Mock -ModuleName pwsh-ai-herd Update-FrameView { }
    }

    Context 'a plain text frame' {

        It 'writes the typed line to stdin unchanged' {
            $frame = New-FakeFrame -Protocol Text -InputText 'ping localhost'

            Send-Input -Frame $frame

            $frame.Process.Sent | Should -Be @('ping localhost')
        }

        It 'echoes what was typed into the frame' {
            $frame = New-FakeFrame -Protocol Text -InputText 'hello'

            Send-Input -Frame $frame

            $frame.Lines | Should -Be @('> hello')
        }

        It 'clears the input line' {
            $frame = New-FakeFrame -Protocol Text -InputText 'hello'

            Send-Input -Frame $frame

            $frame.Input.Text | Should -Be ''
        }

        It 'refreshes the view' {
            $frame = New-FakeFrame -Protocol Text -InputText 'hello'

            Send-Input -Frame $frame

            Should -Invoke -ModuleName pwsh-ai-herd Update-FrameView -Times 1 -Exactly
        }

        It 'sends an empty line when nothing was typed' {
            $frame = New-FakeFrame -Protocol Text -InputText ''

            Send-Input -Frame $frame

            $frame.Process.Sent | Should -Be @('')
        }
    }

    Context 'a streaming JSON frame' {

        BeforeEach {
            $script:frame = New-FakeFrame -Protocol StreamJson -InputText 'refactor the parser'
            Send-Input -Frame $script:frame
            $script:payload = $script:frame.Process.Sent[0] | ConvertFrom-Json
        }

        It 'wraps the text in an envelope the agent understands' {
            $script:payload.type         | Should -Be 'user'
            $script:payload.message.role | Should -Be 'user'
        }

        It 'carries the typed text as a text block' {
            $script:payload.message.content[0].type | Should -Be 'text'
            $script:payload.message.content[0].text | Should -Be 'refactor the parser'
        }

        It 'sends one line of JSON, because the protocol is newline delimited' {
            $script:frame.Process.Sent[0] | Should -Not -Match '\r?\n'
        }

        It 'echoes the typed text, not the JSON' {
            $script:frame.Lines | Should -Be @('> refactor the parser')
        }

        It 'escapes a quote in the typed text' {
            $frame = New-FakeFrame -Protocol StreamJson -InputText 'say "hello"'

            Send-Input -Frame $frame

            { $frame.Process.Sent[0] | ConvertFrom-Json } | Should -Not -Throw
            ($frame.Process.Sent[0] | ConvertFrom-Json).message.content[0].text | Should -Be 'say "hello"'
        }
    }

    Context 'a process that has already exited' {

        BeforeEach {
            $script:frame = New-FakeFrame -Protocol Text -InputText 'too late' -HasExited $true
            Send-Input -Frame $script:frame
        }

        It 'writes nothing' {
            $script:frame.Process.Sent.Count | Should -Be 0
        }

        It 'adds nothing to the frame' {
            $script:frame.Lines.Count | Should -Be 0
        }

        It 'leaves the input line alone so the text is not lost' {
            $script:frame.Input.Text | Should -Be 'too late'
        }
    }
}
