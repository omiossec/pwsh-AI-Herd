BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    $script:SessionId = '11111111-2222-3333-4444-555555555555'

    function Get-PaneCommand {
        param([hashtable]$Splat = @{})

        if (-not $Splat.ContainsKey('SessionId')) { $Splat['SessionId'] = $script:SessionId }

        InModuleScope pwsh-ai-herd -Parameters @{ splat = $Splat } {
            param($splat)
            , @(Get-AgentPaneCommand @splat)
        }
    }

    # The launch script is the last element; everything before it is pwsh's own switches.
    function Get-PaneScript {
        param([hashtable]$Splat = @{})
        (Get-PaneCommand -Splat $Splat)[-1]
    }
}

Describe 'Get-AgentPaneCommand' {

    Context 'the pwsh wrapper' {

        BeforeAll {
            $script:command = Get-PaneCommand -Splat @{ Agent = 'Claude' }
        }

        It 'runs a PowerShell executable' {
            $script:command[0] | Should -Match 'pwsh'
        }

        It 'keeps the pane alive after the agent exits' {
            # The counterpart of the '; exec zsh' tail in the tmux original.
            $script:command | Should -Contain '-NoExit'
        }

        It 'passes the launch script through -Command' {
            $script:command[-2] | Should -Be '-Command'
        }

        It 'produces exactly one launch script' {
            $script:command.Count | Should -Be 5
        }
    }

    Context 'the generated launch script' {

        It 'is syntactically valid PowerShell for every agent' -TestCases @(
            @{ Agent = 'Claude' }
            @{ Agent = 'Codex' }
            @{ Agent = 'Copilot' }
        ) {
            $script = Get-PaneScript -Splat @{ Agent = $Agent; Task = "it's a plan"; Kickoff = "don't stop" }

            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$null, [ref]$errors)

            $errors | Should -BeNullOrEmpty
        }

        It 'stays valid PowerShell when the task contains quotes and braces' {
            $script = Get-PaneScript -Splat @{ Agent = 'Claude'; Task = 'a ''quoted'' $var {brace} "dq"' }

            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$null, [ref]$errors)

            $errors | Should -BeNullOrEmpty
        }

        It 'never uses a double quote, which would not survive the argument round trip' {
            Get-PaneScript -Splat @{ Agent = 'Claude'; Task = 'plain' } | Should -Not -Match '"'
        }

        It 'exports the session id for hooks running inside the pane' {
            Get-PaneScript -Splat @{ Agent = 'Claude' } | Should -Match "HERD_SESSION_ID = '$script:SessionId'"
        }

        It 'exports the agent name in lower case' {
            Get-PaneScript -Splat @{ Agent = 'Codex' } | Should -Match "HERD_AGENT = 'codex'"
        }

        It 'exports the task label' {
            Get-PaneScript -Splat @{ Agent = 'Claude'; Task = 'reviewer' } | Should -Match "HERD_TASK = 'reviewer'"
        }

        It 'falls back to agent and index when no task is given' {
            Get-PaneScript -Splat @{ Agent = 'Claude'; Index = 3 } | Should -Match "HERD_TASK = 'claude #3'"
        }

        It 'sets the pane title' {
            Get-PaneScript -Splat @{ Agent = 'Claude'; Task = 'builder' } | Should -Match 'WindowTitle'
        }

        It 'publishes the task as a base64 wezterm user var' {
            $expected = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('builder'))

            Get-PaneScript -Splat @{ Agent = 'Claude'; Task = 'builder' } |
                Should -Match "SetUserVar=herd_task=' \+ '$([regex]::Escape($expected))'"
        }

        It 'publishes the session id as a wezterm user var' {
            Get-PaneScript -Splat @{ Agent = 'Claude' } | Should -Match 'SetUserVar=herd_session_id='
        }
    }

    Context 'Claude' {

        BeforeAll {
            Mock -ModuleName pwsh-ai-herd Test-Path { $false } -ParameterFilter { $Path -like '*.claude*' }
        }

        It 'pins the session id on a fresh launch' {
            Get-PaneScript -Splat @{ Agent = 'Claude' } | Should -Match "claude --session-id $script:SessionId"
        }

        It 'appends the kickoff prompt as a quoted argument' {
            Get-PaneScript -Splat @{ Agent = 'Claude'; Kickoff = 'Read the readme' } |
                Should -Match "--session-id $script:SessionId 'Read the readme'"
        }

        It 'resumes by id when a transcript exists' {
            Mock -ModuleName pwsh-ai-herd Test-Path { $true } -ParameterFilter { $Path -like '*.claude*' }

            Get-PaneScript -Splat @{ Agent = 'Claude'; Resume = $true } |
                Should -Match "claude --resume $script:SessionId"
        }

        It 'starts a new session when resuming without a transcript' {
            Get-PaneScript -Splat @{ Agent = 'Claude'; Resume = $true } |
                Should -Match "claude --session-id $script:SessionId"
        }

        It 'sets the effort environment variable when the level is not the default' {
            Get-PaneScript -Splat @{ Agent = 'Claude'; Effort = 'low' } |
                Should -Match "CLAUDE_CODE_EFFORT_LEVEL = 'low'"
        }

        It 'leaves the effort variable unset at the default level' {
            Get-PaneScript -Splat @{ Agent = 'Claude'; Effort = 'default' } |
                Should -Not -Match 'CLAUDE_CODE_EFFORT_LEVEL'
        }
    }

    Context 'Codex' {

        It 'maps the <Effort> level to reasoning effort <Expected>' -TestCases @(
            @{ Effort = 'low';     Expected = 'low' }
            @{ Effort = 'medium';  Expected = 'medium' }
            @{ Effort = 'default'; Expected = 'high' }
        ) {
            Get-PaneScript -Splat @{ Agent = 'Codex'; Effort = $Effort } |
                Should -Match "model_reasoning_effort=$Expected"
        }

        It 'never sets the Claude effort variable' {
            Get-PaneScript -Splat @{ Agent = 'Codex'; Effort = 'low' } |
                Should -Not -Match 'CLAUDE_CODE_EFFORT_LEVEL'
        }

        It 'continues the most recent session when resuming' {
            # Codex has no equivalent of --session-id, so the pinned id cannot be used here.
            Get-PaneScript -Splat @{ Agent = 'Codex'; Resume = $true } | Should -Match 'codex resume --last'
        }

        It 'starts a plain session otherwise' {
            $script = Get-PaneScript -Splat @{ Agent = 'Codex' }

            $script | Should -Match '& codex '
            $script | Should -Not -Match 'resume'
        }
    }

    Context 'Copilot' {

        It 'starts bare' {
            Get-PaneScript -Splat @{ Agent = 'Copilot' } | Should -Match '& copilot$'
        }

        It 'resumes with the resume switch' {
            Get-PaneScript -Splat @{ Agent = 'Copilot'; Resume = $true } | Should -Match '& copilot --resume'
        }

        It 'passes a kickoff prompt with the interactive switch' {
            Get-PaneScript -Splat @{ Agent = 'Copilot'; Kickoff = 'hello' } | Should -Match "& copilot -i 'hello'"
        }
    }

    Context 'input validation' {

        It 'rejects an unknown agent' {
            { Get-PaneCommand -Splat @{ Agent = 'Gemini' } } | Should -Throw
        }

        It 'rejects an unknown effort level' {
            { Get-PaneCommand -Splat @{ Agent = 'Claude'; Effort = 'extreme' } } | Should -Throw
        }

        It 'requires a session id' {
            { InModuleScope pwsh-ai-herd { Get-AgentPaneCommand -Agent 'Claude' } } | Should -Throw
        }
    }
}
