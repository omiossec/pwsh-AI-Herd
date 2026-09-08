function Get-AgentPaneCommand {
    <#
    .SYNOPSIS
        Builds the program + arguments wezterm runs inside one agent pane.

    .DESCRIPTION
        The single seam where engine choice lives. Every pane runs the current pwsh executable
        with -NoExit so the pane survives the agent exiting (the equivalent of the '; exec zsh'
        tail in the tmux version), and the shell resolves the agent executable (npm .cmd shims
        included) instead of wezterm.

        The launched script tags the pane before starting the agent: HERD_* environment
        variables for hooks, the pane title, and two wezterm user vars (herd_task,
        herd_session_id) that a wezterm.lua status bar can read with pane:get_user_vars().

        Claude: the session id is pinned up front (--session-id) so the grid can be reopened
        exactly; when a transcript for that id already exists the pane resumes it instead.
        Codex: no pre-pin exists, so a reopen continues the most recent session in the
        directory (codex resume --last). Effort rides on the command line.
        Copilot: started bare; a reopen uses --resume.

    .PARAMETER Resume
        The grid is being reopened: resume conversations instead of starting new ones.

    .OUTPUTS
        string[] to pass to wezterm after '--'.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Claude', 'Codex', 'Copilot')]
        [string]$Agent,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionId,

        [Parameter()]
        [ValidateSet('default', 'medium', 'low')]
        [string]$Effort = 'default',

        [Parameter()]
        [string]$Task,

        [Parameter()]
        [string]$Kickoff,

        [Parameter()]
        [ValidateRange(0, 63)]
        [int]$Index = 0,

        [Parameter()]
        [switch]$Resume
    )

    # Everything below goes into a single-quoted PowerShell literal: double the quotes.
    function Get-Literal([string]$Value) { "'" + $Value.Replace("'", "''") + "'" }
    function Get-Base64([string]$Value) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value)) }

    $label = if ($Task) { $Task } else { "$($Agent.ToLowerInvariant()) #$Index" }

    $line = [System.Collections.Generic.List[string]]::new()
    $line.Add("`$env:HERD_SESSION_ID = $(Get-Literal $SessionId)")
    $line.Add("`$env:HERD_AGENT = $(Get-Literal $Agent.ToLowerInvariant())")
    $line.Add("`$env:HERD_TASK = $(Get-Literal $label)")
    if ($Agent -eq 'Claude' -and $Effort -ne 'default') {
        $line.Add("`$env:CLAUDE_CODE_EFFORT_LEVEL = $(Get-Literal $Effort)")
    }
    $line.Add("`$Host.UI.RawUI.WindowTitle = $(Get-Literal $label)")
    # OSC 1337 SetUserVar: value is base64, ESC ] ... BEL.
    $line.Add("[Console]::Write([char]27 + ']1337;SetUserVar=herd_task=' + $(Get-Literal (Get-Base64 $label)) + [char]7)")
    $line.Add("[Console]::Write([char]27 + ']1337;SetUserVar=herd_session_id=' + $(Get-Literal (Get-Base64 $SessionId)) + [char]7)")

    $kick = if ($Kickoff) { ' ' + (Get-Literal $Kickoff) } else { '' }

    switch ($Agent) {
        'Claude' {
            $transcript = Join-Path -Path $HOME -ChildPath ".claude/projects/*/$SessionId.jsonl"
            if ($Resume -and (Test-Path -Path $transcript)) {
                $line.Add("& claude --resume $SessionId")
            }
            else {
                $line.Add("& claude --session-id $SessionId$kick")
            }
        }
        'Codex' {
            $codexEffort = switch ($Effort) { 'low' { 'low' } 'medium' { 'medium' } default { 'high' } }
            # A bare TOML value that fails to parse is taken as a string by codex, so no quotes.
            $flag = "-c model_reasoning_effort=$codexEffort"
            if ($Resume) { $line.Add("& codex resume --last $flag") }
            else         { $line.Add("& codex $flag$kick") }
        }
        'Copilot' {
            if ($Resume)      { $line.Add('& copilot --resume') }
            elseif ($Kickoff) { $line.Add("& copilot -i $(Get-Literal $Kickoff)") }
            else              { $line.Add('& copilot') }
        }
    }

    $pwsh = [Environment]::ProcessPath
    if (-not $pwsh) { $pwsh = 'pwsh' }

    return [string[]]@($pwsh, '-NoLogo', '-NoExit', '-Command', ($line -join '; '))
}
