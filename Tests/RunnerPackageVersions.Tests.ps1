Describe 'Concrete package versions in execution reports' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        . (Join-Path $root 'Runtime/OSDStagePayloadFile.ps1')
        . (Join-Path $root 'Runtime/OSDStageDeliveryReport.ps1')
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $root 'Runtime/Invoke-OSDStageRunner.ps1'), [ref]$tokens, [ref]$errors)
        foreach ($name in @('Invoke-BuiltInApp','New-RunnerAppResult','Get-RunnerCacheInfo','Write-RunnerLog')) {
            $definition = $ast.Find({ param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
            }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }
    BeforeEach {
        $script:StagedPath = $TestDrive
        $script:workRoot = Join-Path $TestDrive 'Work'
        $script:logPath = Join-Path $TestDrive 'runtime.log'
        $script:preInstallResult = $null
        Mock Get-RunnerCacheInfo { [pscustomobject]@{Version='Current'} }
        Mock Write-RunnerLog { }
        Mock Start-Process { [pscustomobject]@{ExitCode=0;HasExited=$true} }
        Mock Assert-OSDStageManifestPayload { $script:payload }
        Mock Get-OSDStageReportDevice { [pscustomobject]@{CollectionStatus='Available'} }
    }
    It 'records the version from the executed <Id> payload through result and report' -ForEach @(
        @{Id='GoogleChromeEnterprise';Type='VendorMsi';Version='157.0.1.0'},
        @{Id='AdobeAcrobatUnified';Type='AdobeAcrobatUnifiedZip';Version='26.002.21931'}
    ) {
        if ($Type -eq 'VendorMsi') {
            $script:payload = Join-Path $TestDrive 'chrome.msi'
            Set-Content $payload 'test payload'
            # MSI metadata reader is separately exercised against read-only COM fixtures.
            Mock Get-OSDStageMsiProductVersion { '157.0.1.0' }
        }
        else {
            $script:payload = Join-Path $TestDrive 'acrobat.zip'
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [IO.Compression.ZipFile]::Open($payload, [IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($file in @('Adobe Acrobat/setup.exe','Adobe Acrobat/setup.ini')) {
                    $entry = $zip.CreateEntry($file)
                    $writer = [IO.StreamWriter]::new($entry.Open())
                    try { $writer.WriteLine('PATCH=AcrobatDCx64Upd2600221931.msp') }
                    finally { $writer.Dispose() }
                }
            }
            finally { $zip.Dispose() }
        }
        $app = [pscustomobject]@{Id=$Id;Type=$Type;DisplayName='Friendly app';Source='BuiltIn';PackageType='App';Version='Current'}
        $script:manifest = [pscustomobject]@{DeploymentId=[guid]::NewGuid().Guid;Runtime=@{ModuleVersion='test'};Packages=@($app)}
        $execution = Invoke-BuiltInApp -app $app
        $execution.Version | Should -Be $Version
        $record = New-RunnerAppResult -App $app -Status Succeeded -Execution $execution
        $record.Version | Should -Be $Version
        $result = [pscustomobject]@{DeploymentId=$manifest.DeploymentId;Status='Succeeded';ExpectedPackageCount=1;RebootRequired=$false;Packages=@($record)}
        $report = New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $TestDrive
        $report.Packages[0].Version | Should -Be $Version
        (ConvertTo-OSDStageReportHtml $report) | Should -Match ([regex]::Escape("<td>$Version</td>"))
        $app.Version | Should -Be 'Current'
    }
    It 'keeps successful installation status when optional version inspection fails' {
        $script:payload = Join-Path $TestDrive 'unreadable.msi'
        Set-Content $payload 'not an MSI'
        Mock New-Object { throw 'COM unavailable' } -ParameterFilter { $ComObject -eq 'WindowsInstaller.Installer' }
        $app = [pscustomobject]@{Id='GoogleChromeEnterprise';Type='VendorMsi';Source='BuiltIn';Version='Current'}
        $execution = Invoke-BuiltInApp -app $app
        $record = New-RunnerAppResult -App $app -Status Succeeded -Execution $execution
        $record.Status | Should -Be 'Succeeded'
        $record.ExitCode | Should -Be 0
        $record.Version | Should -BeNullOrEmpty
    }
    It 'retains a concrete recorded version when runtime metadata is unavailable' {
        Mock Get-RunnerCacheInfo { [pscustomobject]@{Version='123.4.5'} }
        $app = [pscustomobject]@{Id='Chrome';Source='BuiltIn';Type='VendorMsi';Version='Current'}
        (New-RunnerAppResult -App $app -Status Succeeded).Version | Should -Be '123.4.5'
        $app.Version = '123.4.6'
        (New-RunnerAppResult -App $app -Status Failed).Version | Should -Be '123.4.6'
    }
}
