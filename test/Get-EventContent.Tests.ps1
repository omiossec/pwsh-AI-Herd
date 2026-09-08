BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    function Get-Content1 {
        param($AgentEvent)
        InModuleScope pwsh-ai-herd -Parameters @{ e = $AgentEvent } {
            param($e)
            Get-EventContent -AgentEvent $e
        }
    }
}

Describe 'Get-EventContent' {

    Context 'events that carry no content' {

        It 'returns nothing when there is no message property' {
            @(Get-Content1 -AgentEvent ([PSCustomObject]@{ type = 'assistant' })).Count | Should -Be 0
        }

        It 'returns nothing when the message is null' {
            @(Get-Content1 -AgentEvent ([PSCustomObject]@{ type = 'assistant'; message = $null })).Count |
                Should -Be 0
        }

        It 'returns nothing when the message has no content property' {
            $agentEvent = [PSCustomObject]@{ type = 'assistant'; message = [PSCustomObject]@{ role = 'assistant' } }

            @(Get-Content1 -AgentEvent $agentEvent).Count | Should -Be 0
        }

        It 'returns nothing for an empty content array' {
            $agentEvent = [PSCustomObject]@{ message = [PSCustomObject]@{ content = @() } }

            @(Get-Content1 -AgentEvent $agentEvent).Count | Should -Be 0
        }
    }

    Context 'well-formed content' {

        BeforeAll {
            $script:agentEvent = [PSCustomObject]@{
                type    = 'assistant'
                message = [PSCustomObject]@{
                    content = @(
                        [PSCustomObject]@{ type = 'text';     text = 'hello' }
                        [PSCustomObject]@{ type = 'tool_use'; name = 'Read' }
                    )
                }
            }
        }

        It 'returns every block' {
            @(Get-Content1 -AgentEvent $script:agentEvent).Count | Should -Be 2
        }

        It 'preserves the block order' {
            $blocks = @(Get-Content1 -AgentEvent $script:agentEvent)

            $blocks[0].type | Should -Be 'text'
            $blocks[1].type | Should -Be 'tool_use'
        }

        It 'preserves the block payload' {
            (@(Get-Content1 -AgentEvent $script:agentEvent))[0].text | Should -Be 'hello'
        }
    }

    Context 'defensive filtering' {

        It 'drops blocks that carry no type, since the caller switches on it' {
            $agentEvent = [PSCustomObject]@{
                message = [PSCustomObject]@{
                    content = @(
                        [PSCustomObject]@{ type = 'text'; text = 'kept' }
                        [PSCustomObject]@{ note = 'no type property' }
                    )
                }
            }

            $blocks = @(Get-Content1 -AgentEvent $agentEvent)

            $blocks.Count   | Should -Be 1
            $blocks[0].text | Should -Be 'kept'
        }

        It 'drops bare strings in the content array' {
            $agentEvent = [PSCustomObject]@{
                message = [PSCustomObject]@{ content = @('a plain string') }
            }

            @(Get-Content1 -AgentEvent $agentEvent).Count | Should -Be 0
        }

        It 'survives a content property that is a single object rather than an array' {
            $agentEvent = [PSCustomObject]@{
                message = [PSCustomObject]@{ content = [PSCustomObject]@{ type = 'text'; text = 'solo' } }
            }

            $blocks = @(Get-Content1 -AgentEvent $agentEvent)

            $blocks.Count   | Should -Be 1
            $blocks[0].text | Should -Be 'solo'
        }
    }
}
