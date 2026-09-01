function Get-EventSummary {
    <#
    .SYNOPSIS
        Reduces an arbitrary stream-json payload to a single short line.

    .DESCRIPTION
        Tool results are strings, arrays of content blocks, or objects. Frames are narrow and
        the list view does not wrap, so only the first line is kept, truncated.

    .PARAMETER Value
        The payload to summarise. $null yields an empty string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return ''
    }

    $text = switch ($Value) {
        { $_ -is [string] } { $_; break }
        { $_ -is [array] }  { (@($_ | ForEach-Object { Get-EventSummary -Value $_ }) -join ' ');  break }
        default {
            if ($Value.PSObject.Properties['text']) { $Value.text } else { $Value | ConvertTo-Json -Depth 3 -Compress }
        }
    }

    $text = ($text -split "\r?\n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if ($null -eq $text) {
        return ''
    }
    if ($text.Length -gt 120) {
        return $text.Substring(0, 117) + '...'
    }
    return $text
}
