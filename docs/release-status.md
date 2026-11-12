# Release availability

[Documentation](README.md) · [Getting started](getting-started.md) · [Changelog](../CHANGELOG.md)

**OSDStage 1.0.0 — stable release.** The module and website Configuration Builders
have separate release scopes. Builders remain a preview and are not included in
the PowerShell module package.

Exact version links: [PowerShell Gallery](https://www.powershellgallery.com/packages/OSDStage/1.0.0) ·
[GitHub release](https://github.com/roryvossepoel/OSDStage/releases/tag/v1.0.0).
Publication is performed by the [release workflow](https://github.com/roryvossepoel/OSDStage/actions/workflows/release.yml)
and [Gallery publish/verification workflow](https://github.com/roryvossepoel/OSDStage/actions/workflows/publish.yml).
A merge alone does not publish a package; the publish workflow verifies the
exact downloaded Gallery package against the tagged build using SHA-256.

## Included in 1.0.0

- Built-in apps, schema 2 repository packages and device configuration.
- Automatic content acquisition, optional USB caching and validated offline fallback.
- Repository availability checks before multi-package staging and conservative built-in cache recovery.
- JSON/HTML delivery reports with app display names, payload versions, readable tables and component evidence.
- One final Windows Update pass, including opt-in drivers and firmware.
- Optional `FinalAction None`, `Reboot` or `Shutdown`. Default is `None`; a power request happens only after successful completion, process exit, cleanup and report writes. Failed or incomplete deployments suppress it.

The Windows Viewer and deployment-profile experiments are excluded. Use
PowerShell commands for staging and configuration, and delivery reports for results.

## Install or upgrade

On full Windows or online WinPE with PowerShellGet:

```powershell
Install-Module OSDStage -Repository PSGallery -RequiredVersion '1.0.0' -Force -ErrorAction Stop
Import-Module OSDStage -RequiredVersion '1.0.0' -Force
Get-Module OSDStage | Select-Object Name, Version, Path,
    @{Name='Prerelease';Expression={$_.PrivateData.PSData.Prerelease}}
```

The loaded version should be `1.0.0` with an empty prerelease label. Stable
installation does not require `-AllowPrerelease`. RC1 through RC4 share the
numeric `1.0.0` module folder: close sessions using the old module before upgrading,
then install and verify in a fresh session. Existing schema 2 catalogs and cache
paths are retained. GitHub RC tags and their Gallery packages remain unchanged.

## Acceptance and limits

The [published RC4 acceptance](rc4-gallery-acceptance.md) covers the Gallery-to-WinPE
route on two physical x64 devices. The [broad component acceptance](delivery-report.md#broad-component-acceptance-3-november-2026)
records 19 successful packages, 36 installed updates and 18 passing report checks.

The [12 November combined source-build acceptance](testing.md#combined-10-preparation-acceptance--12-november-2026)
covers the runtime changes included in stable 1.0.0: two x64 Dell deployments,
7/7 successful packages on each, 39/39 installed updates on each, warm-cache
reuse, report checks, cleanup and maintainer-confirmed automatic restart/shutdown.
The separate [PC2 validation](testing.md#pc2-windows-update-and-firmware-validation--12-november-2026)
records November Windows cumulative servicing and post-restart BIOS evidence.
These records retain their original tested version/commit; they are not relabeled
as deployments of the final Gallery package.

ARM64, separate .NET cumulative servicing and the additional variants in the
[validation register](feature-status.md) remain outside recorded physical coverage.
A completed update pass does not guarantee that a later scan offers no more updates.
Reports captured before reboot can show the previous active Windows revision.
