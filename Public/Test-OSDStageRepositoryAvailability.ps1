function Test-OSDStageRepositoryAvailability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Id')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,
        [string]$WindowsPath,
        [switch]$SkipCacheRefresh,
        [switch]$ThrowOnFailure
    )

    Assert-OSDStageSourceEnabled -Source Repository
    $names = @($Name | Select-Object -Unique)
    foreach ($item in $names) {
        if ($item -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $item -match '\.\.') {
            throw "Invalid repository app Id '$item'."
        }
    }

    $architecture = Get-OSDStageHostArchitecture
    $sourceUri = (Get-OSDStageConfiguration).CatalogUri
    $cachePath = $null
    try { $cachePath = Get-OSDStageCachePath }
    catch { Write-Verbose "USB cache unavailable: $($_.Exception.Message)" }
    if (-not $cachePath -and $WindowsPath) {
        $target = Resolve-OSDStageWindowsPath -WindowsPath $WindowsPath
        $cachePath = Join-Path $target 'Windows\Temp\OSDStage\RepositoryCache'
    }

    $catalog = $null
    $catalogStatus = 'NotConfigured'
    $catalogError = $null
    if ($SkipCacheRefresh) { $catalogStatus = 'Skipped' }
    elseif ($sourceUri) {
        try {
            $catalog = Get-OSDStageManifest -Uri $sourceUri -ErrorAction Stop
            $catalogStatus = 'Available'
        }
        catch {
            $catalogStatus = 'CatalogUnavailable'
            $catalogError = $_.Exception.Message
        }
    }

    $checks = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $names) {
        $id = $item
        $status = $catalogStatus
        $detail = $catalogError
        $catalogAvailable = $false
        if ($catalogStatus -eq 'Available') {
            try {
                $resolved = Get-OSDStageCatalogPackages -CatalogUri $sourceUri -Catalog $catalog -Name $item -ErrorAction Stop
                $variants = @(Resolve-OSDStageCatalogPackageVariant -Package @($resolved.Packages) -Architecture $architecture -ErrorAction Stop)
                if ($variants.Count -ne 1) { throw 'Expected exactly one compatible repository package.' }
                $id = [string]$variants[0].Id
                $catalogAvailable = $true
                $status = 'Available'
                $detail = 'Compatible package metadata is available; archive download has not been tested.'
            }
            catch {
                $status = if ($_.Exception.Data.Contains('OSDStageAvailabilityStatus')) {
                    [string]$_.Exception.Data['OSDStageAvailabilityStatus']
                } else { 'CatalogPackageUnavailable' }
                $detail = $_.Exception.Message
            }
        }
        $checks.Add([pscustomobject]@{
            Name = $item
            Id = $id
            Available = $catalogAvailable
            Source = if ($catalogAvailable) { 'Catalog' } else { 'None' }
            CatalogStatus = $status
            CatalogDetail = $detail
            CacheDetail = $null
        })
    }

    # Add-OSDStage synchronizes a selection as one transaction. If any online
    # entry fails, its offline fallback must contain EVERY requested package.
    $needsFallback = @($checks | Where-Object { -not $_.Available }).Count -gt 0
    if ($needsFallback) {
        foreach ($check in $checks) {
            $check.Available = $false
            $check.Source = 'None'
            try {
                if (-not $cachePath) { throw 'No cache volume or explicit WindowsPath is available.' }
                $ids = @(Resolve-OSDStageCachedPackageId -CachePath $cachePath -Name $check.Name -ErrorAction Stop)
                if ($ids.Count -ne 1 -or $ids[0] -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $ids[0] -match '\.\.') {
                    throw 'Cached identity is invalid or ambiguous.'
                }
                $cached = @(Test-OSDStageRepositoryCache -CachePath $cachePath -Name $ids[0] -ErrorAction Stop)
                if ($cached.Count -ne 1 -or -not $cached[0].Valid) {
                    throw 'No unique SHA-256 validated archive is available.'
                }
                Resolve-OSDStageCatalogPackageVariant -Package $cached -Architecture $architecture -ErrorAction Stop | Out-Null
                $check.Id = [string]$ids[0]
                $check.Available = $true
                $check.Source = 'Cache'
                $check.CacheDetail = 'Compatible cached archive passed repository integrity checks.'
            }
            catch { $check.CacheDetail = $_.Exception.Message }
        }
    }

    $failed = @($checks | Where-Object { -not $_.Available })
    $result = [pscustomobject]@{
        PSTypeName = 'OSDStage.RepositoryAvailability'
        Valid = ($failed.Count -eq 0)
        Architecture = $architecture
        CatalogStatus = $catalogStatus
        CatalogError = $catalogError
        CachePath = $cachePath
        UsesCacheFallback = $needsFallback
        Packages = @($checks)
    }
    if ($ThrowOnFailure -and -not $result.Valid) {
        $reasons = @($failed | ForEach-Object { "[$($_.Name)] catalog: $($_.CatalogStatus) $($_.CatalogDetail); cache: $($_.CacheDetail)" })
        throw "Repository availability check failed before staging: $($reasons -join ' | ')"
    }
    $result
}
