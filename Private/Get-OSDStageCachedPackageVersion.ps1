function Get-OSDStageCachedPackageVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$CacheEntryPath,
        [string]$PayloadPath
    )

    $version = $null
    $source = $null
    switch ($Id) {
        { $_ -in @('GoogleChromeEnterprise','CiscoWebex','ZoomWorkplace','MozillaFirefoxEnterprise') } {
            $path = if ($PayloadPath) { $PayloadPath } else { Resolve-OSDStageBuiltInPayloadPath -Root $CacheEntryPath -ExpectedExtension '.msi' }
            $version = Get-OSDStageMsiProductVersion -Path $path
            if ($version) { $source = 'MsiProductVersion' }
            break
        }
        'AdobeAcrobatUnified' {
            $path = if ($PayloadPath) { $PayloadPath } else { Resolve-OSDStageBuiltInPayloadPath -Root $CacheEntryPath -ExpectedExtension '.zip' }
            $version = Get-OSDStageAdobePatchVersion -Path $path
            if ($version) { $source = 'AdobePatchFileName' }
            break
        }
    }

    [pscustomobject]@{
        Version = if ($version) { ([string]$version).Trim() } else { $null }
        VersionSource = $source
    }
}
