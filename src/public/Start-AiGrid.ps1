function Start-AiGrid {
    <#
    .SYNOPSIS
        Opens a WezTerm window with a grid of interactive coding agents, one per pane.

    .DESCRIPTION
        The WezTerm backend of pwsh-ai-herd, the PowerShell counterpart of the tmux `sam`
        command from agentic-config. Unlike Start-AiHerd, every pane is a real terminal, so the
        agents run their normal full-screen UI: permission prompts, slash commands and colours
        all work.

        Each Claude pane is launched with a pinned session id, so the whole grid can be
        reopened later with Resume-AiGrid, every pane resuming its own conversation. Effort is
        spread the way the tmux version does it: the last pane runs low, roughly a quarter run
        medium, the rest run at the default level.

        The grid is recorded per project directory under the module state folder
        (%LOCALAPPDATA%\pwsh-ai-herd on Windows). Relaunching from the same directory
        overwrites the previous record.

    .PARAMETER Count
        Number of agents. Auto layout picks the smallest square-ish grid with columns >= rows
        (6 -> 3 x 2). Defaults to 4.

    .PARAMETER Columns
        Explicit number of columns; use with -Rows. The grid then holds Columns * Rows agents.

    .PARAMETER Rows
        Explicit number of rows; use with -Columns.

    .PARAMETER Agent
        Claude (default), Codex, Copilot, or Mixed to alternate Claude / Codex panes.

    .PARAMETER Worktree
        Give every agent its own git worktree on branch herd/<session>-<n>, created under the
        module state folder. The current directory must be inside a git repository.

    .PARAMETER Kickoff
        A first prompt sent to every agent on launch. Not used when resuming.

    .PARAMETER WorkingDirectory
        Project directory the agents start in. Defaults to the current location.

    .EXAMPLE
        Start-AiGrid

        Four Claude agents in a 2 x 2 grid, in the current directory.

    .EXAMPLE
        Start-AiGrid -Count 6

        Six agents, 3 columns x 2 rows.

    .EXAMPLE
        Start-AiGrid -Columns 3 -Rows 1 -Agent Mixed

        Three agents in one row: Claude, Codex, Claude.

    .EXAMPLE
        Start-AiGrid -Count 4 -Worktree

        Four Claude agents, each isolated in its own git worktree and branch.

    .NOTES
        Requires WezTerm (https://wezterm.org). The agent executables must be on PATH in the
        panes, which run the same pwsh as the caller.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Count', SupportsShouldProcess)]
    [OutputType([psobject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Count')]
        [ValidateRange(1, 16)]
        [int]$Count = 4,

        [Parameter(Mandatory, ParameterSetName = 'Matrix')]
        [ValidateRange(1, 8)]
        [int]$Columns,

        [Parameter(Mandatory, ParameterSetName = 'Matrix')]
        [ValidateRange(1, 8)]
        [int]$Rows,

        [Parameter()]
        [ValidateSet('Claude', 'Codex', 'Copilot', 'Mixed')]
        [string]$Agent = 'Claude',

        [Parameter()]
        [switch]$Worktree,

        [Parameter()]
        [string]$Kickoff,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$WorkingDirectory
    )

    $ErrorActionPreference = 'Stop'

    if (-not $PSBoundParameters.ContainsKey('WorkingDirectory')) {
        $WorkingDirectory = if ($PWD.Provider.Name -eq 'FileSystem') { $PWD.ProviderPath } else { [Environment]::CurrentDirectory }
    }
    $WorkingDirectory = (Resolve-Path -Path $WorkingDirectory).ProviderPath

    $geometry = if ($PSCmdlet.ParameterSetName -eq 'Matrix') {
        Get-GridGeometry -Columns $Columns -Rows $Rows
    }
    else {
        Get-GridGeometry -Count $Count
    }
    $n      = $geometry.Count
    $effort = Get-AgentEffort -Count $n

    $what = "open a $($geometry.Columns) x $($geometry.Rows) WezTerm grid of $n $Agent agent(s)"
    if ($Worktree) { $what += ', one git worktree each' }
    if (-not $PSCmdlet.ShouldProcess($WorkingDirectory, $what)) {
        return
    }

    #region worktrees
    $worktreeInfo = @()
    if ($Worktree) {
        $safeName = (Split-Path -Path $WorkingDirectory -Leaf) -replace '[^A-Za-z0-9_-]', '_'
        $session  = '{0}-{1}' -f $safeName, [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $base     = Join-Path -Path (Get-HerdStatePath -ChildPath 'worktrees') -ChildPath $session
        for ($i = 1; $i -le $n; $i++) {
            $worktreeInfo += New-HerdWorktree -Repository $WorkingDirectory `
                -Path (Join-Path -Path $base -ChildPath $i) -Branch "herd/$session-$i"
        }
    }
    #endregion

    #region pane specs
    $pane = for ($i = 0; $i -lt $n; $i++) {
        $engine = switch ($Agent) {
            'Mixed' { if ($i % 2 -eq 0) { 'Claude' } else { 'Codex' } }
            default { $Agent }
        }
        [PSCustomObject]@{
            Index     = $i
            SessionId = [guid]::NewGuid().ToString()
            Agent     = $engine
            Effort    = $effort[$i]
            Task      = $null
            Kickoff   = $Kickoff
            Worktree  = if ($Worktree) { $worktreeInfo[$i].Path }   else { $null }
            Branch    = if ($Worktree) { $worktreeInfo[$i].Branch } else { $null }
            PaneId    = $null
        }
    }
    #endregion

    New-HerdGrid -Directory $WorkingDirectory -Columns $geometry.Columns -Rows $geometry.Rows -Pane @($pane)
}
