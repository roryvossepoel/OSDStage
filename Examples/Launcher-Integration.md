# Integrate with a WinPE launcher

> Install the stable module from PowerShell Gallery. Check [release availability](../docs/release-status.md) when selecting a module version.

[Examples](README.md) · [Online staging](WinPE-Online.md) · [Results](../docs/getting-started.md#5-check-the-outcome)

Use this pattern in OSDT or another PowerShell-based WinPE launcher **after
OSDCloud has applied Windows and before the launcher reboots the target**.
It is an integration example, not a change to OSDT itself.

## Staging script

Include [Stage-OSDStage.ps1](Stage-OSDStage.ps1) in your launcher files. By default
it loads OSDStage from PowerShell Gallery and stages Office, Adobe Acrobat Unified
and Chrome. `-ModulePath` instead imports an explicit local module manifest, for
example a pinned development checkout on USB. `-OfficeLanguage`, `-IncludeTeams`,
`-Include7Zip` and `-WindowsUpdate` configure the example's queue.
With `-WindowsUpdate`, `-IncludeDrivers` includes drivers and firmware.
`-FinalAction None|Reboot|Shutdown` configures the action after successful Windows
deployment finalization; it defaults to `None`. It does not reboot WinPE.

Declare all repository apps together with `-RepositoryApp` and supply your
`-CatalogUri`. The runner checks that complete selection **before any Add command**,
including built-ins. The same selection and `-SkipCacheRefresh` setting are then
used for repository staging. A missing final repo app therefore blocks the first
built-in too. Missing IDs and their catalog/cache reasons appear in the error.

This repository check requires the current development module; it is not in RC4.
For testing, use `-ModulePath` and the runner from the same checkout. The runner
always calls `Test-OSDStageDeployment -ThrowOnFailure` after the last Add command.

Run the script in a **fresh child PowerShell process**. Do not dot-source it into
the UI process: the script uses `exit` to report its result. The Gallery path needs
PowerShellGet and Gallery access; an explicit local module does not need a Gallery
installation. The script does not prompt to choose a repository or install package
providers. Prepare the normal deployment prerequisites in the WinPE image or
launcher initialization.

## Gate the launcher's reboot

Adapt the local script path to where your launcher stores its files:

```powershell
$StagingScript = 'X:\OSDT\Scripts\Stage-OSDStage.ps1'
if (-not (Test-Path -LiteralPath $StagingScript -PathType Leaf)) {
    throw "Staging script not found: $StagingScript"
}

$process = Start-Process -FilePath 'powershell.exe' `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$StagingScript`"" `
    -Wait -PassThru -ErrorAction Stop

if ($process.ExitCode -ne 0) {
    throw "OSDStage staging failed (exit $($process.ExitCode)). Reboot blocked."
}

# Only this success path may reach the launcher's existing reboot action.
# For a manual WinPE reboot, that action is: wpeutil.exe reboot
```

The staging script itself never reboots. Keep the launcher's reboot action after
this gate; do not put it in a `finally` block or an unconditional completion
handler. If the UI catches the error, show it and return to the operator without
continuing the deployment sequence. Waiting for the child process is essential;
starting it successfully is not evidence that staging succeeded.

| Outcome | Launcher action |
| --- | --- |
| Process fails to start, or any nonzero exit code | Stop and show the error; do not reboot. |
| Exit code `0` | Staging and preflight passed; continue to the launcher's normal reboot step. |

To include repository apps, add `-CatalogUri` and `-RepositoryApp` to the child
script invocation. For multiple IDs, call the runner from a PowerShell wrapper
with an array rather than passing an array through `powershell.exe -File`:

```powershell
# Contents of a child script that the launcher starts and waits for:
$checkout = 'E:\TestModules\OSDStage-<tested-commit>' # Use the detected USB path.
& "$checkout\Examples\Stage-OSDStage.ps1" `
    -ModulePath "$checkout\OSDStage.psd1" `
    -CatalogUri 'https://example.invalid/osdstage/catalog.json' `
    -RepositoryApp @('ExampleApp', 'ExampleScript') `
    -OfficeLanguage @('nl-nl', 'en-us') -IncludeTeams -Include7Zip
exit $LASTEXITCODE
```

To exercise the complete deployment with drivers and shutdown, add
`-WindowsUpdate -IncludeDrivers -FinalAction Shutdown` to that runner call.
Use `-FinalAction Reboot` for the restart case. The runner applies this setting
before any staging commands; the finalizer waits for Windows Setup and configured
cleanup to finish. See [Final action](../docs/runtime.md#final-action).

Replace the example IDs with your actual selection. Keep all repository IDs in
that one array. The runner owns the availability check; do not put an earlier
Add command in the calling wrapper.

A failed repository availability check leaves existing target staging files and
SetupComplete untouched. A later staging failure can leave earlier queue entries
and SetupComplete integration on the target. This wrapper does not roll them back or make the whole queue a
single transaction. Inspect the error and staged state before retrying or
rebooting; a manual reboot would bypass the launcher gate.

## With or without a USB flash drive

The same script uses the default optional `OSDCloud` cache. With a matching USB
flash drive, keep it connected until OOBE. Without one, built-in content is
acquired on the Windows volume at first boot. Keep networking available in
both online scenarios.

`OfflineReady=False` and `NetworkRequired=True` can be normal without cached
payloads. This online example deliberately does not require offline readiness.
The preflight does not prove future vendor connectivity, product activation or
installation success. After SetupComplete, inspect the recorded deployment
results; exit code `0` here means **staged**, not **installed**.

The README quick start stays minimal. This separate wrapper supplies the error
handling and process contract needed by a launcher without adding module cmdlets.
