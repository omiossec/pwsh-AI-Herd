function Invoke-WezTermCli {
    <#
    .SYNOPSIS
        Runs `wezterm cli <arguments>` and returns its standard output.

    .DESCRIPTION
        The wezterm CLI talks to the multiplexer inside the running GUI. Any failure (no GUI
        running, unknown pane id, ...) is turned into a terminating error carrying wezterm's
        stderr, so callers do not have to inspect $LASTEXITCODE.

    .PARAMETER Arguments
        Arguments after `wezterm cli`, one element each. Pass the program to run in a pane
        after a literal '--'.

    .PARAMETER Quiet
        Return $null instead of throwing when wezterm fails. Used to probe whether a mux
        server is reachable at all.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Arguments,

        [Parameter()]
        [switch]$Quiet
    )

    $wezterm = Get-WezTermPath

    # The CLI cannot find a GUI's socket on its own from a non-WezTerm console (see
    # Get-WezTermSocket), so point it there for the duration of the call.
    $previousSocket = $env:WEZTERM_UNIX_SOCKET
    $socket = Get-WezTermSocket
    if ($socket) { $env:WEZTERM_UNIX_SOCKET = $socket }
    try {
        # --no-auto-start: without it, `wezterm cli` silently starts a headless
        # wezterm-mux-server when no GUI is running, and every pane we then spawn lands in that
        # invisible server. Failing instead lets New-HerdGrid open a real window.
        $output   = & $wezterm cli --no-auto-start @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $env:WEZTERM_UNIX_SOCKET = $previousSocket
    }

    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join [Environment]::NewLine
    $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine

    if ($exitCode -ne 0) {
        if ($Quiet) {
            return $null
        }
        throw "wezterm cli $($Arguments[0]) failed (exit $exitCode): $stderr"
    }

    return $stdout.Trim()
}
