# Run with powershell.exe -NoProfile -File from the launcher's WinPE process.
# Exit 0 permits the launcher to continue; exit 1 must block its reboot path.
[CmdletBinding()]
param(
    [string]$ModulePath,
    [uri]$CatalogUri,
    [string[]]$RepositoryApp = @(),
    [string]$WindowsPath,
    [switch]$SkipCacheRefresh,
    [string[]]$OfficeLanguage = @('en-us'),
    [switch]$IncludeTeams,
    [switch]$Include7Zip,
    [switch]$WindowsUpdate,
    [switch]$IncludeDrivers,
    [ValidateSet('None','Reboot','Shutdown')]
    [string]$FinalAction = 'None'
)

$ErrorActionPreference = 'Stop'

try {
    if ($IncludeDrivers -and -not $WindowsUpdate) {
        throw 'IncludeDrivers requires WindowsUpdate.'
    }
    if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) {
        throw 'Run this example in WinPE after Windows has been applied.'
    }

    if ($ModulePath) {
        if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) {
            throw "OSDStage module not found: $ModulePath"
        }
        Import-Module -Name $ModulePath -Force
    }
    else {
        Install-Module OSDStage -Force -SkipPublisherCheck
        Import-Module OSDStage -Force
    }

    $destination = @{}
    if ($WindowsPath) { $destination.WindowsPath = $WindowsPath }
    # Declare the repository selection once. Both preflight and staging use it;
    # a final unavailable repository app must block even the first built-in.
    $repositoryIds = @($RepositoryApp | Select-Object -Unique)
    $configuration = @{ FinalAction = $FinalAction }
    if ($CatalogUri) { $configuration.CatalogUri = $CatalogUri }
    if ($repositoryIds.Count -gt 0) {
        $configuration.EnableRepository = $true
        $configuration.EnableBuiltIns = $true
    }
    if ($configuration.Count -gt 0) { Set-OSDStageConfiguration @configuration }

    if ($repositoryIds.Count -gt 0) {
        Test-OSDStageRepositoryAvailability -Name $repositoryIds @destination `
            -SkipCacheRefresh:$SkipCacheRefresh -ThrowOnFailure | Out-Host
    }

    # Edit this queue for your deployment. These three apps default to x64.
    Add-OSDStageMicrosoft365Apps -Channel MonthlyEnterprise -Language $OfficeLanguage @destination | Out-Host
    if ($IncludeTeams) { Add-OSDStageMicrosoftTeams @destination | Out-Host }
    Add-OSDStageAdobeAcrobatUnified @destination | Out-Host
    Add-OSDStageGoogleChromeEnterprise @destination | Out-Host
    if ($Include7Zip) { Add-OSDStage7Zip @destination | Out-Host }

    if ($repositoryIds.Count -gt 0) {
        Add-OSDStage -Name $repositoryIds @destination -SkipCacheRefresh:$SkipCacheRefresh | Out-Host
    }
    if ($WindowsUpdate) { Add-OSDStageWindowsUpdate -IncludeDrivers:$IncludeDrivers -TimeoutMinutes 60 @destination | Out-Host }

    $validation = Test-OSDStageDeployment @destination -ThrowOnFailure
    $validation | Select-Object WindowsPath, DeploymentId, PackageCount,
        Valid, OfflineReady, NetworkRequired | Format-List | Out-Host

    Write-Host 'OSDStage staging passed. The launcher may continue to its reboot step.'
    exit 0
}
catch {
    Write-Error "OSDStage staging failed. Do not reboot: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
