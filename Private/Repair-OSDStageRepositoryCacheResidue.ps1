function Repair-OSDStageRepositoryCacheResidue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CachePath,
        [string]$LogPath
    )

    $stagingRoot = Join-Path $CachePath '.staging'
    if (-not (Test-Path -LiteralPath $stagingRoot -PathType Container)) { return }
    $items = @(Get-ChildItem -LiteralPath $stagingRoot -Force -ErrorAction SilentlyContinue)
    $owned = @($items | Where-Object { $_.PSIsContainer -and $_.Name -match '^Sync-[0-9a-f]{32}$' })
    $unknown = @($items | Where-Object { -not ($_.PSIsContainer -and $_.Name -match '^Sync-[0-9a-f]{32}$') })

    foreach ($item in $unknown) {
        $message = "Unrecognized cache staging content was left untouched: $($item.FullName)"
        Write-Warning $message
        if ($LogPath) { Write-OSDStageLog -LogPath $LogPath -Component 'CacheHealth' -Event 'CacheAdvisory' -Level 'Warning' -Message $message -Data @{Path=$item.FullName} }
    }
    if ($owned.Count -eq 0) { return }

    $packagesRoot = Join-Path $CachePath 'Packages'
    $catalogPath = Join-Path $CachePath 'CacheCatalog.json'
    $activeConsistent = $false
    $reason = $null
    try {
        if (Test-Path -LiteralPath $catalogPath -PathType Leaf) {
            $catalog = Get-OSDStageManifest -Path $catalogPath
            if (-not ($catalog.PSObject.Properties.Name -contains 'Packages')) { throw 'CacheCatalog.json is missing Packages.' }
            foreach ($package in @($catalog.Packages)) {
                $id = [string]$package.Id
                if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $id -match '\.\.') { throw "CacheCatalog.json contains invalid package Id '$id'." }
                $sha = [string]$package.Payload.Sha256
                if ($sha -notmatch '^[A-Fa-f0-9]{64}$') { throw "CacheCatalog.json package '$id' has invalid SHA-256 metadata." }
                $archive = Join-Path $packagesRoot (Join-Path $id 'Package.zip')
                if (-not (Test-OSDStageFileHash -Path $archive -ExpectedSha256 $sha)) { throw "Cached repository package '$id' is missing or does not match CacheCatalog.json." }
            }
            $activeConsistent = $true
        }
        else {
            $physicalPackages = if (Test-Path -LiteralPath $packagesRoot -PathType Container) { @(Get-ChildItem -LiteralPath $packagesRoot -Directory -Force -ErrorAction SilentlyContinue) } else { @() }
            $activeConsistent = $physicalPackages.Count -eq 0
            if (-not $activeConsistent) { $reason = 'Repository package folders exist without CacheCatalog.json.' }
        }
    }
    catch { $reason = $_.Exception.Message; $activeConsistent = $false }

    if (-not $activeConsistent) {
        $message = "OSDStage transaction residue was preserved because the active repository cache could not be proven consistent$(if ($reason) { ': ' + $reason } else { '.' })"
        Write-Warning $message
        if ($LogPath) { Write-OSDStageLog -LogPath $LogPath -Component 'CacheHealth' -Event 'CacheRecoveryPreserved' -Level 'Warning' -Message $message -Data @{CachePath=$CachePath} }
        return
    }

    $removed = 0
    foreach ($directory in $owned) { Remove-Item -LiteralPath $directory.FullName -Recurse -Force -ErrorAction Stop; $removed++ }
    if ($removed -gt 0 -and $LogPath) { Write-OSDStageLog -LogPath $LogPath -Component 'CacheHealth' -Event 'CacheTransactionResidueRemoved' -Message 'Removed stale OSDStage repository transaction directories after validating the active cache.' -Data @{Count=$removed;StagingRoot=$stagingRoot} }
    [pscustomobject]@{CachePath=$CachePath;RemovedCount=$removed;AdvisoryCount=$unknown.Count}
}
