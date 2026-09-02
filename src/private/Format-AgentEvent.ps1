function Format-AgentEvent {
    <#
    .SYNOPSIS
        Turns one stream-json event line into the display lines shown in a frame.

    .DESCRIPTION
        Agents started with --output-format stream-json emit one JSON object per line
        (assistant messages, tool calls, the final result, bookkeeping events). Raw JSON is
        unreadable in a narrow frame, so each event is reduced to plain text lines; noise
        events (rate limits, partial message chunks) return nothing.

        Anything that is not valid JSON, or carries no 'type', is passed through unchanged:
        an agent can still write plain text to stderr.

        Emits nothing for an event with no display value, so callers must treat the result as
        a possibly-empty collection (@(...)), not as a guaranteed array.

    .PARAMETER Line
        One line drained from the process output queue.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Line
    )

    # stderr lines keep the '! ' prefix added in FrameProcess and are never JSON.
    if (-not $Line.TrimStart().StartsWith('{')) {
        return [string[]]@($Line)
    }

    try {
        $agentEvent = $Line | ConvertFrom-Json
    }
    catch {
        return [string[]]@($Line)
    }

    if ($null -eq $agentEvent -or -not $agentEvent.PSObject.Properties['type']) {
        return [string[]]@($Line)
    }

    $out = [System.Collections.Generic.List[string]]::new()

    switch ($agentEvent.type) {
        'system' {
            if ($agentEvent.PSObject.Properties['subtype'] -and $agentEvent.subtype -eq 'init') {
                $model = if ($agentEvent.PSObject.Properties['model']) { $agentEvent.model } else { 'unknown model' }
                $out.Add("-- session started | $model --")
            }
        }

        'assistant' {
            foreach ($block in @(Get-EventContent -AgentEvent $agentEvent)) {
                switch ($block.type) {
                    'text'     { $out.AddRange([string[]]($block.text -split "\r?\n")) }
                    'thinking' { $out.Add('[thinking]') }
                    'tool_use' { $out.Add("[tool] $($block.name)") }
                }
            }
        }

        'user' {
            foreach ($block in @(Get-EventContent -AgentEvent $agentEvent)) {
                if ($block.type -eq 'tool_result') {
                    $out.Add("[tool result] $(Get-EventSummary -Value $block.content)")
                }
            }
        }

        'result' {
            $isError = $agentEvent.PSObject.Properties['is_error'] -and $agentEvent.is_error
            $prefix  = if ($isError) { '! ' } else { '' }
            $ms      = if ($agentEvent.PSObject.Properties['duration_ms']) { "$($agentEvent.duration_ms) ms" } else { 'done' }
            $out.Add("$prefix-- turn complete ($ms) --")
        }

        # rate_limit_event, stream_event, control_* and anything else: not worth a line.
        default { }
    }

    return $out.ToArray()
}
