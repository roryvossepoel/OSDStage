# Inspection and diagnostics

[Documentation](README.md) · [Getting started](getting-started.md) · [Maintenance](maintenance.md)

The Windows Viewer has been removed from development ahead of 1.0. Published RC4 packages retain their original contents. Current source uses the PowerShell commands below; no Windows Forms or STA session is needed for these inspection commands.

## Staging before reboot

In WinPE, inspect the prepared deployment after the Add commands finish:

```powershell
Test-OSDStageDeployment -ThrowOnFailure |
    Format-List Valid, OfflineReady, NetworkRequired, PackageCount, WindowsPath
```

This checks prepared state, not installation success. Use `-RequireOfflineReady` for a deliberately disconnected deployment. To read exact package order and settings, inspect `Windows/Temp/OSDStage/DeviceManifest.json` on the target Windows volume.

## Cache and available packages

```powershell
Get-OSDStage -Offline
Get-OSDStageCache | Format-List *
Get-OSDStageCacheHealth -Offline | Format-List *
```

These commands inspect state; the Add and Sync commands modify deployment or cache content. `Get-OSDStage -Offline` skips repository lookup, not deployment networking. On full Windows, opt in to supported signature and version inspection:

```powershell
Get-OSDStageCache -ResolveVersions -VerifySignatures |
    Select-Object Id, Version, Valid, SignatureStatus, SignatureScope
```

Cache validity and publisher trust are separate results. Certificate validation can need network access; Windows trust inspection is unavailable in WinPE. See [built-in acquisition](built-in-acquisition.md).

## Remove pending staging

In WinPE, preview removing a package from an existing offline target:

```powershell
Remove-OSDStageStaging -Name MicrosoftTeams -WindowsPath 'C:\' -WhatIf
```

Choose the actual target volume. This command removes pending staging, not installed software or USB cache. Full Windows requires `-TestMode` and uses only the existing isolated TEMP test folder.

## Logs and results

After SetupComplete, use [delivery reports](delivery-report.md), `Get-OSDStageDeploymentResult`, or the original JSON results. Default logs are under `%ProgramData%/OSDStage/Logs`; cache logs are under `OSDStage/Logs` on the cache volume. Custom paths can be set in session configuration. See [maintenance diagnostics](maintenance.md) for collection.

## Web catalog

The separate website catalog remains available under `site/catalog`. It browses built-ins and a user-supplied repository URL. It does not inspect local USB media, stage packages or execute PowerShell. See [GitHub Pages](github-pages.md).
