. (Join-Path $PSScriptRoot 'OSDStagePayloadFile.ps1')
# Shared by the module and standalone PreInstall. No deployment is started here.
function Restore-OSDStageCacheGeneration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][scriptblock]$Validate
    )

    $parent = Split-Path -Path $Root -Parent
    $leaf = Split-Path -Path $Root -Leaf
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { return }

    $oldPattern = '^' + [regex]::Escape($leaf) + '\.osdstage-old-[0-9a-f]{32}$'
    $newPattern = '^' + [regex]::Escape($leaf) + '\.osdstage-new-[0-9a-f]{32}$'
    $children = @(Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction Stop)
    $backups = @($children | Where-Object { $_.Name -match $oldPattern })
    $candidates = @($children | Where-Object { $_.Name -match $newPattern })

    function Test-RecoveryGeneration {
        param([Parameter(Mandatory)][string]$Path)
        try {
            $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Recovery does not follow directory links.' }
            $links = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction Stop | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
            if ($links.Count -gt 0) { throw 'Recovery generation contains a file or directory link.' }
            & $Validate $Path | Out-Null
            return $true
        }
        catch {
            Write-Verbose "Recovery validation rejected '$Path': $($_.Exception.Message)"
            return $false
        }
    }

    function Remove-TransactionDirectory {
        param([Parameter(Mandatory)][string]$Path)
        if (Test-Path -LiteralPath $Path -PathType Container) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            Write-Verbose "Removed completed or abandoned OSDStage cache transaction directory '$Path'."
            return 1
        }
        return 0
    }

    if (Test-Path -LiteralPath $Root -PathType Container) {
        $activeValid = Test-RecoveryGeneration -Path $Root
        if ($activeValid) {
            $removed = 0
            foreach ($item in @($backups) + @($candidates)) { $removed += Remove-TransactionDirectory -Path $item.FullName }
            if ($removed -gt 0) { return [pscustomobject]@{Root=$Root;Recovered=$false;ResidueRemoved=$removed;ActiveValidated=$true} }
            return
        }

        $validBackups = @($backups | Where-Object { Test-RecoveryGeneration -Path $_.FullName })
        if ($validBackups.Count -gt 1) {
            throw "Cache recovery for '$Root' is ambiguous: found $($validBackups.Count) valid previous generations. Transaction directories were preserved."
        }
        if ($validBackups.Count -eq 1) {
            $quarantine = "$Root.osdstage-bad-$([guid]::NewGuid().ToString('N'))"
            Move-Item -LiteralPath $Root -Destination $quarantine -ErrorAction Stop
            try {
                Move-Item -LiteralPath $validBackups[0].FullName -Destination $Root -ErrorAction Stop
                if (-not (Test-RecoveryGeneration -Path $Root)) { throw 'Restored previous generation failed validation.' }
                Remove-Item -LiteralPath $quarantine -Recurse -Force -ErrorAction Stop
                $removed = 0
                foreach ($item in @($backups | Where-Object FullName -ne $validBackups[0].FullName) + @($candidates)) { $removed += Remove-TransactionDirectory -Path $item.FullName }
                return [pscustomobject]@{Root=$Root;PreviousPath=$validBackups[0].FullName;Recovered=$true;ResidueRemoved=$removed;ActiveValidated=$true}
            }
            catch {
                $restoreError = $_
                if (-not (Test-Path -LiteralPath $Root) -and (Test-Path -LiteralPath $quarantine)) { Move-Item -LiteralPath $quarantine -Destination $Root -ErrorAction SilentlyContinue }
                throw $restoreError
            }
        }

        $removed = 0
        foreach ($item in $candidates) { $removed += Remove-TransactionDirectory -Path $item.FullName }
        if ($removed -gt 0) { return [pscustomobject]@{Root=$Root;Recovered=$false;ResidueRemoved=$removed;ActiveValidated=$false} }
        return
    }

    $validBackups = @($backups | Where-Object { Test-RecoveryGeneration -Path $_.FullName })
    if ($validBackups.Count -gt 1) {
        throw "Cache recovery requires an unambiguous previous generation for '$Root'; found $($validBackups.Count) valid generations. Transaction directories were preserved."
    }
    if ($validBackups.Count -eq 1) {
        $source = $validBackups[0].FullName
        Move-Item -LiteralPath $source -Destination $Root -ErrorAction Stop
        $removed = 0
        foreach ($item in @($backups | Where-Object FullName -ne $source) + @($candidates)) { $removed += Remove-TransactionDirectory -Path $item.FullName }
        return [pscustomobject]@{Root=$Root;PreviousPath=$source;Recovered=$true;ResidueRemoved=$removed;ActiveValidated=$true}
    }

    $removed = 0
    foreach ($item in $candidates) { $removed += Remove-TransactionDirectory -Path $item.FullName }
    if ($removed -gt 0) { return [pscustomobject]@{Root=$Root;Recovered=$false;ResidueRemoved=$removed;ActiveValidated=$false} }
}

function Assert-OSDStageRecoverableBuiltInGeneration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidateSet('Microsoft365Apps','MicrosoftTeams','GoogleChromeEnterprise','MozillaFirefoxEnterprise','CiscoWebex','ZoomWorkplace','AdobeAcrobatUnified')][string]$Id,
        [Parameter(Mandatory)][scriptblock]$SignatureValidator,
        [Parameter(Mandatory)][scriptblock]$OfficeValidator,
        [Parameter(Mandatory)][scriptblock]$TeamsVersionReader
    )

    $info = Get-Content -LiteralPath (Join-Path $Root 'CacheInfo.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([string]$info.Id -ne $Id -or $info.Cached -ne $true) {
        throw "Recovery metadata does not describe a cached '$Id' generation."
    }
    $payloadPath = $null
    if ($Id -ne 'Microsoft365Apps') {
        $extension = if ($Id -eq 'MicrosoftTeams') { '.msix' } elseif ($Id -eq 'AdobeAcrobatUnified') { '.zip' } else { '.msi' }
        $payloadPath = Assert-OSDStageCachedPayload -Root $Root -ExpectedExtension $extension -Id $Id
    }
    $required = switch ($Id) {
        'Microsoft365Apps' { 'setup.exe'; 'configuration.xml' }
        'MicrosoftTeams' { 'teamsbootstrapper.exe'; [string]$info.PayloadFileName }
        default { [string]$info.PayloadFileName }
    }
    foreach ($file in $required) {
        $path = (Resolve-OSDStageBuiltInPayloadPath -Path (Join-Path $Root $file))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -le 0) {
            throw "Recovery generation '$Id' is missing nonempty '$file'."
        }
    }
    switch ($Id) {
        'Microsoft365Apps' {
            if ([string]$info.Version -notmatch '^\d+\.\d+\.\d+\.\d+$' -or [string]$info.Architecture -notin @('x86','x64')) {
                throw 'Office recovery metadata has no valid version or architecture.'
            }
            & $OfficeValidator $Root ([string]$info.Version) ([string]$info.Architecture) | Out-Null
            & $SignatureValidator $Id (Join-Path $Root 'setup.exe') | Out-Null
        }
        'MicrosoftTeams' {
            & $SignatureValidator $Id (Join-Path $Root 'teamsbootstrapper.exe') | Out-Null
            $version = & $TeamsVersionReader $payloadPath
            if (-not $version -or [string]$version -ne [string]$info.Version) {
                throw 'Teams recovery package version does not match its metadata.'
            }
        }
        'AdobeAcrobatUnified' {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            $archive = [IO.Compression.ZipFile]::OpenRead($payloadPath)
            try {
                if ($archive.Entries.Count -eq 0) { throw 'Adobe recovery archive is empty.' }
            }
            finally { $archive.Dispose() }
        }
        default { & $SignatureValidator $Id $payloadPath | Out-Null }
    }
}
