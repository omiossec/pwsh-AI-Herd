function Split-CommandLine {
    <#
    .SYNOPSIS
        Splits a command line into executable + argument string.

    .DESCRIPTION
        Deliberately simple: a leading "..." delimits a quoted executable path, otherwise the
        first space separates the executable from its arguments. This is not full shell
        tokenization; the argument string is handed to ProcessStartInfo.Arguments as-is.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CommandLine
    )

    $trimmed = $CommandLine.Trim()

    if ($trimmed.StartsWith('"')) {
        $closing = $trimmed.IndexOf('"', 1)
        if ($closing -lt 0) {
            throw "Unbalanced quote in command line: $CommandLine"
        }
        $fileName  = $trimmed.Substring(1, $closing - 1)
        $arguments = $trimmed.Substring([Math]::Min($closing + 1, $trimmed.Length)).TrimStart()
    }
    else {
        $space = $trimmed.IndexOf(' ')
        if ($space -lt 0) {
            $fileName  = $trimmed
            $arguments = ''
        }
        else {
            $fileName  = $trimmed.Substring(0, $space)
            $arguments = $trimmed.Substring($space + 1)
        }
    }

    [PSCustomObject]@{
        FileName  = $fileName
        Arguments = $arguments
    }
}
