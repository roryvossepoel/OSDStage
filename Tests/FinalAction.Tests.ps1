Describe 'Final action configuration and staging' {
    BeforeEach {
        $script:root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
        . (Join-Path $script:root 'Runtime/OSDStageFinalAction.ps1')
    }
    It 'defaults to None, preserves an explicit choice and writes it to the device manifest' {
        (Get-OSDStageConfiguration).FinalAction | Should -Be None
        Set-OSDStageConfiguration -FinalAction Shutdown
        Set-OSDStageConfiguration -CleanupMode Never
        (Get-OSDStageConfiguration).FinalAction | Should -Be Shutdown
        InModuleScope OSDStage {
            (Set-OSDStageManifestRuntimeConfiguration -Manifest ([pscustomobject]@{})).Runtime.FinalAction | Should -Be Shutdown
        }
        (Set-OSDStageConfiguration -FinalAction Reboot -PassThru).FinalAction | Should -Be Reboot
        (Set-OSDStageConfiguration -FinalAction None -PassThru).FinalAction | Should -Be None
    }
    It 'does not infer power intent from a legacy manifest' {
        Set-StrictMode -Version Latest
        Get-OSDStageFinalAction -Runtime ([pscustomobject]@{}) | Should -Be None
    }
    It 'rejects invalid manifest power intent <Value>' -TestCases @(
        @{Value='Restart'}, @{Value=''}, @{Value=$null}, @{Value=$true}
    ) {
        param($Value)
        { Get-OSDStageFinalAction -Runtime ([pscustomobject]@{FinalAction=$Value}) } | Should -Throw '*None, Reboot or Shutdown*'
    }
    It 'stages the standalone finalizer and its dependencies unchanged' {
        InModuleScope OSDStage -Parameters @{Target=$TestDrive} {
            param($Target)
            Add-OSDStageSetupComplete -WindowsPath $Target | Out-Null
            $root = Split-Path (Get-Module OSDStage).Path -Parent
            foreach ($file in @('OSDStageFinalAction.ps1','Invoke-OSDStageFinalAction.ps1','OSDStageDeliveryReport.ps1')) {
                (Get-FileHash (Join-Path $Target ('Windows/Temp/OSDStage/' + $file))).Hash |
                    Should -Be (Get-FileHash (Join-Path $root ('Runtime/' + $file))).Hash
            }
        }
    }
}

Describe 'Final action process barrier' {
    BeforeAll { . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Runtime/OSDStageFinalAction.ps1') }
    BeforeEach {
        $barrierDirectory = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        New-Item -ItemType Directory -Path $barrierDirectory | Out-Null
        $script:handles = @(1..3 | ForEach-Object {
            $p = [pscustomobject]@{HasExited=$false;ExitCode=0;Disposed=$false}
            $p | Add-Member ScriptMethod Dispose { $this.Disposed=$true }
            $p
        })
        Mock Open-OSDStageFinalActionProcess { param($Identity) $script:handles[$Identity.Id-1] }
        $script:iterations=0
        Mock Start-Sleep {
            $script:handles[$script:iterations].HasExited=$true
            $script:iterations++
        }
        $request = [pscustomobject]@{Processes=@(1..3 | ForEach-Object { @{Id=$_} });TimeoutSeconds=5}
    }
    It 'waits for all three processes, not only the runner, and releases all handles' {
        Wait-OSDStageFinalActionProcesses -Request $request -Directory $barrierDirectory
        $script:iterations | Should -Be 3
        @($script:handles | Where-Object Disposed -eq $true).Count | Should -Be 3
        Test-Path (Join-Path $barrierDirectory 'Ready') | Should -BeTrue
    }
    It 'does not acknowledge a missing or reused process identity' {
        Mock Open-OSDStageFinalActionProcess { throw 'PID reused' } -ParameterFilter { $Identity.Id -eq 2 }
        { Wait-OSDStageFinalActionProcesses -Request $request -Directory $barrierDirectory } | Should -Throw '*PID reused*'
        Test-Path (Join-Path $barrierDirectory 'Ready') | Should -BeFalse
        $script:handles[0].Disposed | Should -BeTrue
    }
    It 'stops without proceeding on a timeout' {
        $request.TimeoutSeconds=0
        { Wait-OSDStageFinalActionProcesses -Request $request -Directory $barrierDirectory } | Should -Throw '*wait limit*'
        $script:iterations | Should -Be 0
    }
    It 'requires a successful exit from later SetupComplete work too' {
        $script:handles[1].ExitCode=17
        { Wait-OSDStageFinalActionProcesses -Request $request -Directory $barrierDirectory } | Should -Throw '*code 17*'
    }
    It 'honors cancellation while waiting' {
        Set-Content (Join-Path $barrierDirectory 'Cancel') 'cancel'
        { Wait-OSDStageFinalActionProcesses -Request $request -Directory $barrierDirectory } | Should -Throw '*cancelled*'
        $script:iterations | Should -Be 0
    }
}

Describe 'Final action ordering and failure isolation' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        . (Join-Path $script:root 'Runtime/OSDStageFinalAction.ps1')
        . (Join-Path $script:root 'Runtime/OSDStageDeliveryReport.ps1')
        if (-not (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue)) {
            function Unregister-ScheduledTask { param($TaskName,[switch]$Confirm,$ErrorAction) }
        }
    }
    BeforeEach {
        $script:directory = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $script:stage = Join-Path $script:directory 'Stage'
        $script:results = Join-Path $script:directory 'Results'
        $script:worker = Join-Path $script:directory 'Worker'
        New-Item -ItemType Directory -Path $script:stage,$script:results,$script:worker -Force | Out-Null
        $report = Get-Content (Join-Path $script:root 'site/examples/DeliveryReport.json') -Raw | ConvertFrom-Json
        $id = [guid]::NewGuid().Guid
        $report.DeploymentId=$id
        $state = New-OSDStageFinalActionState -Action Shutdown -Status Waiting
        $report | Add-Member NoteProperty FinalAction $state
        $result = [pscustomobject]@{
            DeploymentId=$id;StartedAtUtc=$report.StartedAtUtc;CompletedAtUtc=$report.CompletedAtUtc
            Status='Succeeded';ExpectedPackageCount=@($report.Packages).Count;SuccessfulPackageCount=@($report.Packages).Count
            UnsuccessfulPackageCount=0;Packages=$report.Packages;FinalAction=$state;RebootRequired=$true
        }
        Write-OSDStageFinalActionJson (Join-Path $script:results 'Latest.json') $result
        Write-OSDStageFinalActionJson (Join-Path $script:results 'DeliveryReport.json') $report
        Set-Content (Join-Path $script:results 'DeliveryReport.html') 'original report'
        Set-Content (Join-Path $script:stage 'DeviceManifest.json') ('{"DeploymentId":"' + $id + '"}')
        $script:request = [pscustomobject]@{
            DeploymentId=$id;Action='Shutdown';RunnerStartedAtUtc=$report.StartedAtUtc
            StagedPath=$script:stage;ResultPath=(Join-Path $script:results 'Latest.json');CleanupMode='OnSuccess'
            ManifestHash=(Get-FileHash (Join-Path $script:stage 'DeviceManifest.json') -Algorithm SHA256).Hash
            TaskName='OSDStage-test';Processes=@();TimeoutSeconds=0
        }
        $script:requestPath=Join-Path $script:worker 'Request.json'
        $script:order=[Collections.Generic.List[string]]::new()
        Mock Wait-OSDStageFinalActionProcesses { $script:order.Add('ProcessesExited') }
        Mock Unregister-ScheduledTask { $script:order.Add('TaskRemoved') }
        Mock Invoke-OSDStageFinalPowerAction {
            $script:order.Add('Power')
            $saved=Get-Content (Join-Path $script:results 'Latest.json') -Raw | ConvertFrom-Json
            $saved.FinalAction.Status | Should -Be Requested
            $saved.RebootRequired | Should -BeTrue
            $html=Get-Content (Join-Path $script:results 'DeliveryReport.html') -Raw
            $html | Should -Match 'Final action'
            $html | Should -Match 'Requested'
            if ($script:request.CleanupMode -eq 'OnSuccess') { Test-Path $script:stage | Should -BeFalse }
        }
    }
    It 'finishes process waits, cleanup, result/report writes and task removal before <Action>' -TestCases @(
        @{Action='Shutdown'},@{Action='Reboot'}
    ) {
        param($Action)
        $script:request.Action=$Action
        $result=Get-Content $script:request.ResultPath -Raw | ConvertFrom-Json
        $result.FinalAction.Action=$Action
        Write-OSDStageFinalActionJson $script:request.ResultPath $result
        Write-OSDStageFinalActionJson $script:requestPath $script:request
        Invoke-OSDStageFinalAction $script:requestPath
        Should -Invoke Invoke-OSDStageFinalPowerAction -Times 1 -Exactly -ParameterFilter { $Action -eq $script:request.Action }
        @($script:order) | Should -Be @('ProcessesExited','TaskRemoved','Power')
    }
    It 'retains sources with CleanupMode Never but still performs the final action last' {
        $script:request.CleanupMode='Never'
        Write-OSDStageFinalActionJson $script:requestPath $script:request
        Invoke-OSDStageFinalAction $script:requestPath
        Test-Path $script:stage | Should -BeTrue
        Should -Invoke Invoke-OSDStageFinalPowerAction -Times 1 -Exactly
        $script:order[-1] | Should -Be Power
    }
    It 'never retries an already claimed deployment action' {
        Write-OSDStageFinalActionJson $script:requestPath $script:request
        Invoke-OSDStageFinalAction $script:requestPath
        Invoke-OSDStageFinalAction $script:requestPath
        Should -Invoke Invoke-OSDStageFinalPowerAction -Times 1 -Exactly
    }
    It 'skips power and retains sources when <Scenario>' -TestCases @(
        @{Scenario='SetupComplete failed'},@{Scenario='SetupComplete timed out'},@{Scenario='runner failed'},
        @{Scenario='packages skipped'},@{Scenario='deployment superseded'},@{Scenario='manifest changed'},
        @{Scenario='report missing'},@{Scenario='report stale'},@{Scenario='cancelled'},@{Scenario='cleanup failed'}
    ) {
        param($Scenario)
        $result=Get-Content $script:request.ResultPath -Raw | ConvertFrom-Json
        switch ($Scenario) {
            'SetupComplete failed' { Mock Wait-OSDStageFinalActionProcesses { throw 'Parent failed' } }
            'SetupComplete timed out' { Mock Wait-OSDStageFinalActionProcesses { throw 'Wait timed out' } }
            'runner failed' { $result.Status='Failed' }
            'packages skipped' { $result.Packages[0].Status='Skipped';$result.UnsuccessfulPackageCount=1 }
            'deployment superseded' { $result.DeploymentId=[guid]::NewGuid().Guid }
            'manifest changed' { Add-Content (Join-Path $script:stage 'DeviceManifest.json') 'changed' }
            'report missing' { Remove-Item (Join-Path $script:results 'DeliveryReport.html') }
            'report stale' {
                $report=Get-Content (Join-Path $script:results 'DeliveryReport.json') -Raw | ConvertFrom-Json
                $report.CompletedAtUtc='2000-01-01T00:00:00Z'
                Write-OSDStageFinalActionJson (Join-Path $script:results 'DeliveryReport.json') $report
            }
            'cancelled' { Set-Content (Join-Path $script:worker 'Cancel') 'cancel' }
            'cleanup failed' { Mock Remove-Item { throw 'Source locked' } -ParameterFilter { $LiteralPath -eq $script:stage } }
        }
        Write-OSDStageFinalActionJson $script:request.ResultPath $result
        Write-OSDStageFinalActionJson $script:requestPath $script:request
        Invoke-OSDStageFinalAction $script:requestPath
        Should -Invoke Invoke-OSDStageFinalPowerAction -Times 0 -Exactly
        Test-Path $script:stage | Should -BeTrue
        (Get-Content (Join-Path $script:worker 'Finished.json') -Raw | ConvertFrom-Json).Status | Should -Be Skipped
        if ($Scenario -eq 'deployment superseded') {
            (Get-Content $script:request.ResultPath -Raw | ConvertFrom-Json).FinalAction.Status | Should -Be Waiting
        }
    }
    It 'does not request power if final report persistence fails' {
        Mock ConvertTo-OSDStageReportHtml { throw 'Cannot render final report' }
        Write-OSDStageFinalActionJson $script:requestPath $script:request
        Invoke-OSDStageFinalAction $script:requestPath
        Should -Invoke Invoke-OSDStageFinalPowerAction -Times 0 -Exactly
        (Get-Content (Join-Path $script:worker 'Finished.json') -Raw | ConvertFrom-Json).Status | Should -Be Skipped
    }
    It 'records rejection of the power request without retrying it' {
        Mock Invoke-OSDStageFinalPowerAction { throw 'Windows rejected the final action' }
        Write-OSDStageFinalActionJson $script:requestPath $script:request
        Invoke-OSDStageFinalAction $script:requestPath
        Invoke-OSDStageFinalAction $script:requestPath
        Should -Invoke Invoke-OSDStageFinalPowerAction -Times 1 -Exactly
        $state=Get-Content (Join-Path $script:worker 'Finished.json') -Raw | ConvertFrom-Json
        $state.Status | Should -Be Skipped
        $state.Reason | Should -Match 'Windows rejected'
        $report=Get-Content (Join-Path $script:results 'DeliveryReport.json') -Raw | ConvertFrom-Json
        $report.FinalAction.Reason | Should -Not -Match 'Windows rejected'
        $report.FinalAction.Status | Should -Be Skipped
    }
}

Describe 'Runner final action integration' {
    BeforeAll {
        $script:root=Split-Path $PSScriptRoot -Parent
        $script:engine=(Get-Process -Id $PID).Path
    }
    It 'arms only an unfiltered successful configured run: <Scenario>' -TestCases @(
        @{Scenario='legacy';Action=$null;Fail=$false;Filtered=$false;Armed=$false;State='NotRequested';ExitCode=0},
        @{Scenario='None';Action='None';Fail=$false;Filtered=$false;Armed=$false;State='NotRequested';ExitCode=0},
        @{Scenario='Shutdown';Action='Shutdown';Fail=$false;Filtered=$false;Armed=$true;State='Waiting';ExitCode=0},
        @{Scenario='Reboot';Action='Reboot';Fail=$false;Filtered=$false;Armed=$true;State='Waiting';ExitCode=0},
        @{Scenario='failed';Action='Shutdown';Fail=$true;Filtered=$false;Armed=$false;State='Skipped';ExitCode=1},
        @{Scenario='registrationfailed';Action='Shutdown';Fail=$false;Filtered=$false;Armed=$false;State='Skipped';ExitCode=0},
        @{Scenario='filtered';Action='Shutdown';Fail=$false;Filtered=$true;Armed=$false;State='Skipped';ExitCode=0}
    ) {
        param($Scenario,$Action,$Fail,$Filtered,$Armed,$State,$ExitCode)
        $folder=Join-Path $TestDrive $Scenario
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Copy-Item (Join-Path $script:root 'Runtime/*') -Destination $folder
        # Replace only task registration. The real runner must make the decision;
        # no test creates a scheduled task or calls shutdown.exe.
        Add-Content (Join-Path $folder 'OSDStageFinalAction.ps1') @'
function Start-OSDStageFinalAction {
    param($Action,$DeploymentId,$RunnerStartedAtUtc,$StagedPath,$ResultPath,$CleanupMode)
    Set-Content (Join-Path $StagedPath 'armed.txt') $Action
}
'@
        if ($Scenario -eq 'registrationfailed') {
            Add-Content (Join-Path $folder 'OSDStageFinalAction.ps1') "function Start-OSDStageFinalAction { throw 'Task registration failed' }"
        }
        $runtime=@{PreventSleep=$false;CleanupMode='Never';CacheVolumeLabel='Test';LogPath=(Join-Path $folder 'Runtime.log');ResultPath=(Join-Path $folder 'Results/Latest.json')}
        if ($null -ne $Action) { $runtime.FinalAction=$Action }
        $packages=@()
        if ($Fail) { $packages=@(@{Id='..invalid';Source='BuiltIn';Type='VendorMsi'}) }
        @{DeploymentId=[guid]::NewGuid().Guid;Runtime=$runtime;Packages=$packages} | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $folder 'DeviceManifest.json') -Encoding UTF8
        $arguments=@('-NoProfile','-File',(Join-Path $folder 'Invoke-OSDStageRunner.ps1'),'-StagedPath',$folder)
        if ($Filtered) { $arguments+=@('-Name','NotSelected') }
        & $script:engine @arguments | Out-Null
        $LASTEXITCODE | Should -Be $ExitCode
        Test-Path (Join-Path $folder 'armed.txt') | Should -Be $Armed
        (Get-Content $runtime.ResultPath -Raw | ConvertFrom-Json).FinalAction.Status | Should -Be $State
    }
}

Describe 'Windows native process exit evidence' {
    BeforeAll { . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Runtime/OSDStageFinalAction.ps1') }
    It 'retains native handles until all later processes exit successfully' -Skip:($env:OS -ne 'Windows_NT') {
        $children=@()
        try {
            $engine=(Get-Process -Id $PID).Path
            foreach ($seconds in @(3,5,7)) {
                $children+=Start-Process $engine -ArgumentList @('-NoProfile','-Command',"Start-Sleep -Seconds $seconds; exit 0") -PassThru
            }
            $identities=@($children | ForEach-Object { [pscustomobject]@{Id=$_.Id;StartTicks=$_.StartTime.ToUniversalTime().Ticks} })
            Wait-OSDStageFinalActionProcesses -Request ([pscustomobject]@{Processes=$identities;TimeoutSeconds=30}) -Directory $TestDrive
            @($children | Where-Object { -not $_.HasExited }).Count | Should -Be 0
        }
        finally { foreach ($child in $children) { if (-not $child.HasExited) { $child.Kill() };$child.Dispose() } }
    }
}
