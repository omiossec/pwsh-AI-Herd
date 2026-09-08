# Tests

Pester 5 tests for every function in `src`, one file per function plus `Module.Tests.ps1` for
the module-level conventions and `FrameProcess.Tests.ps1` for the compiled C# wrapper.

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force   # once
./test/Invoke-Test.ps1                       # everything
./test/Invoke-Test.ps1 -Name 'Get-WezTerm*'  # one group of files
./test/Invoke-Test.ps1 -TestName '*worktree*' -Output Detailed
./test/Invoke-Test.ps1 -CI                   # JUnit result file, non-zero exit on failure
./test/Invoke-Test.ps1 -CodeCoverage
```

Nothing in the suite opens a terminal, starts an agent, touches a real repository, or writes
into the module state folder. WezTerm and git are faked. The only real child processes are the
short-lived `pwsh` instances the `FrameProcess` tests need, and they are always disposed.

## How the tests reach the code

Every function except the seven public ones is module-private, so tests call them through
`InModuleScope pwsh-ai-herd`. Values cross that boundary with `-Parameters`, because the block
does not inherit the caller's variables:

```powershell
InModuleScope pwsh-ai-herd -Parameters @{ n = $Count } {
    param($n)
    Get-GridGeometry -Count $n
}
```

Mocks use `-ModuleName pwsh-ai-herd` so the module's own calls are intercepted.

Two things to know before adding tests here:

- **Do not put `.GetNewClosure()` on a mock body.** It stops Pester binding the mocked
  function's parameters, so `$Arguments` and friends arrive empty. Pass canned values through
  a `$global:` variable instead, and clean it up in `AfterEach` or `AfterAll`.
- **Watch for single-element arrays unrolling.** A helper that returns a one-item collection
  hands the caller a bare scalar, and indexing it then walks a string character by character.
  Return `, @(...)` from such helpers, and assign before piping into `Should -Contain`.
- **Compute anything a `-Skip` reads at file scope, not in `BeforeAll`.** Pester evaluates
  `-Skip` while discovering tests, before any `BeforeAll` has run, so a flag set there is still
  empty and the whole file skips itself silently. `TerminalGuiProbe.ps1` is dot-sourced at file
  scope for exactly this reason.

## Fixtures

`TestHelper.ps1` is dot-sourced from the files that need it.

| Helper | What it stands in for |
| --- | --- |
| `New-FakeFrame` | A frame as `New-Frame` builds it, with a real `ConcurrentQueue` for output and fakes for the views, so the pump and input paths run without Terminal.Gui |
| `New-FakeProcess` | `FrameHost.FrameProcess`, recording what was sent to stdin and whether it was disposed |
| `New-FakeWezTerm` | A script that impersonates the wezterm executable, logging its arguments and returning canned output or a failure |
| `New-TestGridRecord` | A grid record shaped like the one `Save-HerdGrid` writes |

Terminal.Gui views construct without `Application.Init`, so `Set-FrameLayout` and `New-Frame`
are tested for real. They skip themselves when `Microsoft.PowerShell.ConsoleGuiTools` is not
installed, which `TerminalGuiProbe.ps1` decides.

On a machine with ConsoleGuiTools installed the suite runs about 740 tests in half a minute,
and only the five skips listed below are expected.

## Known defects the suite records

Two tests are skipped on purpose. Each states the behaviour the code is meant to have, next to
an active test pinning what it does today. Removing the `-Skip` is how you verify a fix.

1. **`Start-AiGrid` fails for a single agent.** `Get-AgentEffort` returns a one-element array
   that PowerShell unrolls to a bare string, and `Start-AiGrid` then indexes it as an array, so
   the pane gets the effort `d`. `Get-AgentPaneCommand` rejects that, so `Start-AiGrid -Count 1`
   and `-Columns 1 -Rows 1` both throw. See `Start-AiGrid.Tests.ps1`.

2. **`Get-EventSummary` cannot summarise an array of content blocks.** `switch` enumerates a
   collection, so its `[array]` branch is unreachable and the `default` branch reads the whole
   argument rather than the current element. A tool result made of content blocks renders as
   raw JSON in the frame instead of its text. See `Get-EventSummary.Tests.ps1`.
