BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    function Split-Line {
        param([string]$Line)
        InModuleScope pwsh-ai-herd -Parameters @{ text = $Line } {
            param($text)
            Split-CommandLine -CommandLine $text
        }
    }
}

Describe 'Split-CommandLine' {

    Context 'an unquoted executable' {

        It 'splits on the first space' {
            $result = Split-Line 'claude --print --verbose'

            $result.FileName  | Should -Be 'claude'
            $result.Arguments | Should -Be '--print --verbose'
        }

        It 'returns an empty argument string when there are no arguments' {
            $result = Split-Line 'codex'

            $result.FileName  | Should -Be 'codex'
            $result.Arguments | Should -BeNullOrEmpty
        }

        It 'keeps later spaces in the argument string untouched' {
            $result = Split-Line 'git commit -m "two words"'

            $result.FileName  | Should -Be 'git'
            $result.Arguments | Should -Be 'commit -m "two words"'
        }

        It 'trims surrounding whitespace before splitting' {
            $result = Split-Line "   ping localhost   "

            $result.FileName  | Should -Be 'ping'
            $result.Arguments | Should -Be 'localhost'
        }
    }

    Context 'a quoted executable path' {

        It 'takes everything inside the quotes as the file name' {
            $result = Split-Line '"C:\Program Files\Git\bin\git.exe" log --oneline'

            $result.FileName  | Should -Be 'C:\Program Files\Git\bin\git.exe'
            $result.Arguments | Should -Be 'log --oneline'
        }

        It 'drops the quotes from the file name' {
            (Split-Line '"C:\tools\a b.exe"').FileName | Should -Not -Match '"'
        }

        It 'returns no arguments for a bare quoted path' {
            (Split-Line '"C:\tools\a b.exe"').Arguments | Should -BeNullOrEmpty
        }

        It 'strips the whitespace between the closing quote and the first argument' {
            (Split-Line '"C:\a b.exe"     --flag').Arguments | Should -Be '--flag'
        }

        It 'throws on an unbalanced quote rather than guessing' {
            { Split-Line '"C:\Program Files\git.exe log' } | Should -Throw -ExpectedMessage '*Unbalanced quote*'
        }
    }

    Context 'input validation' {

        It 'rejects an empty command line' {
            { Split-Line '' } | Should -Throw
        }

        It 'returns an empty file name for a whitespace-only command line' {
            # ValidateNotNullOrEmpty lets whitespace through. Starting a process with an empty
            # file name then fails in New-Frame, which reports it in a message box.
            $result = Split-Line '   '

            $result.FileName  | Should -BeNullOrEmpty
            $result.Arguments | Should -BeNullOrEmpty
        }
    }

    Context 'the documented limitation' {

        It 'does not tokenise quotes that are not at the start' {
            # Deliberately simple: only a LEADING quote delimits the executable.
            $result = Split-Line 'git commit -m "a b"'

            $result.Arguments | Should -Be 'commit -m "a b"'
        }
    }
}
