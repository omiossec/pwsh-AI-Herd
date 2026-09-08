BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    function Format-Line {
        param([string]$Line)
        InModuleScope pwsh-ai-herd -Parameters @{ text = $Line } {
            param($text)
            @(Format-AgentEvent -Line $text)
        }
    }

    function Format-Event {
        param($AgentEvent)
        Format-Line -Line ($AgentEvent | ConvertTo-Json -Depth 10 -Compress)
    }
}

Describe 'Format-AgentEvent' {

    Context 'lines that are not agent events' {

        It 'passes a plain text line through unchanged' {
            Format-Line -Line 'just some output' | Should -Be @('just some output')
        }

        It 'passes a stderr line through with its marker intact' {
            Format-Line -Line '! warning: no tests found' | Should -Be @('! warning: no tests found')
        }

        It 'passes malformed JSON through rather than losing it' {
            Format-Line -Line '{ this is not json' | Should -Be @('{ this is not json')
        }

        It 'passes a JSON object with no type through' {
            Format-Line -Line '{"foo":"bar"}' | Should -Be @('{"foo":"bar"}')
        }

        It 'does not try to parse a line that merely contains a brace' {
            Format-Line -Line 'result was {"ok":true}' | Should -Be @('result was {"ok":true}')
        }
    }

    Context 'session start' {

        It 'announces the session with its model' {
            Format-Event @{ type = 'system'; subtype = 'init'; model = 'claude-opus-5' } |
                Should -Be @('-- session started | claude-opus-5 --')
        }

        It 'falls back to a placeholder when no model is reported' {
            Format-Event @{ type = 'system'; subtype = 'init' } |
                Should -Be @('-- session started | unknown model --')
        }

        It 'ignores system events that are not the init event' {
            @(Format-Event @{ type = 'system'; subtype = 'compact_boundary' }).Count | Should -Be 0
        }
    }

    Context 'assistant messages' {

        It 'renders a text block' {
            $agentEvent = @{ type = 'assistant'; message = @{ content = @(@{ type = 'text'; text = 'Hello' }) } }

            Format-Event $agentEvent | Should -Be @('Hello')
        }

        It 'splits a multi-line text block into one display line each' {
            $agentEvent = @{ type = 'assistant'; message = @{ content = @(@{ type = 'text'; text = "line one`nline two" }) } }

            Format-Event $agentEvent | Should -Be @('line one', 'line two')
        }

        It 'collapses a thinking block to a marker' {
            $agentEvent = @{ type = 'assistant'; message = @{ content = @(@{ type = 'thinking'; thinking = 'secret' }) } }

            Format-Event $agentEvent | Should -Be @('[thinking]')
        }

        It 'never leaks the thinking text into the frame' {
            $agentEvent = @{ type = 'assistant'; message = @{ content = @(@{ type = 'thinking'; thinking = 'secret' }) } }

            Format-Event $agentEvent | Should -Not -Contain 'secret'
        }

        It 'names the tool of a tool_use block' {
            $agentEvent = @{ type = 'assistant'; message = @{ content = @(@{ type = 'tool_use'; name = 'Read' }) } }

            Format-Event $agentEvent | Should -Be @('[tool] Read')
        }

        It 'renders several blocks in order' {
            $agentEvent = @{
                type    = 'assistant'
                message = @{ content = @(
                    @{ type = 'text';     text = 'Looking' }
                    @{ type = 'tool_use'; name = 'Grep' }
                ) }
            }

            Format-Event $agentEvent | Should -Be @('Looking', '[tool] Grep')
        }

        It 'ignores an assistant event with no content' {
            @(Format-Event @{ type = 'assistant' }).Count | Should -Be 0
        }
    }

    Context 'tool results' {

        It 'summarises a string tool result' {
            $agentEvent = @{
                type    = 'user'
                message = @{ content = @(@{ type = 'tool_result'; content = 'Found 3 call sites' }) }
            }

            Format-Event $agentEvent | Should -Be @('[tool result] Found 3 call sites')
        }

        It 'ignores user blocks that are not tool results' {
            $agentEvent = @{ type = 'user'; message = @{ content = @(@{ type = 'text'; text = 'echoed' }) } }

            @(Format-Event $agentEvent).Count | Should -Be 0
        }
    }

    Context 'turn results' {

        It 'reports the duration of a successful turn' {
            Format-Event @{ type = 'result'; duration_ms = 1488 } |
                Should -Be @('-- turn complete (1488 ms) --')
        }

        It 'says done when no duration is reported' {
            Format-Event @{ type = 'result' } | Should -Be @('-- turn complete (done) --')
        }

        It 'marks a failed turn with the stderr prefix' {
            Format-Event @{ type = 'result'; is_error = $true; duration_ms = 12 } |
                Should -Be @('! -- turn complete (12 ms) --')
        }

        It 'does not mark a turn that reports is_error false' {
            Format-Event @{ type = 'result'; is_error = $false; duration_ms = 12 } |
                Should -Be @('-- turn complete (12 ms) --')
        }
    }

    Context 'bookkeeping events' {

        It 'renders nothing for <Type>' -TestCases @(
            @{ Type = 'rate_limit_event' }
            @{ Type = 'stream_event' }
            @{ Type = 'control_request' }
            @{ Type = 'control_response' }
            @{ Type = 'something_new' }
        ) {
            @(Format-Event @{ type = $Type }).Count | Should -Be 0
        }

        It 'returns a collection the caller can safely count' {
            # Update-Frame wraps the call in @() and relies on Count being available.
            $result = Format-Line -Line '{"type":"stream_event"}'

            { $result.Count } | Should -Not -Throw
        }
    }

    Context 'input validation' {

        It 'rejects an empty line' {
            { Format-Line -Line '' } | Should -Throw
        }
    }
}
