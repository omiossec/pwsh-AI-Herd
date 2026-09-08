<#
    Module-level conventions, the ones the loader depends on.

    Export-ModuleMember uses the public file base names and FunctionsToExport gates what is
    visible after Import-Module, so a file whose name does not match its function silently
    disappears from the module. These tests catch that.
#>
BeforeAll {
    $script:SourceRoot   = (Resolve-Path -Path (Join-Path $PSScriptRoot '../src')).ProviderPath
    $script:ManifestPath = Join-Path -Path $script:SourceRoot -ChildPath 'pwsh-ai-herd.psd1'

    Import-Module -Name $script:ManifestPath -Force

    $script:Manifest    = Test-ModuleManifest -Path $script:ManifestPath
    $script:PublicFile  = @(Get-ChildItem -Path (Join-Path $script:SourceRoot 'public')  -Filter '*.ps1' -File)
    $script:PrivateFile = @(Get-ChildItem -Path (Join-Path $script:SourceRoot 'private') -Filter '*.ps1' -File)
    $script:ClassFile   = @(Get-ChildItem -Path (Join-Path $script:SourceRoot 'class')   -Filter '*.ps1' -File)
    $script:AllFile     = $script:PublicFile + $script:PrivateFile

    function Get-FunctionName {
        param([string]$Path)

        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)

        # The leading comma keeps a single name an array rather than a bare string, which the
        # caller would then index one character at a time.
        return , @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) |
            ForEach-Object { $_.Name })
    }
}

Describe 'the module manifest' {

    It 'is valid' {
        $script:Manifest | Should -Not -BeNullOrEmpty
    }

    It 'requires PowerShell 7' {
        $script:Manifest.PowerShellVersion | Should -BeGreaterOrEqual ([version]'7.0')
    }

    It 'targets PowerShell Core only' {
        $script:Manifest.CompatiblePSEditions | Should -Be @('Core')
    }

    It 'points at the loader' {
        $script:Manifest.RootModule | Should -Be 'pwsh-ai-herd.psm1'
    }

    It 'does not force ConsoleGuiTools to be imported, it is only a source of assemblies' {
        $script:Manifest.RequiredModules | Should -BeNullOrEmpty
    }

    It 'exports no cmdlets, variables or aliases' {
        @($script:Manifest.ExportedCmdlets.Keys).Count   | Should -Be 0
        @($script:Manifest.ExportedVariables.Keys).Count | Should -Be 0
        @($script:Manifest.ExportedAliases.Keys).Count   | Should -Be 0
    }
}

Describe 'what the module exports' {

    It 'exports one function per file in public' {
        @($script:Manifest.ExportedFunctions.Keys).Count | Should -Be $script:PublicFile.Count
    }

    It 'exports <Name>, whose file is in public' -TestCases @(
        (Get-ChildItem -Path (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../src')) 'public') -Filter '*.ps1' -File |
            ForEach-Object { @{ Name = $_.BaseName } })
    ) {
        (Get-Module -Name 'pwsh-ai-herd').ExportedFunctions.Keys | Should -Contain $Name
    }

    It 'lists <Name> in the manifest, without which it is invisible after Import-Module' -TestCases @(
        (Get-ChildItem -Path (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../src')) 'public') -Filter '*.ps1' -File |
            ForEach-Object { @{ Name = $_.BaseName } })
    ) {
        $script:Manifest.ExportedFunctions.Keys | Should -Contain $Name
    }

    It 'keeps every private function private' {
        $exported = (Get-Module -Name 'pwsh-ai-herd').ExportedFunctions.Keys

        foreach ($file in $script:PrivateFile) {
            $exported | Should -Not -Contain $file.BaseName
        }
    }
}

Describe 'the one function per file convention' {

    It '<Name> defines exactly one function' -TestCases @(
        (Get-ChildItem -Path (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../src')) 'public'), (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../src')) 'private') -Filter '*.ps1' -File |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
    ) {
        @(Get-FunctionName -Path $Path).Count | Should -Be 1
    }

    It '<Name> is named after the function it defines' -TestCases @(
        (Get-ChildItem -Path (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../src')) 'public'), (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../src')) 'private') -Filter '*.ps1' -File |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName; BaseName = $_.BaseName } })
    ) {
        (Get-FunctionName -Path $Path)[0] | Should -Be $BaseName
    }
}

Describe 'coding conventions' {

    It '<Name> parses without error' -TestCases @(
        (Get-ChildItem -Path (Resolve-Path (Join-Path $PSScriptRoot '../src')) -Filter '*.ps1' -File -Recurse |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
    ) {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)

        $errors | Should -BeNullOrEmpty
    }

    It '<Name> uses CmdletBinding' -TestCases @(
        (Get-ChildItem -Path (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../src')) 'public'), (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../src')) 'private') -Filter '*.ps1' -File |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
    ) {
        Get-Content -Path $Path -Raw | Should -Match '\[CmdletBinding'
    }

    It '<Name> carries comment-based help with a synopsis' -TestCases @(
        (Get-ChildItem -Path (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../src')) 'public'), (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../src')) 'private') -Filter '*.ps1' -File |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
    ) {
        Get-Content -Path $Path -Raw | Should -Match '\.SYNOPSIS'
    }

    It 'every public function documents at least one example' -TestCases @(
        (Get-ChildItem -Path (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../src')) 'public') -Filter '*.ps1' -File |
            ForEach-Object { @{ Name = $_.BaseName } })
    ) {
        @((Get-Help -Name $Name -Examples).Examples.Example).Count | Should -BeGreaterThan 0
    }

    It 'the class file is prefixed so its load order is fixed' {
        $script:ClassFile | ForEach-Object { $_.Name | Should -Match '^\d\d-' }
    }
}

Describe 'the public surface' {

    It 'every state-changing command supports WhatIf' -TestCases @(
        @{ Name = 'Start-AiGrid' }
        @{ Name = 'Resume-AiGrid' }
        @{ Name = 'Add-AiGridAgent' }
        @{ Name = 'Send-AiGridText' }
        @{ Name = 'Remove-AiGridWorktree' }
    ) {
        (Get-Command -Name $Name).Parameters.ContainsKey('WhatIf') | Should -BeTrue
    }

    It 'the destructive command asks before acting' {
        $metadata = [System.Management.Automation.CommandMetadata](Get-Command -Name 'Remove-AiGridWorktree')

        $metadata.ConfirmImpact | Should -Be 'High'
    }

    It 'every command uses an approved verb' {
        foreach ($name in (Get-Module -Name 'pwsh-ai-herd').ExportedFunctions.Keys) {
            $verb = $name.Split('-')[0]

            (Get-Verb -Verb $verb) | Should -Not -BeNullOrEmpty -Because "$name should use an approved verb"
        }
    }
}

Describe 'static analysis' {

    BeforeAll {
        $script:HasAnalyzer = [bool](Get-Module -Name 'PSScriptAnalyzer' -ListAvailable)

        # Accepted, and documented in CLAUDE.md:
        #   the TUI helpers and the two grid builders change state but must not prompt, because
        #   the public commands they serve already do;
        #   the MainLoop parameter exists to satisfy the Func[MainLoop,bool] timer signature;
        #   Test-ConsoleGuiTools has a plural noun because that is the module's literal name.
        $script:Accepted = @(
            @{ Rule = 'PSUseShouldProcessForStateChangingFunctions'; File = 'New-Frame.ps1' }
            @{ Rule = 'PSUseShouldProcessForStateChangingFunctions'; File = 'Set-FrameLayout.ps1' }
            @{ Rule = 'PSUseShouldProcessForStateChangingFunctions'; File = 'Update-Frame.ps1' }
            @{ Rule = 'PSUseShouldProcessForStateChangingFunctions'; File = 'Update-FrameView.ps1' }
            @{ Rule = 'PSUseShouldProcessForStateChangingFunctions'; File = 'Start-AiHerd.ps1' }
            @{ Rule = 'PSUseShouldProcessForStateChangingFunctions'; File = 'New-HerdGrid.ps1' }
            @{ Rule = 'PSUseShouldProcessForStateChangingFunctions'; File = 'New-HerdWorktree.ps1' }
            @{ Rule = 'PSReviewUnusedParameter';                     File = 'Start-AiHerd.ps1' }
            @{ Rule = 'PSUseSingularNouns';                          File = 'Test-ConsoleGuiTools.ps1' }
        )
    }

    It 'reports nothing beyond the accepted warnings' -Skip:(-not [bool](Get-Module -Name 'PSScriptAnalyzer' -ListAvailable)) {
        $findings = @(Invoke-ScriptAnalyzer -Path $script:SourceRoot -Recurse -Severity Warning, Error)

        $unexpected = @($findings | Where-Object {
            $finding = $_
            -not ($script:Accepted | Where-Object {
                $_.Rule -eq $finding.RuleName -and $_.File -eq (Split-Path -Path $finding.ScriptPath -Leaf)
            })
        })

        ($unexpected | ForEach-Object { "$($_.RuleName) in $($_.ScriptName):$($_.Line)" }) -join '; ' |
            Should -BeNullOrEmpty
    }
}
