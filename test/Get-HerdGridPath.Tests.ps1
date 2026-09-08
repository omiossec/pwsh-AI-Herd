BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/pwsh-ai-herd.psd1') -Force

    function Get-GridPath {
        param([string]$Directory)
        InModuleScope pwsh-ai-herd -Parameters @{ d = $Directory } {
            param($d)
            Get-HerdGridPath -Directory $d
        }
    }
}

Describe 'Get-HerdGridPath' {

    Context 'shape of the path' {

        It 'names the file after a 32 character hash' {
            [IO.Path]::GetFileNameWithoutExtension((Get-GridPath 'C:\work\project')) |
                Should -Match '^[0-9a-f]{32}$'
        }

        It 'uses a json extension' {
            [IO.Path]::GetExtension((Get-GridPath 'C:\work\project')) | Should -Be '.json'
        }

        It 'puts the file in the grids folder of the module state directory' {
            Split-Path -Path (Get-GridPath 'C:\work\project') -Parent |
                Should -BeLike '*pwsh-ai-herd*grids'
        }
    }

    Context 'one grid per project' {

        It 'is stable across calls, so a relaunch overwrites the same record' {
            Get-GridPath 'C:\work\project' | Should -Be (Get-GridPath 'C:\work\project')
        }

        It 'gives different projects different files' {
            Get-GridPath 'C:\work\alpha' | Should -Not -Be (Get-GridPath 'C:\work\beta')
        }

        It 'ignores a trailing directory separator' {
            Get-GridPath 'C:\work\project' | Should -Be (Get-GridPath 'C:\work\project\')
        }

        It 'ignores a trailing forward slash too' {
            Get-GridPath 'C:\work\project' | Should -Be (Get-GridPath 'C:\work\project/')
        }

        It 'treats paths that differ only in case as the same project on Windows' -Skip:(-not $IsWindows) {
            Get-GridPath 'C:\Work\Project' | Should -Be (Get-GridPath 'c:\work\project')
        }

        It 'keeps case significant on Linux and macOS' -Skip:$IsWindows {
            Get-GridPath '/work/Project' | Should -Not -Be (Get-GridPath '/work/project')
        }
    }

    Context 'input validation' {

        It 'requires a directory' {
            { InModuleScope pwsh-ai-herd { Get-HerdGridPath -Directory '' } } | Should -Throw
        }
    }
}
