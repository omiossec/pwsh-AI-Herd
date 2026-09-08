<#
    Tests for the compiled C# child-process wrapper in src/class/00-FrameProcess.ps1.

    These start real short-lived processes: the point of the class is the plumbing between a
    child process and the queue the UI thread drains, and that cannot be faked usefully.
#>
BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    $script:Pwsh = [Environment]::ProcessPath

    # The whole argument string is handed to ProcessStartInfo as one blob, so any quoting in a
    # -Command script has to survive PowerShell's own re-parsing. Encoding the script sidesteps
    # that entirely.
    function Get-EncodedCommand {
        param([string]$Script)
        '-NoLogo -NoProfile -EncodedCommand ' +
            [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
    }

    function New-Child {
        param([string]$Arguments, [string]$WorkingDirectory)

        InModuleScope pwsh-ai-herd -Parameters @{ exe = $script:Pwsh; a = $Arguments; d = $WorkingDirectory } {
            param($exe, $a, $d)
            if ($d) { [FrameHost.FrameProcess]::new($exe, $a, $d) }
            else    { [FrameHost.FrameProcess]::new($exe, $a) }
        }
    }

    # Output arrives on thread-pool threads, so give it a moment rather than assuming it landed.
    function Wait-Output {
        param($Process, [int]$Count = 1, [int]$TimeoutMs = 15000)

        $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
        while ([DateTime]::UtcNow -lt $deadline -and $Process.Output.Count -lt $Count) {
            Start-Sleep -Milliseconds 100
        }

        $lines = @()
        $line  = $null
        while ($Process.Output.TryDequeue([ref]$line)) { $lines += $line }
        return , $lines
    }

    function Wait-Exit {
        param($Process, [int]$TimeoutMs = 15000)

        $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
        while ([DateTime]::UtcNow -lt $deadline -and -not $Process.HasExited) {
            Start-Sleep -Milliseconds 100
        }
        return $Process.HasExited
    }
}

Describe 'FrameHost.FrameProcess' {

    Context 'the compiled type' {

        It 'is available once the module is imported' {
            'FrameHost.FrameProcess' -as [type] | Should -Not -BeNullOrEmpty
        }

        It 'is disposable, so the frame host can clean up in its finally block' {
            ('FrameHost.FrameProcess' -as [type]).GetInterface('IDisposable') | Should -Not -BeNullOrEmpty
        }

        It 'takes a working directory as its third constructor argument' {
            $constructors = ('FrameHost.FrameProcess' -as [type]).GetConstructors()

            @($constructors | Where-Object { $_.GetParameters().Count -eq 3 }).Count | Should -Be 1
        }
    }

    Context 'a running child process' {

        BeforeAll {
            $script:child = New-Child -Arguments '-NoLogo -NoProfile -Command Start-Sleep -Seconds 30'
        }

        AfterAll {
            if ($script:child) { $script:child.Dispose() }
        }

        It 'reports the process id' {
            $script:child.Id | Should -BeGreaterThan 0
        }

        It 'reports that it is still running' {
            $script:child.HasExited | Should -BeFalse
        }

        It 'is a separate operating system process' {
            Get-Process -Id $script:child.Id -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'capturing output' {

        It 'queues what the process writes to stdout' {
            $child = New-Child -Arguments (Get-EncodedCommand "Write-Output 'hello from the child'")
            try {
                # Assigned first: piping the wrapped collection would hand Should the whole
                # array as a single item.
                $lines = Wait-Output -Process $child

                $lines | Should -Contain 'hello from the child'
            }
            finally { $child.Dispose() }
        }

        It 'queues each line separately' {
            $child = New-Child -Arguments (Get-EncodedCommand "'one'; 'two'; 'three'")
            try {
                $lines = Wait-Output -Process $child -Count 3

                $lines | Should -Contain 'one'
                $lines | Should -Contain 'three'
            }
            finally { $child.Dispose() }
        }

        It 'marks stderr lines so the frame can show them differently' {
            $child = New-Child -Arguments (Get-EncodedCommand "[Console]::Error.WriteLine('bad news')")
            try {
                $lines = Wait-Output -Process $child

                @($lines | Where-Object { $_ -eq '! bad news' }).Count | Should -Be 1
            }
            finally { $child.Dispose() }
        }

        It 'uses a queue the UI thread can drain safely' {
            $child = New-Child -Arguments (Get-EncodedCommand "'x'")
            try {
                $child.Output.GetType().Name | Should -BeLike 'ConcurrentQueue*'
            }
            finally { $child.Dispose() }
        }
    }

    Context 'writing to stdin' {

        It 'delivers a line to the child process' {
            $child = New-Child -Arguments (Get-EncodedCommand '$line = [Console]::In.ReadLine(); Write-Output "echo: $line"')
            try {
                $child.SendLine('ping')

                $lines = Wait-Output -Process $child

                $lines | Should -Contain 'echo: ping'
            }
            finally { $child.Dispose() }
        }

        It 'does nothing when the process has already exited' {
            $child = New-Child -Arguments '-NoLogo -NoProfile -Command exit 0'
            try {
                [void](Wait-Exit -Process $child)

                { $child.SendLine('too late') } | Should -Not -Throw
            }
            finally { $child.Dispose() }
        }
    }

    Context 'a process that exits' {

        It 'reports that it has exited' {
            $child = New-Child -Arguments '-NoLogo -NoProfile -Command exit 0'
            try {
                Wait-Exit -Process $child | Should -BeTrue
            }
            finally { $child.Dispose() }
        }

        It 'reports the exit code' {
            $child = New-Child -Arguments '-NoLogo -NoProfile -Command exit 3'
            try {
                [void](Wait-Exit -Process $child)

                $child.ExitCode | Should -Be 3
            }
            finally { $child.Dispose() }
        }
    }

    Context 'stopping a process' {

        It 'kills a running child' {
            $child = New-Child -Arguments '-NoLogo -NoProfile -Command Start-Sleep -Seconds 60'
            try {
                $child.Stop()

                Wait-Exit -Process $child | Should -BeTrue
            }
            finally { $child.Dispose() }
        }

        It 'can be stopped twice without throwing' {
            $child = New-Child -Arguments '-NoLogo -NoProfile -Command Start-Sleep -Seconds 60'
            try {
                $child.Stop()
                [void](Wait-Exit -Process $child)

                { $child.Stop() } | Should -Not -Throw
            }
            finally { $child.Dispose() }
        }

        It 'is stopped by Dispose as well, so the frame host cannot leak agents' {
            $child = New-Child -Arguments '-NoLogo -NoProfile -Command Start-Sleep -Seconds 60'
            $id = $child.Id

            $child.Dispose()
            Start-Sleep -Milliseconds 800

            Get-Process -Id $id -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    Context 'the working directory' {

        It 'starts the child where it was told, not where the host happens to be' {
            $child = New-Child -Arguments (Get-EncodedCommand '(Get-Location).Path') `
                -WorkingDirectory ([string]$TestDrive)
            try {
                $lines = Wait-Output -Process $child

                $lines[0] | Should -Be ([string]$TestDrive)
            }
            finally { $child.Dispose() }
        }
    }
}
