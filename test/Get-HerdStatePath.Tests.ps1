BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    function Get-StatePath {
        param([string]$ChildPath)
        InModuleScope pwsh-ai-herd -Parameters @{ c = $ChildPath } {
            param($c)
            if ($c) { Get-HerdStatePath -ChildPath $c } else { Get-HerdStatePath }
        }
    }
}

Describe 'Get-HerdStatePath' {

    Context 'the state root' {

        It 'returns a path' {
            Get-StatePath | Should -Not -BeNullOrEmpty
        }

        It 'creates the directory so callers can write into it straight away' {
            Test-Path -Path (Get-StatePath) -PathType Container | Should -BeTrue
        }

        It 'is named after the module' {
            Split-Path -Path (Get-StatePath) -Leaf | Should -Be 'pwsh-ai-herd'
        }

        It 'is stable across calls' {
            Get-StatePath | Should -Be (Get-StatePath)
        }

        It 'lives under the local application data folder on Windows' -Skip:(-not $IsWindows) {
            Get-StatePath | Should -BeLike "$env:LOCALAPPDATA*"
        }

        It 'follows the XDG state convention elsewhere' -Skip:$IsWindows {
            Get-StatePath | Should -Match '(\.local[/\\]state|XDG)'
        }
    }

    Context 'sub-directories' {

        It 'appends the <Child> child path' -TestCases @(
            @{ Child = 'grids' }
            @{ Child = 'worktrees' }
        ) {
            Split-Path -Path (Get-StatePath -ChildPath $Child) -Leaf | Should -Be $Child
        }

        It 'creates the sub-directory as well' {
            Test-Path -Path (Get-StatePath -ChildPath 'grids') -PathType Container | Should -BeTrue
        }

        It 'nests the sub-directory inside the state root' {
            Split-Path -Path (Get-StatePath -ChildPath 'grids') -Parent | Should -Be (Get-StatePath)
        }

        It 'is idempotent when the directory already exists' {
            { Get-StatePath -ChildPath 'grids'; Get-StatePath -ChildPath 'grids' } | Should -Not -Throw
        }
    }
}
