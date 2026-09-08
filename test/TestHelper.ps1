<#
    Shared fixtures for the pwsh-ai-herd Pester suite.

    Dot-sourced from the BeforeAll of every test file that needs it. Two kinds of helper live
    here:

      * Fake frames. The frame-host functions (Update-Frame, Send-FrameInput, Close-Frame,
        Update-FrameView) only ever touch a handful of members on the frame object, so a
        PSCustomObject with the same shape exercises the real logic without Terminal.Gui and
        without starting a child process. The output queue is a real ConcurrentQueue, because
        that is what Update-Frame drains.

      * A fake wezterm. Invoke-WezTermCli shells out to the executable Get-WezTermPath
        returns; a generated .ps1 stands in for it. Running a .ps1 through the call operator
        sets $LASTEXITCODE from its `exit` and surfaces Write-Error as an ErrorRecord, which is
        exactly what the function classifies.
#>

function New-FakeProcess {
    <#
        Stand-in for FrameHost.FrameProcess. Sent records every SendLine, Disposed flips on
        Dispose, and Output is a real queue so the caller can enqueue lines the pump will find.
    #>
    [CmdletBinding()]
    param(
        [bool]$HasExited = $false,
        [int]$ExitCode = 0,
        [int]$Id = 4242
    )

    $process = [PSCustomObject]@{
        Output    = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        HasExited = $HasExited
        ExitCode  = $ExitCode
        Id        = $Id
        Sent      = [System.Collections.Generic.List[string]]::new()
        Disposed  = $false
    }
    $process | Add-Member -MemberType ScriptMethod -Name 'SendLine' -Value { param($Line) $this.Sent.Add($Line) }
    $process | Add-Member -MemberType ScriptMethod -Name 'Dispose'  -Value { $this.Disposed = $true }
    $process | Add-Member -MemberType ScriptMethod -Name 'Stop'     -Value { $this.HasExited = $true }
    return $process
}

function New-FakeListView {
    <# Stand-in for Terminal.Gui.ListView: records the last SetSource and the redraw count. #>
    [CmdletBinding()]
    param(
        [int]$Height = 10
    )

    $list = [PSCustomObject]@{
        Bounds       = [PSCustomObject]@{ Height = $Height }
        TopItem      = 0
        Source       = @()
        RedrawCount  = 0
    }
    $list | Add-Member -MemberType ScriptMethod -Name 'SetSource'       -Value { param($Items) $this.Source = $Items }
    $list | Add-Member -MemberType ScriptMethod -Name 'SetNeedsDisplay' -Value { $this.RedrawCount++ }
    return $list
}

function New-FakeFrame {
    <# A frame shaped like the one New-Frame builds, with fakes in place of the views. #>
    [CmdletBinding()]
    param(
        [ValidateSet('Text', 'StreamJson')]
        [string]$Protocol = 'Text',

        [string]$InputText = '',
        [bool]$HasExited = $false,
        [int]$ExitCode = 0,
        [int]$Id = 4242,
        [int]$ListHeight = 10
    )

    $inputField = [PSCustomObject]@{ Text = $InputText }

    return [PSCustomObject]@{
        Process     = New-FakeProcess -HasExited $HasExited -ExitCode $ExitCode -Id $Id
        View        = [PSCustomObject]@{ Title = "PID $Id | fake" }
        List        = New-FakeListView -Height $ListHeight
        Input       = $inputField
        Lines       = [System.Collections.Generic.List[string]]::new()
        CommandLine = 'fake --command'
        Protocol    = $Protocol
        Directory   = 'C:\fake'
        ExitNoted   = $false
    }
}

function New-FakeWezTerm {
    <#
        Writes a script that impersonates the wezterm executable and returns its path. It logs
        the arguments it was called with, then either writes a canned line to stdout or fails
        with the given exit code and a message on stderr.

            -Path      base path; the right extension for the platform is appended
            -Emit      the line written to stdout on success
            -FailWith  exit code to return instead
            -ErrorText what to write to stderr when failing

        This has to be a real external program, not a PowerShell script invoked in process. A
        .ps1 called through the call operator shares the caller's $ErrorActionPreference, so
        its Write-Error becomes a terminating error under 'Stop' and Invoke-WezTermCli never
        reaches its own exit-code handling. The real wezterm is an external process whose
        stderr is only ever text, and a .cmd or .sh behaves the same way.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Emit = 'ok',

        [int]$FailWith = 0,

        [string]$ErrorText = 'fake wezterm failure'
    )

    $directory = Split-Path -Path $Path -Parent
    $baseName  = [IO.Path]::GetFileNameWithoutExtension($Path)

    # Each fake logs to its own file: a shared log would be raced by the previous test's
    # process, which may still be exiting while this one starts.
    $stateFile = Join-Path -Path $directory -ChildPath "wezterm-calls-$(New-Guid).txt"

    if ($IsWindows) {
        $scriptPath = Join-Path -Path $directory -ChildPath "$baseName.cmd"
        $body = @"
@echo off
echo %*>>"$stateFile"
if not "$FailWith"=="0" (
    echo $ErrorText 1>&2
    exit /b $FailWith
)
echo $Emit
exit /b 0
"@
        Set-Content -Path $scriptPath -Value $body -Encoding ascii
    }
    else {
        $scriptPath = Join-Path -Path $directory -ChildPath "$baseName.sh"
        $body = @"
#!/bin/sh
echo "`$@" >> '$stateFile'
if [ $FailWith -ne 0 ]; then
    echo '$ErrorText' >&2
    exit $FailWith
fi
echo '$Emit'
exit 0
"@
        Set-Content -Path $scriptPath -Value $body -Encoding utf8
        & chmod +x $scriptPath
    }

    if (-not $script:FakeWezTermLog) { $script:FakeWezTermLog = @{} }
    $script:FakeWezTermLog[$scriptPath] = $stateFile

    return $scriptPath
}

function Get-FakeWezTermCall {
    <# The argument lines a fake wezterm recorded, oldest first. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    $stateFile = $script:FakeWezTermLog[$ScriptPath]
    if (-not $stateFile -or -not (Test-Path -Path $stateFile)) { return , @() }

    # The leading comma stops PowerShell unrolling a one-line log into a bare string, which
    # would make the caller's [0] index a character instead of a call.
    return , @(Get-Content -Path $stateFile)
}

function New-TestGridRecord {
    <# A grid record shaped like the one Save-HerdGrid writes. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [int]$PaneCount = 2,
        [int]$Columns = 2,
        [int]$Rows = 1,
        [string]$Agent = 'Claude',
        [string]$Worktree,
        [string]$Branch
    )

    $panes = for ($i = 0; $i -lt $PaneCount; $i++) {
        [PSCustomObject]@{
            Index     = $i
            SessionId = [guid]::NewGuid().ToString()
            Agent     = $Agent
            Effort    = 'default'
            Task      = $null
            Kickoff   = $null
            Worktree  = if ($Worktree) { Join-Path -Path $Worktree -ChildPath ($i + 1) } else { $null }
            Branch    = if ($Branch) { "$Branch-$($i + 1)" } else { $null }
            PaneId    = $i
        }
    }

    return [PSCustomObject]@{
        Version   = 1
        Directory = $Directory
        Columns   = $Columns
        Rows      = $Rows
        Saved     = [DateTimeOffset]::Now.ToString('o')
        Panes     = @($panes)
    }
}
