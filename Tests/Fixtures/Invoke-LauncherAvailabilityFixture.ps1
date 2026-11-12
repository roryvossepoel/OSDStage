param(
    [string]$ModulePath,
    [string]$RunnerPath,
    [string]$Scenario,
    [string]$Target,
    [string]$Cache,
    [string]$Trace
)
$ErrorActionPreference = 'Stop'
$loaded = Import-Module $ModulePath -Force -PassThru
$global:LauncherFixture = @{
    ModulePath = $ModulePath; Target = $Target; Trace = $Trace; Scenario = $Scenario
}

# Only environmental dependencies are replaced. The runner, availability API,
# catalog/alias resolution and cached archive integrity checks are real.
& $loaded {
    param($Mode, $CacheRoot)
    $script:LauncherFixtureMode = $Mode
    $script:LauncherFixtureCache = $CacheRoot
    function script:Get-OSDStageHostArchitecture { 'x64' }
    function script:Get-OSDStageCachePath { $script:LauncherFixtureCache }
    function script:Get-OSDStageManifest {
        [CmdletBinding()]
        param([uri]$Uri, [string]$Path)
        if ($Uri) {
            if ($script:LauncherFixtureMode -in @('Offline', 'Corrupt')) {
                throw 'Fixture catalog is unreachable.'
            }
            if ($script:LauncherFixtureMode -eq 'SkipCache') {
                throw 'SkipCacheRefresh must not request catalog metadata.'
            }
            if ($Uri.AbsoluteUri.EndsWith('/catalog.json')) {
                return [pscustomobject]@{
                    SchemaVersion = 2
                    Packages = @([pscustomobject]@{
                        Id = 'Fixture'; Aliases = @('OldFixture')
                        Architectures = @([pscustomobject]@{
                            Architecture = 'x64'; Manifest = 'Fixture/manifest.json'
                        })
                    })
                }
            }
            return [pscustomobject]@{
                SchemaVersion = 2; Id = 'Fixture'; Version = '1.0'; Architecture = 'x64'
                Payload = [pscustomobject]@{ FileName = 'Package.zip'; Sha256 = ('a' * 64) }
            }
        }
        Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json
    }
} $Scenario $Cache

if ($Scenario -in @('Offline', 'Corrupt', 'SkipCache')) {
    $folder = Join-Path $Cache 'Packages/Fixture'
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $archive = Join-Path $folder 'Package.zip'
    Set-Content -LiteralPath $archive -Value 'verified archive fixture'
    [pscustomobject]@{
        Packages = @([pscustomobject]@{
            Id = 'Fixture'; Aliases = @('OldFixture'); Architecture = 'x64'; Version = '1.0'
            Payload = @{ Sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash }
        })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Cache 'CacheCatalog.json')
    if ($Scenario -eq 'Corrupt') { Set-Content -LiteralPath $archive -Value 'tampered' }
}

function Test-Path {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(ParameterSetName = 'Literal')][string[]]$LiteralPath,
        [Parameter(Position = 0, ParameterSetName = 'Path')][string[]]$Path,
        [Microsoft.PowerShell.Commands.TestPathType]$PathType = 'Any'
    )
    if ($LiteralPath -eq 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { return $true }
    Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
}
function Import-Module {
    param([string]$Name, [switch]$Force)
    if ($Name -ne $global:LauncherFixture.ModulePath -or -not $Force) { throw 'Unexpected module import.' }
    # Keep the loaded real module and its isolated environment dependencies.
}
function Install-Module { throw 'Pinned launcher test must not install from Gallery.' }

function Invoke-FixtureStage {
    param([string]$Step, [string]$WindowsPath)
    if ($WindowsPath -ne $global:LauncherFixture.Target) { throw 'Wrong target Windows path.' }
    $expectedAction = switch ($global:LauncherFixture.Scenario) {
        'FinalReboot' { 'Reboot' }
        'FinalShutdown' { 'Shutdown' }
        default { 'None' }
    }
    if ((Get-OSDStageConfiguration).FinalAction -ne $expectedAction) {
        throw 'FinalAction must be configured before the first Add command.'
    }
    Add-Content -LiteralPath $global:LauncherFixture.Trace -Value $Step
    $stage = Join-Path $WindowsPath 'Windows/Temp/OSDStage'
    $setup = Join-Path $WindowsPath 'Windows/Setup/Scripts'
    New-Item -ItemType Directory -Path $stage, $setup -Force | Out-Null
    Add-Content -LiteralPath (Join-Path $stage 'staged.txt') -Value $Step
    Add-Content -LiteralPath (Join-Path $setup 'SetupComplete.cmd') -Value $Step
}
function Add-OSDStageMicrosoft365Apps {
    param($Channel, [string[]]$Language, $WindowsPath)
    if ($Channel -ne 'MonthlyEnterprise' -or ($Language -join ',') -ne 'nl-nl,en-us') {
        throw 'Office test selection changed.'
    }
    Invoke-FixtureStage Office $WindowsPath
}
function Add-OSDStageMicrosoftTeams { param($WindowsPath) Invoke-FixtureStage Teams $WindowsPath }
function Add-OSDStageAdobeAcrobatUnified { param($WindowsPath) Invoke-FixtureStage Adobe $WindowsPath }
function Add-OSDStageGoogleChromeEnterprise { param($WindowsPath) Invoke-FixtureStage Chrome $WindowsPath }
function Add-OSDStage7Zip { param($WindowsPath) Invoke-FixtureStage 7Zip $WindowsPath }
function Add-OSDStage {
    param([string[]]$Name, $WindowsPath, [switch]$SkipCacheRefresh)
    if ($Name -contains 'NotepadPlusPlus') { throw 'Repository package NotepadPlusPlus is unavailable.' }
    if (($Name -join ',') -ne 'OldFixture') { throw 'Repository staging selection differs from preflight.' }
    if ([bool]$SkipCacheRefresh -ne ($global:LauncherFixture.Scenario -eq 'SkipCache')) { throw 'Cache mode differs from preflight.' }
    Invoke-FixtureStage Repository $WindowsPath
}
function Add-OSDStageWindowsUpdate {
    param($WindowsPath, $TimeoutMinutes, [switch]$IncludeDrivers)
    if ($TimeoutMinutes -ne 60) { throw 'Wrong Windows Update timeout.' }
    if ([bool]$IncludeDrivers -ne ($global:LauncherFixture.Scenario -like 'Final*')) { throw 'Wrong driver selection.' }
    Invoke-FixtureStage WindowsUpdate $WindowsPath
}
function Test-OSDStageDeployment {
    param($WindowsPath, [switch]$ThrowOnFailure)
    if (-not $ThrowOnFailure -or $WindowsPath -ne $global:LauncherFixture.Target) { throw 'Invalid final validation.' }
    Add-Content -LiteralPath $global:LauncherFixture.Trace -Value 'DeploymentCheck'
    [pscustomobject]@{
        WindowsPath = $WindowsPath; DeploymentId = 'fixture'; PackageCount = 7
        Valid = $true; OfflineReady = $false; NetworkRequired = $true
    }
}

$selection = @('OldFixture')
if ($Scenario -like 'Missing*') { $selection += @('MissingFirst', 'NotepadPlusPlus') }
$parameters = @{
    ModulePath = $ModulePath; CatalogUri = 'https://example.invalid/catalog.json'
    RepositoryApp = $selection; WindowsPath = $Target; OfficeLanguage = @('nl-nl', 'en-us')
    IncludeTeams = $true; Include7Zip = $true; WindowsUpdate = $true
    SkipCacheRefresh = ($Scenario -eq 'SkipCache')
}
if ($Scenario -like 'Final*') {
    $parameters.FinalAction = if ($Scenario -eq 'FinalReboot') { 'Reboot' } else { 'Shutdown' }
    $parameters.IncludeDrivers = $true
}
& $RunnerPath @parameters
exit $LASTEXITCODE
