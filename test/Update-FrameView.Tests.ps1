BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelper.ps1')

    function Update-View {
        param($Frame)
        InModuleScope pwsh-ai-herd -Parameters @{ f = $Frame } {
            param($f)
            Update-FrameView -Frame $f
        }
    }
}

Describe 'Update-FrameView' {

    Context 'feeding the list' {

        It 'shows every line the frame holds' {
            $frame = New-FakeFrame
            $frame.Lines.AddRange([string[]]@('one', 'two', 'three'))

            Update-View -Frame $frame

            $frame.List.Source | Should -Be @('one', 'two', 'three')
        }

        It 'hands the list a plain array, not the live collection' {
            $frame = New-FakeFrame
            $frame.Lines.Add('one')

            Update-View -Frame $frame
            $frame.Lines.Add('two')

            @($frame.List.Source).Count | Should -Be 1
        }

        It 'copes with an empty frame' {
            $frame = New-FakeFrame

            { Update-View -Frame $frame } | Should -Not -Throw
        }

        It 'asks for a redraw' {
            $frame = New-FakeFrame
            $frame.Lines.Add('one')

            Update-View -Frame $frame

            $frame.List.RedrawCount | Should -Be 1
        }
    }

    Context 'staying scrolled to the bottom' {

        It 'scrolls so the newest line is visible' {
            $frame = New-FakeFrame -ListHeight 5
            1..20 | ForEach-Object { $frame.Lines.Add("line $_") }

            Update-View -Frame $frame

            $frame.List.TopItem | Should -Be 15
        }

        It 'does not scroll while everything fits' {
            $frame = New-FakeFrame -ListHeight 10
            1..3 | ForEach-Object { $frame.Lines.Add("line $_") }

            Update-View -Frame $frame

            $frame.List.TopItem | Should -Be 0
        }

        It 'does not scroll when the list is exactly full' {
            $frame = New-FakeFrame -ListHeight 5
            1..5 | ForEach-Object { $frame.Lines.Add("line $_") }

            Update-View -Frame $frame

            $frame.List.TopItem | Should -Be 0
        }

        It 'leaves the scroll alone before the view has been laid out' {
            # Bounds.Height is zero until Terminal.Gui lays the frame out.
            $frame = New-FakeFrame -ListHeight 0
            1..20 | ForEach-Object { $frame.Lines.Add("line $_") }

            Update-View -Frame $frame

            $frame.List.TopItem | Should -Be 0
        }
    }
}
