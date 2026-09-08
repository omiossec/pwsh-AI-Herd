#Requires -Version 7.0
<#
    .SYNOPSIS
        Runs the pwsh-ai-herd Pester suite.

    .DESCRIPTION
        Wraps Invoke-Pester with the configuration the suite expects, so a run is one command
        whatever shell it starts from. Nothing here opens a terminal or starts an agent: the
        wezterm CLI and git are faked, and the only real child processes are the short-lived
        ones the FrameProcess tests need.

    .PARAMETER Name
        Run only the files whose name matches this wildcard, for example 'Get-*'.

    .PARAMETER TestName
        Run only the tests whose full name matches this wildcard.

    .PARAMETER Output
        Pester output verbosity. Detailed lists every test.

    .PARAMETER CodeCoverage
        Also measure how much of src is covered, and write coverage.xml next to this script.

    .PARAMETER CI
        Write a JUnit result file and fail the process with a non-zero exit code when a test
        fails, for use in a pipeline.

    .EXAMPLE
        ./test/Invoke-Test.ps1

    .EXAMPLE
        ./test/Invoke-Test.ps1 -Name 'Get-WezTerm*' -Output Detailed

    .EXAMPLE
        ./test/Invoke-Test.ps1 -CI
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Name = '*',

    [Parameter()]
    [string]$TestName,

    [Parameter()]
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Normal',

    [Parameter()]
    [switch]$CodeCoverage,

    [Parameter()]
    [switch]$CI
)

$ErrorActionPreference = 'Stop'

$pester = Get-Module -Name 'Pester' -ListAvailable |
    Where-Object { $_.Version -ge [version]'5.0.0' } |
    Sort-Object -Property Version -Descending |
    Select-Object -First 1

if (-not $pester) {
    throw 'Pester 5 or later is required. Install it with: Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force'
}
Import-Module -ModuleInfo $pester -Force

$configuration = New-PesterConfiguration
$configuration.Run.Path      = @(Get-ChildItem -Path $PSScriptRoot -Filter "$Name.Tests.ps1" -File | ForEach-Object { $_.FullName })
$configuration.Run.PassThru  = $true
$configuration.Output.Verbosity = $Output

if ($configuration.Run.Path.Value.Count -eq 0) {
    throw "No test file matched '$Name'."
}

if ($TestName) {
    $configuration.Filter.FullName = $TestName
}

if ($CodeCoverage) {
    $configuration.CodeCoverage.Enabled      = $true
    $configuration.CodeCoverage.Path         = @(Join-Path -Path $PSScriptRoot -ChildPath '../src')
    $configuration.CodeCoverage.OutputPath   = Join-Path -Path $PSScriptRoot -ChildPath 'coverage.xml'
    $configuration.CodeCoverage.OutputFormat = 'JaCoCo'
}

if ($CI) {
    $configuration.TestResult.Enabled      = $true
    $configuration.TestResult.OutputPath   = Join-Path -Path $PSScriptRoot -ChildPath 'TestResults.xml'
    $configuration.TestResult.OutputFormat = 'JUnitXml'
}

$result = Invoke-Pester -Configuration $configuration

if ($CI -and $result.FailedCount -gt 0) {
    exit 1
}

$result
