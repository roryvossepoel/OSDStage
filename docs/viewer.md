# OSDStage Inspector

[Documentation](README.md) · [Getting started](getting-started.md) · [Troubleshooting](faq.md)

OSDStage Inspector is opened by `Show-OSDStageUI`. Its deployment views are read-only: it displays what the PowerShell CLI has prepared and what is locally available, including the device queue and stored configuration, package availability, USB cache and existing logs. It does not configure, stage or install packages. The **Cache** tab additionally exposes explicit maintenance actions for the connected OSDStage cache.

<a id="two-different-viewers"></a>

## Inspector scope

| Viewer | Reads | Does not do |
| --- | --- | --- |
| Windows Viewer: `Show-OSDStageUI` | Local target queue, cache and logs; configured repository metadata | Configure or deploy packages |
| Web catalog viewer | Public built-in metadata and a user-entered schema 2 catalog URL; tiles/list and pagination | Inspect the local disk, USB cache or deployed Windows results |

The commands and tabs in the rest of this guide describe the **Windows Viewer**.
The web viewer is included in the static website under `site/catalog`. It is not
a module command. It has no prefilled organization repository or demo catalog.
See [GitHub Pages](github-pages.md) for building, reviewing and publishing the site.

## Where to run the Windows Viewer

| Environment | Target inspected | Notes |
| --- | --- | --- |
| Windows preparation machine | Connected USB cache, plus an existing target if supplied with `-WindowsPath` | Prepare and inspect deployment content. There is no need to install the Viewer on deployed devices. |
| WinPE | Discovered offline Windows installation, or an explicit `-WindowsPath` | Inspect after OSDCloud has applied Windows and the CLI has staged apps. Do not use `-TestMode`. |
| Full Windows with `-TestMode` | Existing `%TEMP%\OSDStage-GUI-Staging-Test` folder | Legacy isolated test-target inspection. The Viewer does not create the folder or stage sample apps. |

Use an STA PowerShell session with Windows Forms available. The WinPE image also needs PowerShell and .NET support. Windows 11 and two x64 WinPE devices were exercised during 0.34.0 validation; those tests do not establish compatibility with every WinPE image or architecture.

## Open the Viewer

**Windows preparation machine, with OSDStage installed:** start Windows PowerShell in STA if needed, then import the module inside that session.

```powershell
powershell.exe -STA -NoProfile
```

In the new PowerShell session:

```powershell
Import-Module OSDStage
Show-OSDStageUI -Offline
```

**WinPE:** use the module import in the [online](../Examples/WinPE-Online.md) or [offline](../Examples/WinPE-Offline.md) staging example, then run:

```powershell
Show-OSDStageUI -Offline
```

To inspect a particular Windows root, supply that root, not its `Windows` subdirectory:

```powershell
# Replace D:\ with the prepared Windows volume you intend to inspect.
Show-OSDStageUI -WindowsPath 'D:\' -Offline
```

For online repository discovery, set your actual `CatalogUri` through `Set-OSDStageConfiguration` in the same session and omit `-Offline`. The repository URL cannot be edited in the Viewer.

<a id="screenshots-from-winpe"></a>

## Historical screenshots

The earlier WinPE screenshots show the previous OSDApps name, paths and package
selection. They are preserved unmodified in the [historical screenshot archive](history/viewer-screenshots.md),
not presented as screenshots of the current OSDStage interface. Updated captures
must come from an actual run of the current module.

## Header and navigation

The compact context row shows **Target | USB | Offline/Online**. Its tooltip provides fuller target, cache and catalog context. `Offline` describes repository lookup behavior, not the machine's actual network connection.

Search filters displayed rows. Clicking a column header sorts the current view; it does not change `DeviceManifest.json` or installation order. Refresh re-reads the target and re-detects the connected OSDStage cache. Potentially slow maintenance actions run with a progress window so the Inspector remains responsive.

## Staged for device

This tab reads the selected target's `DeviceManifest.json` and shows the manifest order, Display Name, Source, Package Type, Vendor, version policy, cached version and architecture. The detail pane shows the selected app's actual staged settings, not settings reconstructed from defaults.

The Order column remains the manifest sequence even when the table is sorted differently. The detail pane is populated on initial load when entries are available.

**Staged does not mean installed.** `SetupComplete.cmd: Present` reports file presence, not evidence that SetupComplete or every installer has completed. An empty queue can mean no apps were staged, the wrong target was selected, or successful cleanup removed staging. Use runtime logs to establish the installation outcome.

## Cache manager

The Cache manager combines package discovery and cache inventory into one app-oriented view. Each logical app is shown once. When an app has multiple cached configurations, such as Firefox channels or runtime variants, the main row summarizes them and the detail pane shows the individual configurations.

| Column | Meaning |
| --- | --- |
| App | Human-readable app/package name. |
| Source | Built-in or Repository. |
| Package Type | `App`, `Script`, `Font`, `Certificate` or `Driver`. |
| Vendor | Publisher metadata when available; the Inspector does not invent one. |
| Cached version | Exact version for a single cached configuration, or a configuration count when multiple variants exist. |
| Available version | Version resolved by the update check. Multiple configurations are summarized and expanded in the detail pane. |
| Status | `Current`, `Update available`, `Check failed`, `Not cached`, `Catalog not configured`, or another explicit state. |

Checkboxes are temporary action selection only. Unchecking an app never removes it. New built-in cache configurations remain CLI-only: the Cache manager does not choose architecture, channel, language, runtime type or Office settings.

### Cache maintenance

- **Refresh** re-reads device, cache and signature state. Use it after inserting, removing or replacing an OSDCloud USB device.
- **Check health** runs `Get-OSDStageCacheHealth` and shows concrete non-healthy entries with state, integrity, recommended action, size, reason and path.
- **Check updates** checks the selected apps; with no checked rows it checks every cached app. Existing exact version resolvers are used for Office, Chrome, Firefox, 7-Zip, Visual Studio Code, Visual C++ runtimes, .NET runtimes and CMTrace Open. Other vendor payloads are still checked against their recorded remote metadata instead of being silently skipped.
- **Cache selected** can add uncached repository apps when a catalog is configured. New built-in configurations must be created with the PowerShell CLI.
- **Update selected** rechecks and updates only the checked apps that are actually out of date.
- **Update all available** rechecks the cache and synchronizes only entries explicitly identified as having an update. Current entries are not intentionally reacquired.
- **Remove selected...** removes only checked cached apps after an explicit confirmation.
- **Clear entire cache...** is a separate destructive action with its own confirmation. Logs are preserved.

Maintenance actions do not stage packages or change the device deployment manifest.

### Cached configurations

The main table intentionally hides technical variant rows. Select an app to inspect its cached configurations in the detail pane, including architecture, channel, runtime type or language where recorded, cached version, available version, update result and cache path.

### Versions

On full Windows, the Viewer requests `Get-OSDStageCache -ResolveVersions` to inspect existing valid content without updating cache metadata. MSI packages can provide ProductVersion; Adobe's ZIP can provide the included patch build through `setup.ini`. Office and Teams use their recorded cache metadata. The Adobe version is a patch build, not necessarily the base MSI version.

WinPE relies on saved metadata rather than the full-Windows MSI inspection path. `Not recorded` means there is no usable specific version to display; it does not by itself mean the package is missing. A cached version is never presented as an independently verified installed version.

### Integrity and signature are different checks

| Status | What was checked |
| --- | --- |
| Integrity: `Files present` | Required built-in files/directories exist. This is not a full cryptographic check. |
| Integrity: `SHA-256 verified` | A repository ZIP matches the hash in its package metadata. |
| Signature: `Signature valid` | The supported MSI/EXE passed Windows Authenticode trust and the expected built-in publisher check. |
| Signature: `Not assessed` | The format is outside this Authenticode inspection path, such as Adobe's outer ZIP. |
| Signature: `N/A` | Repository ZIP signature inspection does not apply; see its separate SHA-256 result. |
| Signature: `Unavailable in WinPE` | OSDStage did not invoke Windows signature verification in WinPE. |
| Signature: `Not checked` | Signature inspection was deliberately skipped or no check result was requested. |

Invalid, untrusted or unexpected-publisher results must not be interpreted as valid content. The CLI's entry-level `Valid` property describes app-specific local checks: file presence for some built-ins, generation consistency for Office, and hash/metadata checks for repository packages and several newer built-ins. The Viewer's compact integrity label does not enumerate every underlying check. Inspect `SignatureStatus` separately and see [what a cache check proves](maintenance.md#what-a-cache-check-proves) for the per-app scope. None of these local results establishes vendor freshness.

### Default signature inspection and network behavior

The Viewer checks supported built-in MSI/EXE signatures by default on full Windows. The public CLI keeps explicit opt-in inspection:

```powershell
Get-OSDStageCache -ResolveVersions -VerifySignatures |
    Select-Object Id, Version, Valid, SignatureStatus, SignatureScope, SignatureSigner
```

Office inspection covers **setup.exe only**; Teams covers **teamsbootstrapper.exe only**. It does not verify the Office data tree or Teams MSIX. Adobe's outer ZIP remains outside the supported Authenticode scope. See the [publisher policy](built-in-acquisition.md#authenticode-and-publisher-policy-0340).

`-Offline` disables repository lookup, but Windows trust/revocation evaluation may still use the network. To suppress both catalog lookup and signature inspection by the Viewer:

```powershell
Show-OSDStageUI -Offline -SkipSignatureVerification
```

This affects **viewing only**. It does not disable the signer policy enforced by built-in synchronization or SetupComplete, and it does not disconnect network adapters.

## Logs

Logs reads up to 500 recent lines from a selected existing log and presents Timestamp, Level, Component, Event and Message. Select a row to see the full parsed details; long table values may be truncated at smaller window sizes. The row tooltip retains raw log text.

The Viewer discovers known USB/device log locations. A custom runtime `LogPath` may need to be opened separately with PowerShell or a log reader. It does not create a missing log or make a new deployment log before SetupComplete has run.

See [Runtime and cleanup](runtime.md#logging) for paths and event meanings. `PreInstallComplete`, individual exit codes and `InstallComplete` are the installation evidence; the Packages/Staged tabs are not installed-software inventory.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Viewer cannot open in WinPE | Confirm PowerShell, .NET, Windows Forms and an STA session are available. |
| No repository listed | Configure `CatalogUri` in the same session, or deliberately use the local-only `-Offline` view. |
| No staged apps | Confirm target/manifest, whether staging was performed, and whether OnSuccess cleanup already ran. |
| USB not found | Check the volume label, drive visibility and `CacheVolumeLabel`; do not assume the same drive letter on each machine. |
| Signature trust failed | Inspect status, signer, clock and Windows trust/revocation availability; do not bypass deployment policy merely to make the Viewer green. |
| Refresh is slow | It can re-read files, compute repository hashes, inspect versions and evaluate signatures. |

To capture a Viewer exception without changing deployment state:

```powershell
try { Show-OSDStageUI -Offline -ErrorAction Stop }
catch { $_ | Format-List * -Force; $_.ScriptStackTrace }
```

[Back to documentation](README.md)
