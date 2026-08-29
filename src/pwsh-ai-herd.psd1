@{
    RootModule        = 'pwsh-ai-herd.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '9b37fec9-6d8e-4726-b3d8-a888bd7704f2'
    Author            = 'Olivier Miossec'
    Copyright         = '(c) 2026 Olivier Miossec. All rights reserved.'
    Description       = 'Run up to 6 independent CLI coding agents (Claude, Codex, ...) side by side in a single console window, with optional git worktree isolation per agent.'

    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')

    # Not declared in RequiredModules on purpose: Microsoft.PowerShell.ConsoleGuiTools is
    # never imported as a module, it is only the delivery vehicle for Terminal.Gui.dll and
    # NStack.dll, which are Add-Type'd from its module base at run time. Listing it here
    # would force an import the module does not need. The presence check stays in code.
    RequiredModules   = @()

    FunctionsToExport = @('Start-AiHerd')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('AI', 'Agent', 'CLI', 'TUI', 'Terminal', 'Worktree', 'Claude', 'Codex')
            LicenseUri   = 'https://github.com/omiossec/pwsh-ai-herd/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/omiossec/pwsh-ai-herd'
            ReleaseNotes = 'Initial module scaffolding.'
        }
    }
}
