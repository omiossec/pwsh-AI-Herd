function Get-WezTermSocket {
    <#
    .SYNOPSIS
        Finds the multiplexer socket of a running WezTerm GUI.

    .DESCRIPTION
        Inside a WezTerm pane, $env:WEZTERM_UNIX_SOCKET already points at it. From any other
        console the CLI has to be told, because the 20240203 Windows build resolves the GUI's
        'gui-sock-<pid>' name relative to the current directory and fails to connect.

        The runtime directory holds one 'gui-sock-<pid>' per GUI instance (stale ones linger
        after a crash, so the pid is checked against live processes) and 'sock' for a headless
        wezterm-mux-server, which is only used when such a server actually runs.

    .OUTPUTS
        Full socket path, or $null when no reachable WezTerm is running.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:WEZTERM_UNIX_SOCKET) {
        return $env:WEZTERM_UNIX_SOCKET
    }

    $runtime = @()
    if ($env:XDG_RUNTIME_DIR) {
        $runtime += Join-Path -Path $env:XDG_RUNTIME_DIR -ChildPath 'wezterm'
    }
    $runtime += Join-Path -Path $HOME -ChildPath '.local/share/wezterm'

    # Two flat arrays: under strict mode, .Id on an empty collection is an error.
    $live     = @(Get-Process -Name 'wezterm-gui', 'wezterm-mux-server' -ErrorAction SilentlyContinue)
    $liveId   = @($live | ForEach-Object { $_.Id })
    $liveName = @($live | ForEach-Object { $_.ProcessName })

    foreach ($dir in $runtime) {
        if (-not (Test-Path -Path $dir -PathType Container)) { continue }

        $guiSocket = Get-ChildItem -Path $dir -Filter 'gui-sock-*' -Force -ErrorAction SilentlyContinue |
            Where-Object { [int]($_.Name -replace '^gui-sock-', '') -in $liveId } |
            Sort-Object -Property LastWriteTime -Descending |
            Select-Object -First 1
        if ($guiSocket) {
            return $guiSocket.FullName
        }

        $muxSocket = Join-Path -Path $dir -ChildPath 'sock'
        if ((Test-Path -Path $muxSocket) -and ($liveName -contains 'wezterm-mux-server')) {
            return $muxSocket
        }
    }

    return $null
}
