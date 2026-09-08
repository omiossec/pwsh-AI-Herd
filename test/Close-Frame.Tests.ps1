BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.ps1')

    function New-FakeContainer {
        $container = [PSCustomObject]@{ Removed = [System.Collections.Generic.List[object]]::new() }
        $container | Add-Member -MemberType ScriptMethod -Name 'Remove' -Value { param($View) $this.Removed.Add($View) }
        return $container
    }

    # Close-Frame edits the module's frame list, so the state has to be installed there.
    function Invoke-Close {
        param($Frame, $AllFrames, $Container)

        InModuleScope pwsh-ai-herd -Parameters @{ f = $Frame; all = $AllFrames; c = $Container } {
            param($f, $all, $c)
            $script:Frames = [System.Collections.Generic.List[psobject]]::new()
            foreach ($item in $all) { $script:Frames.Add($item) }
            $script:FrameContainer = $c

            Close-Frame -Frame $f

            return $script:Frames
        }
    }
}

Describe 'Close-Frame' {

    BeforeEach {
        Mock -ModuleName pwsh-ai-herd Set-FrameLayout { }

        $script:container = New-FakeContainer
        $script:first     = New-FakeFrame -Id 101
        $script:second    = New-FakeFrame -Id 102
        $script:third     = New-FakeFrame -Id 103
    }

    Context 'closing one frame of several' {

        BeforeEach {
            $script:remaining = Invoke-Close -Frame $script:second `
                -AllFrames @($script:first, $script:second, $script:third) -Container $script:container
        }

        It 'kills the process tree of that frame' {
            $script:second.Process.Disposed | Should -BeTrue
        }

        It 'leaves the other processes running' {
            $script:first.Process.Disposed | Should -BeFalse
            $script:third.Process.Disposed | Should -BeFalse
        }

        It 'drops the frame from the list' {
            @($script:remaining).Count | Should -Be 2
        }

        It 'keeps the other frames in order' {
            @($script:remaining)[0].Process.Id | Should -Be 101
            @($script:remaining)[1].Process.Id | Should -Be 103
        }

        It 'removes the view from the window' {
            $script:container.Removed | Should -Contain $script:second.View
        }

        It 'relays out the frames that are left' {
            Should -Invoke -ModuleName pwsh-ai-herd Set-FrameLayout -Times 1 -Exactly
        }
    }

    Context 'closing the last frame' {

        BeforeEach {
            $script:remaining = Invoke-Close -Frame $script:first `
                -AllFrames @($script:first) -Container $script:container
        }

        It 'leaves no frames' {
            @($script:remaining).Count | Should -Be 0
        }

        It 'still relays out, so the empty window is redrawn' {
            Should -Invoke -ModuleName pwsh-ai-herd Set-FrameLayout -Times 1 -Exactly
        }
    }

    Context 'a process that has already exited' {

        It 'still cleans up the frame' {
            $exited = New-FakeFrame -HasExited $true

            $remaining = Invoke-Close -Frame $exited -AllFrames @($exited) -Container $script:container

            @($remaining).Count      | Should -Be 0
            $exited.Process.Disposed | Should -BeTrue
        }
    }
}
