function Update-Frame {
    <#
    .SYNOPSIS
        Timer tick: drains every frame's output queue into its view, flags exited processes.

    .NOTES
        Must return $true, otherwise Terminal.Gui removes the timeout and the UI stops refreshing.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    foreach ($frame in @($script:Frames)) {
        $changed = $false
        $line    = $null

        while ($frame.Process.Output.TryDequeue([ref]$line)) {
            if ($frame.Protocol -eq 'StreamJson') {
                # Bookkeeping events render to nothing, and PowerShell unrolls that empty
                # array to $null on the way out: @() first, then only add when there is something.
                $rendered = @(Format-AgentEvent -Line $line)
                if ($rendered.Count -gt 0) {
                    $frame.Lines.AddRange([string[]]$rendered)
                }
            }
            else {
                $frame.Lines.Add($line)
            }
            $changed = $true
        }

        if ($frame.Lines.Count -gt $script:MaxLine) {
            $frame.Lines.RemoveRange(0, $frame.Lines.Count - $script:MaxLine)
        }

        if ($frame.Process.HasExited -and -not $frame.ExitNoted) {
            $frame.ExitNoted  = $true
            $frame.View.Title = "PID $($frame.Process.Id) | exited ($($frame.Process.ExitCode)) | $($frame.CommandLine)"
            $frame.Lines.Add("-- process exited with code $($frame.Process.ExitCode) --")
            $changed = $true
        }

        if ($changed) {
            Update-FrameView -Frame $frame
        }
    }

    return $true    # keep the timeout alive
}
