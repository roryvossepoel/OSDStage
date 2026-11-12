# Standalone finalization. No module import, startup trigger or retry after reboot.
function Get-OSDStageFinalAction {
    param([Parameter(Mandatory)]$Runtime)
    if ($null -eq $Runtime.PSObject.Properties['FinalAction']) { return 'None' }
    if ($Runtime.FinalAction -isnot [string] -or $Runtime.FinalAction -notin @('None','Reboot','Shutdown')) {
        throw 'Runtime.FinalAction must be None, Reboot or Shutdown.'
    }
    return [string]$Runtime.FinalAction
}

function New-OSDStageFinalActionState {
    param([string]$Action = 'None', [string]$Status = 'NotRequested', [string]$Reason)
    [pscustomobject]@{ Action=$Action; Status=$Status; Reason=$Reason; RequestedAtUtc=$null }
}

function Write-OSDStageFinalActionJson {
    param([string]$Path, $Value)
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $temporary -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}

function Get-OSDStageFinalActionProcesses {
    param([int]$RunnerId)
    $items = [Collections.Generic.List[object]]::new()
    $currentId = $RunnerId
    $foundScript = $false
    $foundSetup = $false
    for ($depth = 0; $depth -lt 16 -and $currentId -gt 0; $depth++) {
        $instance = Get-CimInstance Win32_Process -Filter "ProcessId=$currentId" -ErrorAction Stop
        if (-not $instance) { throw 'Cannot establish the SetupComplete process lifetime.' }
        $process = [Diagnostics.Process]::GetProcessById($currentId)
        try {
            if ($process.HasExited) { throw 'Setup process already exited before finalization was armed.' }
            $items.Add([pscustomobject]@{ Id=$currentId; StartTicks=$process.StartTime.ToUniversalTime().Ticks; Name=[string]$instance.Name })
        }
        finally { $process.Dispose() }
        if ($instance.Name -ieq 'cmd.exe' -and [string]$instance.CommandLine -match '(?i)(?:[\\/]|\b)SetupComplete\.cmd(?:["\s]|$)') { $foundScript = $true }
        if ($instance.Name -ieq 'windeploy.exe') { $foundSetup = $true; break }
        # Never wait for long-lived system ancestors (winlogon/services) or infer completion from a delay.
        if ($instance.Name -notin @('powershell.exe','pwsh.exe','cmd.exe')) { break }
        $currentId = [int]$instance.ParentProcessId
    }
    if (-not $foundScript -or -not $foundSetup) { throw 'FinalAction requires the standard SetupComplete.cmd / windeploy.exe execution context.' }
    return $items.ToArray()
}

function Start-OSDStageFinalAction {
    param([ValidateSet('Reboot','Shutdown')][string]$Action, [string]$DeploymentId,
        [string]$RunnerStartedAtUtc, [string]$StagedPath, [string]$ResultPath,
        [ValidateSet('Never','OnSuccess')][string]$CleanupMode)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) {
        throw 'FinalAction is only available in full Windows.'
    }
    $id = [guid]::Parse($DeploymentId)
    if ($id -eq [guid]::Empty) { throw 'FinalAction requires a deployment identity.' }
    $processes = @(Get-OSDStageFinalActionProcesses -RunnerId $PID)
    $stage = [IO.Path]::GetFullPath($StagedPath).TrimEnd('\','/')
    $result = [IO.Path]::GetFullPath($ResultPath)
    $root = Join-Path $env:ProgramData ('OSDStage\FinalActions\' + $id.Guid)
    foreach ($retained in @($result,$root)) {
        if ($retained.StartsWith($stage + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'FinalAction results and worker must be outside the staging directory.'
        }
    }
    if (Test-Path -LiteralPath $root) { throw 'FinalAction was already armed for this deployment; it will not be retried.' }
    New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
    # Only SYSTEM and local administrators may change the deferred power request.
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($sid in @('S-1-5-18','S-1-5-32-544')) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.SecurityIdentifier]::new($sid), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $root -AclObject $acl -ErrorAction Stop
    foreach ($file in @('OSDStageFinalAction.ps1','Invoke-OSDStageFinalAction.ps1','OSDStageDeliveryReport.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $root $file) -ErrorAction Stop
    }
    $taskName = 'OSDStage-FinalAction-' + $id.Guid
    $requestPath = Join-Path $root 'Request.json'
    $request = [pscustomobject]@{
        DeploymentId=$id.Guid; Action=$Action; RunnerStartedAtUtc=$RunnerStartedAtUtc
        StagedPath=$stage; ResultPath=$result; CleanupMode=$CleanupMode; Processes=$processes
        ManifestHash=(Get-FileHash -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Algorithm SHA256).Hash
        TaskName=$taskName; TimeoutSeconds=1800
    }
    Write-OSDStageFinalActionJson -Path $requestPath -Value $request
    $workerPath = Join-Path $root 'Invoke-OSDStageFinalAction.ps1'
    $engine = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -RequestPath "{1}"' -f $workerPath,$requestPath
    try {
        $taskAction = New-ScheduledTaskAction -Execute $engine -Argument $arguments
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 35) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $taskName -Action $taskAction -Principal $principal -Settings $settings -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path -LiteralPath (Join-Path $root 'Ready'))) {
            if ($watch.Elapsed.TotalSeconds -ge 30 -or (Test-Path -LiteralPath (Join-Path $root 'Finished.json'))) {
                throw 'FinalAction worker did not attach to the live SetupComplete processes.'
            }
            Start-Sleep -Milliseconds 200
        }
    }
    catch {
        Set-Content -LiteralPath (Join-Path $root 'Cancel') -Value 'FinalAction registration failed.' -Encoding UTF8
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        throw
    }
}

function Open-OSDStageFinalActionProcess {
    param($Identity)
    $process = [Diagnostics.Process]::GetProcessById([int]$Identity.Id)
    try {
        $null = $process.Handle
        if ($process.HasExited -or $process.StartTime.ToUniversalTime().Ticks -ne [long]$Identity.StartTicks) {
            throw 'A SetupComplete process exited or its PID was reused before the worker attached.'
        }
        return $process
    }
    catch { $process.Dispose(); throw }
}

function Wait-OSDStageFinalActionProcesses {
    param($Request, [string]$Directory)
    $handles = [Collections.Generic.List[object]]::new()
    try {
        foreach ($identity in $Request.Processes) {
            # Pin the process identity and exit status before acknowledging Ready.
            $handles.Add((Open-OSDStageFinalActionProcess -Identity $identity))
        }
        if ($handles.Count -lt 3) { throw 'Incomplete SetupComplete process evidence.' }
        Set-Content -LiteralPath (Join-Path $Directory 'Ready') -Value 'Process handles acquired.' -Encoding UTF8 -ErrorAction Stop
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while (@($handles | Where-Object { -not $_.HasExited }).Count -gt 0) {
            if (Test-Path -LiteralPath (Join-Path $Directory 'Cancel')) { throw 'FinalAction was cancelled.' }
            if ($watch.Elapsed.TotalSeconds -ge [int]$Request.TimeoutSeconds) { throw 'SetupComplete did not finish within the finalization wait limit; no power action requested.' }
            Start-Sleep -Milliseconds 500
        }
        foreach ($process in $handles) {
            if ($process.ExitCode -ne 0) { throw "A deployment/SetupComplete process exited with code $($process.ExitCode); no power action requested." }
        }
    }
    finally { foreach ($process in $handles) { $process.Dispose() } }
}

function Get-OSDStageFinalActionEvidence {
    param($Request)
    $result = Get-Content -LiteralPath $Request.ResultPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $directory = Split-Path -Parent $Request.ResultPath
    $report = Get-Content -LiteralPath (Join-Path $directory 'DeliveryReport.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($result.DeploymentId -ne $Request.DeploymentId -or $report.DeploymentId -ne $Request.DeploymentId -or
        [string]$result.StartedAtUtc -ne [string]$Request.RunnerStartedAtUtc -or
        $result.Status -ne 'Succeeded' -or $report.ExecutionStatus -ne 'Succeeded' -or
        [string]$report.StartedAtUtc -ne [string]$Request.RunnerStartedAtUtc -or
        [string]$report.CompletedAtUtc -ne [string]$result.CompletedAtUtc -or
        $result.UnsuccessfulPackageCount -ne 0 -or $result.SuccessfulPackageCount -ne $result.ExpectedPackageCount -or
        @($result.Packages).Count -ne $result.ExpectedPackageCount -or
        @($result.Packages | Where-Object Status -ne 'Succeeded').Count -gt 0 -or
        $result.FinalAction.Action -ne $Request.Action -or $result.FinalAction.Status -ne 'Waiting') {
        throw 'FinalAction has no matching, complete successful runner result; the request may have been superseded.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $directory 'DeliveryReport.html') -PathType Leaf)) { throw 'Delivery report HTML is missing.' }
    return [pscustomobject]@{ Result=$result; Report=$report; Directory=$directory }
}

function Save-OSDStageFinalActionOutcome {
    param($Request, [string]$Directory, [string]$Status, [string]$Reason)
    $state = New-OSDStageFinalActionState -Action $Request.Action -Status $Status -Reason $Reason
    if ($Status -eq 'Requested') { $state.RequestedAtUtc = [datetime]::UtcNow.ToString('o') }
    Write-OSDStageFinalActionJson -Path (Join-Path $Directory 'Finished.json') -Value $state
    # Never overwrite another deployment or a newer execution of this deployment.
    $result = Get-Content -LiteralPath $Request.ResultPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($result.DeploymentId -ne $Request.DeploymentId -or [string]$result.StartedAtUtc -ne [string]$Request.RunnerStartedAtUtc) { throw 'FinalAction result was superseded.' }
    $reportDirectory = Split-Path -Parent $Request.ResultPath
    $reportPath = Join-Path $reportDirectory 'DeliveryReport.json'
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($report.DeploymentId -ne $Request.DeploymentId -or
        [string]$report.StartedAtUtc -ne [string]$Request.RunnerStartedAtUtc -or
        [string]$report.CompletedAtUtc -ne [string]$result.CompletedAtUtc) { throw 'FinalAction report was superseded.' }
    $result | Add-Member -NotePropertyName FinalAction -NotePropertyValue $state -Force
    $report | Add-Member -NotePropertyName FinalAction -NotePropertyValue (ConvertTo-OSDStageReportFinalAction -State $state) -Force
    if ($Status -in @('Skipped','Failed') -and $report.Status -eq 'Succeeded') {
        $report.Status = 'Attention'
        $report.Summary = 'Execution succeeded; the configured final action was not requested. Review final action details.'
    }
    Write-OSDStageFinalActionJson -Path $Request.ResultPath -Value $result
    Write-OSDStageFinalActionJson -Path $reportPath -Value $report
    $htmlPath = Join-Path $reportDirectory 'DeliveryReport.html'
    $temporary = "$htmlPath.finalaction.tmp"
    try {
        ConvertTo-OSDStageReportHtml -Report $report | Set-Content -LiteralPath $temporary -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $temporary -Destination $htmlPath -Force -ErrorAction Stop
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}

function Invoke-OSDStageFinalPowerAction {
    param([ValidateSet('Reboot','Shutdown')][string]$Action)
    $operation = if ($Action -eq 'Reboot') { '/r' } else { '/s' }
    # /t 0 avoids the implicit force-close behavior of a positive shutdown timeout.
    # No /f: unrelated apps are not forcibly terminated.
    $process = Start-Process -FilePath (Join-Path $env:windir 'System32\shutdown.exe') -ArgumentList @($operation,'/t','0') -Wait -PassThru -ErrorAction Stop
    if ($process.ExitCode -ne 0) { throw "Windows rejected the final action (exit code $($process.ExitCode))." }
}

function Invoke-OSDStageFinalAction {
    param([Parameter(Mandatory)][string]$RequestPath)
    $directory = Split-Path -Parent $RequestPath
    $request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($request.Action -notin @('Reboot','Shutdown')) { throw 'Invalid final action request.' }
    $claim = Join-Path $directory 'Claimed'
    # CreateNew is atomic. Even a duplicate/manual invocation cannot request power twice.
    try { $claimHandle = [IO.File]::Open($claim,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None); $claimHandle.Dispose() }
    catch [IO.IOException] { return }
    try {
        Wait-OSDStageFinalActionProcesses -Request $request -Directory $directory
        if (Test-Path -LiteralPath (Join-Path $directory 'Cancel')) { throw 'FinalAction was cancelled.' }
        $null = Get-OSDStageFinalActionEvidence -Request $request
        $manifestPath = Join-Path $request.StagedPath 'DeviceManifest.json'
        if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $request.ManifestHash) {
            throw 'Staged deployment changed while waiting; cleanup and final action were skipped.'
        }
        if ($request.CleanupMode -eq 'OnSuccess') {
            Remove-Item -LiteralPath $request.StagedPath -Recurse -Force -ErrorAction Stop
            if (Test-Path -LiteralPath $request.StagedPath) { throw 'Runtime cleanup did not finish.' }
        }
        elseif ($request.CleanupMode -ne 'Never') { throw 'Unsupported finalization cleanup mode.' }
        Unregister-ScheduledTask -TaskName $request.TaskName -Confirm:$false -ErrorAction Stop
        Save-OSDStageFinalActionOutcome -Request $request -Directory $directory -Status Requested -Reason 'Runner, SetupComplete and Windows Setup exited successfully; configured cleanup finished. The power request is being submitted, not verified as completed.'
        # LAST operation: every result/report write, process wait and cleanup precedes this call.
        Invoke-OSDStageFinalPowerAction -Action $request.Action
    }
    catch {
        $reason = $_.Exception.Message
        Unregister-ScheduledTask -TaskName $request.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        try { Save-OSDStageFinalActionOutcome -Request $request -Directory $directory -Status Skipped -Reason $reason }
        catch {
            # A missing/superseded report must not hide the reason or permit a power request.
            Write-OSDStageFinalActionJson -Path (Join-Path $directory 'Finished.json') -Value (New-OSDStageFinalActionState -Action $request.Action -Status Skipped -Reason $reason)
        }
    }
}
