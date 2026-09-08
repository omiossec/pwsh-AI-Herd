<#
    Start-AiHerd takes over the console with Terminal.Gui and only returns when the user quits,
    so it cannot be run here. What is testable is its contract: the parameters it accepts, the
    agent command lines it bakes in, and the cleanup it promises.
#>
BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    $script:Command = Get-Command -Name 'Start-AiHerd'
    $script:Source  = Get-Content -Path (Join-Path $PSScriptRoot '../src/public/Start-AiHerd.ps1') -Raw
}

Describe 'Start-AiHerd' {

    Context 'the command' {

        It 'is exported by the module' {
            $script:Command | Should -Not -BeNullOrEmpty
        }

        It 'comes from pwsh-ai-herd' {
            $script:Command.ModuleName | Should -Be 'pwsh-ai-herd'
        }

        It 'is an advanced function' {
            $script:Command.CmdletBinding | Should -BeTrue
        }
    }

    Context 'how many sessions' {

        It 'accepts a session count' {
            $script:Command.Parameters.ContainsKey('NumberOfSession') | Should -BeTrue
        }

        It 'starts with an empty window by default' {
            $script:Command.Parameters['NumberOfSession'].Attributes.Where{
                $_ -is [System.Management.Automation.ParameterAttribute]
            } | Should -Not -BeNullOrEmpty

            $script:Source | Should -Match '\$NumberOfSession = 0'
        }

        It 'allows nothing above the six frames the layout supports' {
            $range = $script:Command.Parameters['NumberOfSession'].Attributes.Where{
                $_ -is [System.Management.Automation.ValidateRangeAttribute]
            }

            $range.MinRange | Should -Be 0
            $range.MaxRange | Should -Be 6
        }

        It 'rejects a seventh session' {
            { Start-AiHerd -NumberOfSession 7 } | Should -Throw
        }

        It 'rejects a negative count' {
            { Start-AiHerd -NumberOfSession -1 } | Should -Throw
        }
    }

    Context 'which agent' {

        It 'offers the three agents the module knows' {
            $set = $script:Command.Parameters['Agent'].Attributes.Where{
                $_ -is [System.Management.Automation.ValidateSetAttribute]
            }

            $set.ValidValues | Should -Be @('Claude', 'Copilot', 'Codex')
        }

        It 'rejects an unknown agent' {
            { Start-AiHerd -Agent Gemini } | Should -Throw
        }

        It 'defaults to Claude' {
            $script:Source | Should -Match "\`$Agent = 'Claude'"
        }
    }

    Context 'the agent command lines' {

        It 'starts Claude in print mode so it does not try to open a full-screen UI on a pipe' {
            $script:Source | Should -Match 'claude --print'
        }

        It 'keeps stdin open across turns with the streaming input format' {
            $script:Source | Should -Match '--input-format stream-json'
        }

        It 'asks for streaming output, which the frame renders event by event' {
            $script:Source | Should -Match '--output-format stream-json'
        }

        It 'passes verbose, which the streaming output format requires' {
            $script:Source | Should -Match '--verbose'
        }

        It 'still starts Copilot and Codex bare, since neither has a stdin protocol yet' {
            $script:Source | Should -Match "Copilot = 'copilot'"
            $script:Source | Should -Match "Codex   = 'codex'"
        }
    }

    Context 'the working directory' {

        It 'accepts one' {
            $script:Command.Parameters.ContainsKey('WorkingDirectory') | Should -BeTrue
        }

        It 'resolves the PowerShell location rather than inheriting the host process directory' {
            $script:Source | Should -Match 'ProviderPath'
            $script:Source | Should -Match 'Resolve-Path'
        }

        It 'shows the directory in the window title' {
            $script:Source | Should -Match 'AI Herd \|'
        }
    }

    Context 'cleanup' {

        It 'disposes every child process in a finally block, so no agent outlives the host' {
            $script:Source | Should -Match 'finally'
            $script:Source | Should -Match '\$frame\.Process\.Dispose\(\)'
        }

        It 'shuts Terminal.Gui down so the console is restored' {
            $script:Source | Should -Match 'Application\]::Shutdown\(\)'
        }
    }

    Context 'the refresh pump' {

        It 'is installed on the main loop, where PowerShell can run safely' {
            $script:Source | Should -Match 'MainLoop\.AddTimeout'
        }

        It 'ticks often enough to feel live' {
            $script:Source | Should -Match 'FromMilliseconds\(120\)'
        }
    }

    Context 'documentation' {

        It 'has comment-based help with a synopsis' {
            (Get-Help -Name 'Start-AiHerd').Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'documents every parameter' {
            $help = Get-Help -Name 'Start-AiHerd' -Detailed

            foreach ($name in @('NumberOfSession', 'Agent', 'WorkingDirectory')) {
                @($help.Parameters.Parameter | Where-Object { $_.Name -eq $name }).Count |
                    Should -Be 1 -Because "$name should be documented"
            }
        }

        It 'shows at least one example' {
            @((Get-Help -Name 'Start-AiHerd' -Examples).Examples.Example).Count |
                Should -BeGreaterThan 0
        }
    }
}
