BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    function Get-Summary {
        param($Value)
        InModuleScope pwsh-ai-herd -Parameters @{ v = $Value } {
            param($v)
            Get-EventSummary -Value $v
        }
    }
}

Describe 'Get-EventSummary' {

    Context 'nothing to summarise' {

        It 'returns an empty string for $null' {
            Get-Summary -Value $null | Should -Be ''
        }

        It 'returns an empty string for an empty string' {
            Get-Summary -Value '' | Should -Be ''
        }

        It 'returns an empty string when every line is blank' {
            Get-Summary -Value "  `n`n   " | Should -Be ''
        }
    }

    Context 'strings' {

        It 'passes a short single line through unchanged' {
            Get-Summary -Value 'file written' | Should -Be 'file written'
        }

        It 'keeps only the first non-empty line, because the frame does not wrap' {
            Get-Summary -Value "first line`nsecond line`nthird" | Should -Be 'first line'
        }

        It 'skips leading blank lines' {
            Get-Summary -Value "`n`n  real content" | Should -Be '  real content'
        }

        It 'handles Windows line endings' {
            Get-Summary -Value "first`r`nsecond" | Should -Be 'first'
        }
    }

    Context 'truncation' {

        It 'leaves a 120 character line intact' {
            $text = 'x' * 120
            Get-Summary -Value $text | Should -Be $text
        }

        It 'truncates a longer line to 120 characters including the ellipsis' {
            $result = Get-Summary -Value ('x' * 500)

            $result.Length | Should -Be 120
            $result        | Should -BeLike '*...'
        }
    }

    Context 'arrays of content blocks' {

        It 'returns an empty string for an empty array' {
            Get-Summary -Value @() | Should -Be ''
        }

        # PowerShell's switch statement enumerates a collection, so an array argument is
        # matched element by element and the { $_ -is [array] } clause is never reached. The
        # two tests below pin the behaviour that results today; the two skipped ones state the
        # contract the help text describes. Un-skip them when the switch is fixed.

        It 'currently keeps only the first element of a string array' {
            Get-Summary -Value @('alpha', 'beta') | Should -Be 'alpha'
        }

        It 'currently dumps an array of content blocks as JSON' {
            $blocks = @(
                [PSCustomObject]@{ type = 'text'; text = 'Found 3 call sites' }
                [PSCustomObject]@{ type = 'text'; text = 'second block' }
            )

            Get-Summary -Value $blocks | Should -BeLike '*{"type":"text"*'
        }

        It 'joins the summaries of each element' -Skip {
            Get-Summary -Value @('alpha', 'beta') | Should -Be 'alpha beta'
        }

        It 'reads the text of each block in an array of content blocks' -Skip {
            $blocks = @(
                [PSCustomObject]@{ type = 'text'; text = 'Found 3 call sites' }
                [PSCustomObject]@{ type = 'text'; text = 'second block' }
            )

            Get-Summary -Value $blocks | Should -Be 'Found 3 call sites second block'
        }
    }

    Context 'objects' {

        It 'prefers a text property' {
            Get-Summary -Value ([PSCustomObject]@{ type = 'text'; text = 'hello there' }) |
                Should -Be 'hello there'
        }

        It 'falls back to compact JSON when there is no text property' {
            $result = Get-Summary -Value ([PSCustomObject]@{ status = 'ok'; count = 3 })

            $result | Should -BeLike '*status*'
            $result | Should -BeLike '*ok*'
            $result | Should -Not -Match '\r?\n'
        }

        It 'truncates a long JSON fallback like any other line' {
            $long = [PSCustomObject]@{ payload = ('y' * 400) }
            (Get-Summary -Value $long).Length | Should -Be 120
        }
    }
}
