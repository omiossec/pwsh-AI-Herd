# Terminal.Gui is only needed to build the Pos and Dim values, and views construct fine without
# Application.Init, so no console is required here. The probe has to run at file scope: Pester
# evaluates -Skip during discovery, long before any BeforeAll block.
. (Join-Path -Path $PSScriptRoot -ChildPath 'TerminalGuiProbe.ps1')

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    function Invoke-Layout {
        param([int]$Count)

        InModuleScope pwsh-ai-herd -Parameters @{ n = $Count } {
            param($n)

            $script:Frames = [System.Collections.Generic.List[psobject]]::new()
            for ($i = 0; $i -lt $n; $i++) {
                $script:Frames.Add([PSCustomObject]@{ View = [Terminal.Gui.FrameView]::new("frame $i") })
            }
            $script:FrameContainer = [Terminal.Gui.View]::new()
            foreach ($frame in $script:Frames) { $script:FrameContainer.Add($frame.View) }

            Set-FrameLayout

            return @($script:Frames | ForEach-Object {
                [PSCustomObject]@{
                    X      = $_.View.X.ToString()
                    Y      = $_.View.Y.ToString()
                    Width  = $_.View.Width.ToString()
                    Height = $_.View.Height.ToString()
                }
            })
        }
    }
}

Describe 'Set-FrameLayout' -Skip:(-not $script:HasTerminalGui) {

    Context 'an empty window' {

        It 'does not throw when there is nothing to lay out' {
            {
                InModuleScope pwsh-ai-herd {
                    $script:Frames         = [System.Collections.Generic.List[psobject]]::new()
                    $script:FrameContainer = [Terminal.Gui.View]::new()
                    Set-FrameLayout
                }
            } | Should -Not -Throw
        }
    }

    Context 'one frame' {

        It 'fills the window' {
            $layout = Invoke-Layout -Count 1

            $layout[0].Width  | Should -Match 'Fill'
            $layout[0].Height | Should -Match 'Fill'
        }

        It 'starts at the origin' {
            $layout = Invoke-Layout -Count 1

            $layout[0].X | Should -Match '0'
            $layout[0].Y | Should -Match '0'
        }
    }

    Context 'two frames' {

        It 'places them side by side' {
            $layout = Invoke-Layout -Count 2

            $layout[0].Y | Should -Be $layout[1].Y
            $layout[0].X | Should -Not -Be $layout[1].X
        }

        It 'gives both frames the full height' {
            $layout = Invoke-Layout -Count 2

            $layout[0].Height | Should -Match 'Fill'
            $layout[1].Height | Should -Match 'Fill'
        }

        It 'lets the last column absorb the rounding' {
            $layout = Invoke-Layout -Count 2

            $layout[1].Width | Should -Match 'Fill'
        }
    }

    Context 'four frames' {

        It 'uses two rows' {
            $layout = Invoke-Layout -Count 4

            $layout[0].Y | Should -Be $layout[1].Y
            $layout[2].Y | Should -Be $layout[3].Y
            $layout[0].Y | Should -Not -Be $layout[2].Y
        }

        It 'uses two columns' {
            $layout = Invoke-Layout -Count 4

            $layout[0].X | Should -Be $layout[2].X
            $layout[0].X | Should -Not -Be $layout[1].X
        }

        It 'gives the bottom row the remaining height' {
            $layout = Invoke-Layout -Count 4

            $layout[2].Height | Should -Match 'Fill'
            $layout[3].Height | Should -Match 'Fill'
        }
    }

    Context 'six frames' {

        It 'fills three columns before starting a second row' {
            $layout = Invoke-Layout -Count 6

            @($layout[0..2] | ForEach-Object { $_.Y } | Select-Object -Unique).Count | Should -Be 1
            @($layout[3..5] | ForEach-Object { $_.Y } | Select-Object -Unique).Count | Should -Be 1
        }

        It 'reuses the column positions on the second row' {
            $layout = Invoke-Layout -Count 6

            $layout[0].X | Should -Be $layout[3].X
            $layout[1].X | Should -Be $layout[4].X
            $layout[2].X | Should -Be $layout[5].X
        }
    }

    Context 'every supported size' {

        It 'lays out <Count> frames without throwing' -TestCases @(
            @{ Count = 1 }
            @{ Count = 2 }
            @{ Count = 3 }
            @{ Count = 4 }
            @{ Count = 5 }
            @{ Count = 6 }
        ) {
            { Invoke-Layout -Count $Count } | Should -Not -Throw
        }

        It 'gives every frame a size' {
            $layout = Invoke-Layout -Count 5

            $layout | ForEach-Object {
                $_.Width  | Should -Not -BeNullOrEmpty
                $_.Height | Should -Not -BeNullOrEmpty
            }
        }
    }
}
