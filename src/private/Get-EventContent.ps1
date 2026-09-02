function Get-EventContent {
    <#
    .SYNOPSIS
        Returns the content blocks of a stream-json message event, or nothing.

    .DESCRIPTION
        Guards the $agentEvent.message.content walk: Set-StrictMode -Version Latest makes a missing
        property a terminating error, and an agent is free to emit a message event shaped
        differently from the one documented.

    .PARAMETER AgentEvent
        The deserialised stream-json event.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [psobject]$AgentEvent
    )

    if (-not $AgentEvent.PSObject.Properties['message']) { return @() }
    $message = $AgentEvent.message
    if ($null -eq $message -or -not $message.PSObject.Properties['content']) { return @() }

    return @($message.content | Where-Object { $_ -is [psobject] -and $_.PSObject.Properties['type'] })
}
