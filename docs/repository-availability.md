# Check repository selections before staging

[Documentation](README.md) · [Online staging](../Examples/WinPE-Online.md)

Available in current development; this command is not in the published RC4 package.

Run `Test-OSDStageRepositoryAvailability` **before the first Add command**, including built-in Add commands. It checks all requested repository IDs and declared aliases, selected package manifests and host-compatible architecture. It does not download installers, refresh cache, stage content or alter SetupComplete.

In a WinPE launcher after OSDCloud, import the tested development module and use the same repository selection for both checks and staging:

```powershell
$ErrorActionPreference = 'Stop'
$RepositoryIds = @('ExampleApp', 'ExampleScript') # Replace with IDs from your catalog.
Set-OSDStageConfiguration -CatalogUri 'https://example.invalid/osdstage/catalog.json'

Test-OSDStageRepositoryAvailability -Name $RepositoryIds -WindowsPath 'C:\' -ThrowOnFailure

Add-OSDStageGoogleChromeEnterprise -WindowsPath 'C:\'
Add-OSDStage -Name $RepositoryIds -WindowsPath 'C:\'
Test-OSDStageDeployment -WindowsPath 'C:\' -ThrowOnFailure
```

The first check prevents a missing final repository item from being discovered only after earlier built-ins have been staged. The final deployment check still validates the actual staged queue. Independent Add calls cannot know what a later script line will request; the preflight must receive the complete selection and run before those calls. This does not make arbitrary staging scripts transactional.

For cached-only staging, use `-SkipCacheRefresh` on both the availability check and repository Add calls. If no USB cache is found, an explicit `-WindowsPath` lets the check inspect the existing target-local `Windows\Temp\OSDStage\RepositoryCache`. It does not create that directory.

Without `-ThrowOnFailure`, inspect `Valid` and `Packages`. Each package contains its requested `Name`, resolved `Id`, `Available`, `Source`, `CatalogStatus`, `CatalogDetail` and `CacheDetail`. `PackageNotFound` distinguishes a missing ID from `CatalogUnavailable`; invalid manifests or incompatible variants report `CatalogPackageUnavailable` with the underlying reason.

If any catalog selection fails, **all** requested packages must be available in valid cache, matching the batch fallback of `Add-OSDStage -Name $RepositoryIds`. A mixed selection of an online-only package and a cache-only package therefore fails this conservative check. No stale or corrupted cache is accepted merely because the directory exists. A valid fallback is allowed even when the catalog is unreachable or no longer lists the package.

This is a point-in-time metadata and cache check. It does not prove that a later archive download will succeed, freeze a changing catalog, or validate future installer behavior. Built-in packages are outside this repository-only check and may still acquire their payloads during full-Windows PreInstall. Use `Test-OSDStageDeployment -RequireOfflineReady` after staging when the entire deployment must work offline.
