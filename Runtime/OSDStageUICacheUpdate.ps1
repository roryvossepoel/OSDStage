
function Get-OSDStageUIOfficeAvailableVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)

    $configurationPath = Join-Path ([string]$Entry.CachePath) 'configuration.xml'
    if (-not (Test-Path -LiteralPath $configurationPath -PathType Leaf)) {
        throw 'Cached Office configuration.xml is missing.'
    }
    $profile = Get-OSDStageOfficePayloadProfile -Path $configurationPath
    if ($profile.Version -match '^\d+\.\d+\.\d+\.\d+
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)

    "$([string]$Entry.Source):$([string]$Entry.Id):$([string]$Entry.Architecture):$([string]$Entry.Channel):$([string]$Entry.RuntimeType)"
}

function New-OSDStageUICacheUpdatePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    if (-not $State.Snapshot -or -not $State.Snapshot.CachePath) {
        throw 'No OSDStage USB cache is currently connected.'
    }

    # Always refresh release metadata immediately before an update. This avoids
    # applying stale status from a previously connected USB device.
    $State.Status.Text = 'Checking available cache updates...'
    $State.Form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    [void](Update-OSDStageUICacheUpdateStatus -State $State)

    $available = @(
        foreach ($entry in @($State.Snapshot.CacheEntries)) {
            $key = Get-OSDStageUICacheUpdateKey -Entry $entry
            $status = $State.CacheUpdateStatus[$key]
            if ($status -and [string]$status.Status -eq 'Update available') {
                [pscustomobject]@{ Entry=$entry; Status=$status }
            }
        }
    )

    $plan = [System.Collections.Generic.List[object]]::new()

    $repositoryEntries = @($available | Where-Object { [string]$_.Entry.Source -eq 'Repository' })
    if ($repositoryEntries.Count -gt 0) {
        $names = @($repositoryEntries.Entry.Id | Sort-Object -Unique)
        $plan.Add([pscustomobject]@{
            Source       = 'Repository'
            Id           = 'Repository'
            DisplayName  = "Repository packages ($($names.Count))"
            Command      = 'Sync-OSDStageRepository'
            Names        = $names
            Architecture = $null
            Channel      = $null
            RuntimeType  = $null
            Current      = $null
            Latest       = $null
        })
    }

    foreach ($candidate in @($available | Where-Object { [string]$_.Entry.Source -eq 'BuiltIn' })) {
        $entry = $candidate.Entry

        # Only release resolvers that produced an explicit Update available
        # status can reach this plan. Microsoft 365 Apps and other unsupported
        # built-ins therefore cannot be downloaded accidentally.
        $commandName = "Sync-OSDStage$($entry.Id)"
        $command = Get-Command -Name $commandName -Module OSDStage -ErrorAction SilentlyContinue
        if (-not $command) { continue }

        $displayName = if ($entry.DisplayName) { [string]$entry.DisplayName } else { [string]$entry.Id }
        $plan.Add([pscustomobject]@{
            Source       = 'BuiltIn'
            Id           = [string]$entry.Id
            DisplayName  = $displayName
            Command      = $commandName
            Names        = @()
            Architecture = [string]$entry.Architecture
            Channel      = [string]$entry.Channel
            RuntimeType  = [string]$entry.RuntimeType
            Current      = [string]$entry.Version
            Latest       = [string]$candidate.Status.Latest
        })
    }

    @($plan)
}

function Invoke-OSDStageUICacheUpdate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    $plan = @(New-OSDStageUICacheUpdatePlan -State $State)
    if ($plan.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'No supported cache updates are currently available.',
            'OSDStage - Update cache',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return [pscustomobject]@{ Updated=@(); Current=@(); Skipped=@('No updates available'); Failed=@() }
    }

    $summaryLines = @(
        "Update $($plan.Count) available cache item(s)?"
        ''
        @($plan | ForEach-Object {
            if ($_.Latest) { "- $($_.DisplayName): $($_.Current) -> $($_.Latest)" }
            else { "- $($_.DisplayName)" }
        })
        ''
        'Only items marked Update available will be synchronized.'
    )
    $answer = [System.Windows.Forms.MessageBox]::Show(
        ($summaryLines -join [Environment]::NewLine),
        'OSDStage - Update available cache items',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return [pscustomobject]@{ Updated=@(); Current=@(); Skipped=@('Cancelled'); Failed=@() }
    }

    $modulePath = Join-Path $script:moduleRoot 'OSDStage.psd1'
    $catalogUri = (Get-OSDStageConfiguration).CatalogUri
    $payload = [pscustomobject]@{
        ModulePath = $modulePath
        CatalogUri = if ($catalogUri) { $catalogUri.AbsoluteUri } else { $null }
        Tasks      = @($plan)
    }

    $worker = {
        param($Payload)

        $ErrorActionPreference = 'Stop'
        Import-Module -Name ([string]$Payload.ModulePath) -Force -ErrorAction Stop
        if ($Payload.CatalogUri) {
            Set-OSDStageConfiguration -CatalogUri ([uri]$Payload.CatalogUri) | Out-Null
        }

        $tasks = @($Payload.Tasks)
        $total = $tasks.Count
        $position = 0

        foreach ($task in $tasks) {
            $position++
            Write-Output ([pscustomobject]@{
                RecordType = 'Start'
                Position   = $position
                Total      = $total
                Label      = [string]$task.DisplayName
                Message    = "Checking and updating $($task.DisplayName)"
            })

            try {
                if ([string]$task.Source -eq 'Repository') {
                    $names = @($task.Names)
                    Sync-OSDStageRepository -Name $names -Confirm:$false -ErrorAction Stop | Out-Null
                    Write-Output ([pscustomobject]@{
                        RecordType='Complete'; Position=$position; Total=$total
                        Label=[string]$task.DisplayName; Status='Updated'
                        Message="Repository cache synchronized: $($names -join ', ')"
                    })
                    continue
                }

                $parameters = @{}
                if ($task.Architecture) { $parameters.Architecture = [string]$task.Architecture }
                if ($task.Channel) { $parameters.Channel = [string]$task.Channel }
                if ($task.RuntimeType) { $parameters.RuntimeType = [string]$task.RuntimeType }
                $parameters.Confirm = $false

                $result = @(& ([string]$task.Command) @parameters -ErrorAction Stop)
                $updatedFlag = @(
                    $result |
                        Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'Updated' } |
                        Select-Object -Last 1
                )
                $wasUpdated = if ($updatedFlag.Count -gt 0) { [bool]$updatedFlag[0].Updated } else { $true }
                $status = if ($wasUpdated) { 'Updated' } else { 'Already current' }

                Write-Output ([pscustomobject]@{
                    RecordType='Complete'; Position=$position; Total=$total
                    Label=[string]$task.DisplayName; Status=$status
                    Message="$($task.DisplayName): $status"
                })
            }
            catch {
                Write-Output ([pscustomobject]@{
                    RecordType='Failed'; Position=$position; Total=$total
                    Label=[string]$task.DisplayName; Status='Failed'
                    Message="$($task.DisplayName): $($_.Exception.Message)"
                })
            }
        }
    }

    $job = Start-Job -ScriptBlock $worker -ArgumentList $payload
    $progressForm = [System.Windows.Forms.Form]::new()
    $progressForm.Text = 'OSDStage - Updating cache'
    $progressForm.Size = [System.Drawing.Size]::new(660,410)
    $progressForm.MinimumSize = [System.Drawing.Size]::new(560,340)
    $progressForm.StartPosition = 'CenterParent'
    $progressForm.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $progressForm.Font = [System.Drawing.Font]::new('Segoe UI',9)
    $progressForm.ControlBox = $false
    $progressForm.ShowInTaskbar = $false

    $layout = [System.Windows.Forms.TableLayoutPanel]::new()
    $layout.Dock = 'Fill'
    $layout.Padding = [System.Windows.Forms.Padding]::new(12)
    $layout.RowCount = 5
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',32))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',28))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',26))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',42))
    $progressForm.Controls.Add($layout)

    $activity = [System.Windows.Forms.Label]::new()
    $activity.Dock = 'Fill'
    $activity.Font = [System.Drawing.Font]::new('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
    $activity.Text = 'Preparing cache update...'
    [void]$layout.Controls.Add($activity,0,0)

    $progress = [System.Windows.Forms.ProgressBar]::new()
    $progress.Dock = 'Fill'
    $progress.Minimum = 0
    $progress.Maximum = [math]::Max(1,$plan.Count)
    $progress.Value = 0
    $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    [void]$layout.Controls.Add($progress,0,1)

    $elapsed = [System.Windows.Forms.Label]::new()
    $elapsed.Dock = 'Fill'
    $elapsed.Text = 'Elapsed: 00:00'
    [void]$layout.Controls.Add($elapsed,0,2)

    $details = [System.Windows.Forms.TextBox]::new()
    $details.Dock = 'Fill'
    $details.Multiline = $true
    $details.ReadOnly = $true
    $details.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $details.BackColor = [System.Drawing.Color]::White
    $details.Font = [System.Drawing.Font]::new('Consolas',9)
    [void]$layout.Controls.Add($details,0,3)

    $closeProgress = [System.Windows.Forms.Button]::new()
    $closeProgress.Text = 'Close'
    $closeProgress.Enabled = $false
    $closeProgress.Width = 100
    $closeProgress.Anchor = 'Right'
    [void]$layout.Controls.Add($closeProgress,0,4)

    $updated = [System.Collections.Generic.List[string]]::new()
    $current = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()
    $processed = 0
    $completed = $false
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $appendLine = {
        param([string]$Text)
        $stamp = (Get-Date).ToString('HH:mm:ss')
        $details.AppendText("[$stamp] $Text$([Environment]::NewLine)")
        $details.SelectionStart = $details.TextLength
        $details.ScrollToCaret()
    }

    $processRecords = {
        param([object[]]$Records)
        foreach ($record in @($Records)) {
            if (-not $record -or -not $record.RecordType) { continue }
            switch ([string]$record.RecordType) {
                'Start' {
                    $activity.Text = "$($record.Message) ($($record.Position) of $($record.Total))"
                    & $appendLine $record.Message
                }
                'Complete' {
                    $processed = [math]::Max($processed,[int]$record.Position)
                    $progress.Value = [math]::Min($progress.Maximum,$processed)
                    if ([string]$record.Status -eq 'Updated') { $updated.Add([string]$record.Label) }
                    else { $current.Add([string]$record.Label) }
                    & $appendLine $record.Message
                }
                'Failed' {
                    $processed = [math]::Max($processed,[int]$record.Position)
                    $progress.Value = [math]::Min($progress.Maximum,$processed)
                    $failed.Add([string]$record.Message)
                    & $appendLine $record.Message
                }
            }
        }
    }

    $timer = [System.Windows.Forms.Timer]::new()
    $timer.Interval = 250
    $timer.Add_Tick({
        $elapsed.Text = 'Elapsed: ' + $stopwatch.Elapsed.ToString('mm\:ss')
        $records = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
        if ($records.Count -gt 0) { & $processRecords $records }

        if (-not $completed -and $job.State -in @('Completed','Failed','Stopped')) {
            $completed = $true
            $remaining = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
            if ($remaining.Count -gt 0) { & $processRecords $remaining }
            $stopwatch.Stop()
            $timer.Stop()

            if ($job.State -eq 'Failed' -and $job.ChildJobs.Count -gt 0 -and $job.ChildJobs[0].JobStateInfo.Reason) {
                $reason = [string]$job.ChildJobs[0].JobStateInfo.Reason.Message
                if ($reason) {
                    $failed.Add($reason)
                    & $appendLine "Worker failed: $reason"
                }
            }

            $progress.Value = $progress.Maximum
            $activity.Text = "Cache update complete: $($updated.Count) updated, $($current.Count) current, $($failed.Count) failed"
            $elapsed.Text = 'Elapsed: ' + $stopwatch.Elapsed.ToString('mm\:ss')
            $closeProgress.Enabled = $true
            $progressForm.ControlBox = $true
        }
    })
    $closeProgress.Add_Click({ if ($completed) { $progressForm.Close() } })
    $progressForm.Add_FormClosing({ if (-not $completed) { $_.Cancel = $true } })

    try {
        $State.Form.UseWaitCursor = $false
        & $appendLine "Starting $($plan.Count) available update(s)."
        $timer.Start()
        [void]$progressForm.ShowDialog($State.Form)
    }
    finally {
        $timer.Stop()
        $timer.Dispose()
        if ($job.State -notin @('Completed','Failed','Stopped')) { Stop-Job -Job $job -ErrorAction SilentlyContinue }
        Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $progressForm.Dispose()
    }

    [pscustomobject]@{
        Updated = @($updated)
        Current = @($current)
        Skipped = @($current | ForEach-Object { "Already current: $_" })
        Failed  = @($failed)
    }
}
) {
        return [string]$profile.Version
    }
    if ($profile.CustomDownloadSource) {
        throw 'Office uses a custom download source; public CDN version cannot be resolved.'
    }
    $channels = @{
        Current = '492350f6-3a01-4f97-b9c0-c7c6ddf67d60'
        MonthlyEnterprise = '55336b82-a18d-4dd6-b5f6-9e5095c314a6'
        SemiAnnual = '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114'
        CurrentPreview = '64256afe-f5d9-4f86-8936-8840a6a4f5be'
        SemiAnnualPreview = 'b8f9b850-328d-4355-9145-c59439a0c4cf'
        BetaChannel = '5440fd1f-7ecb-4221-8110-145efaa6372f'
    }
    if (-not $channels.ContainsKey([string]$profile.Channel)) {
        throw "No Office CDN version resolver exists for channel '$($profile.Channel)'."
    }

    $cabName = if ([string]$profile.Architecture -eq 'x86') { 'v32.cab' } else { 'v64.cab' }
    $probeRoot = Join-Path ([IO.Path]::GetTempPath()) ("OSDStage-UI-Office-{0}" -f [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $probeRoot -ErrorAction Stop | Out-Null
        $cabPath = Join-Path $probeRoot $cabName
        $uri = 'https://officecdn.microsoft.com/pr/{0}/Office/Data/{1}' -f $channels[[string]$profile.Channel],$cabName
        Invoke-WebRequest -Uri $uri -OutFile $cabPath -UseBasicParsing -TimeoutSec 30 -Headers @{ 'Cache-Control'='no-cache' } -ErrorAction Stop | Out-Null
        $descriptor = Expand-OSDStageOfficeDescriptor -CabPath $cabPath -DestinationPath $probeRoot
        Get-OSDStageOfficeDescriptorVersion -Path $descriptor -Architecture ([string]$profile.Architecture) -ChannelId $channels[[string]$profile.Channel]
    }
    finally {
        if (Test-Path -LiteralPath $probeRoot) {
            Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-OSDStageUIChromeAvailableVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('x64','x86')][string]$Architecture)

    $platform = if ($Architecture -eq 'x64') { 'win64' } else { 'win' }
    $uri = "https://versionhistory.googleapis.com/v1/chrome/platforms/$platform/channels/stable/versions?order_by=version%20desc&page_size=1"
    $response = Invoke-RestMethod -Uri $uri -TimeoutSec 30 -ErrorAction Stop
    $version = @($response.versions | Select-Object -First 1).version
    if ([string]$version -notmatch '^\d+\.\d+\.\d+\.\d+
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)

    "$([string]$Entry.Source):$([string]$Entry.Id):$([string]$Entry.Architecture):$([string]$Entry.Channel):$([string]$Entry.RuntimeType)"
}

function New-OSDStageUICacheUpdatePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    if (-not $State.Snapshot -or -not $State.Snapshot.CachePath) {
        throw 'No OSDStage USB cache is currently connected.'
    }

    # Always refresh release metadata immediately before an update. This avoids
    # applying stale status from a previously connected USB device.
    $State.Status.Text = 'Checking available cache updates...'
    $State.Form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    [void](Update-OSDStageUICacheUpdateStatus -State $State)

    $available = @(
        foreach ($entry in @($State.Snapshot.CacheEntries)) {
            $key = Get-OSDStageUICacheUpdateKey -Entry $entry
            $status = $State.CacheUpdateStatus[$key]
            if ($status -and [string]$status.Status -eq 'Update available') {
                [pscustomobject]@{ Entry=$entry; Status=$status }
            }
        }
    )

    $plan = [System.Collections.Generic.List[object]]::new()

    $repositoryEntries = @($available | Where-Object { [string]$_.Entry.Source -eq 'Repository' })
    if ($repositoryEntries.Count -gt 0) {
        $names = @($repositoryEntries.Entry.Id | Sort-Object -Unique)
        $plan.Add([pscustomobject]@{
            Source       = 'Repository'
            Id           = 'Repository'
            DisplayName  = "Repository packages ($($names.Count))"
            Command      = 'Sync-OSDStageRepository'
            Names        = $names
            Architecture = $null
            Channel      = $null
            RuntimeType  = $null
            Current      = $null
            Latest       = $null
        })
    }

    foreach ($candidate in @($available | Where-Object { [string]$_.Entry.Source -eq 'BuiltIn' })) {
        $entry = $candidate.Entry

        # Only release resolvers that produced an explicit Update available
        # status can reach this plan. Microsoft 365 Apps and other unsupported
        # built-ins therefore cannot be downloaded accidentally.
        $commandName = "Sync-OSDStage$($entry.Id)"
        $command = Get-Command -Name $commandName -Module OSDStage -ErrorAction SilentlyContinue
        if (-not $command) { continue }

        $displayName = if ($entry.DisplayName) { [string]$entry.DisplayName } else { [string]$entry.Id }
        $plan.Add([pscustomobject]@{
            Source       = 'BuiltIn'
            Id           = [string]$entry.Id
            DisplayName  = $displayName
            Command      = $commandName
            Names        = @()
            Architecture = [string]$entry.Architecture
            Channel      = [string]$entry.Channel
            RuntimeType  = [string]$entry.RuntimeType
            Current      = [string]$entry.Version
            Latest       = [string]$candidate.Status.Latest
        })
    }

    @($plan)
}

function Invoke-OSDStageUICacheUpdate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    $plan = @(New-OSDStageUICacheUpdatePlan -State $State)
    if ($plan.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'No supported cache updates are currently available.',
            'OSDStage - Update cache',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return [pscustomobject]@{ Updated=@(); Current=@(); Skipped=@('No updates available'); Failed=@() }
    }

    $summaryLines = @(
        "Update $($plan.Count) available cache item(s)?"
        ''
        @($plan | ForEach-Object {
            if ($_.Latest) { "- $($_.DisplayName): $($_.Current) -> $($_.Latest)" }
            else { "- $($_.DisplayName)" }
        })
        ''
        'Only items marked Update available will be synchronized.'
    )
    $answer = [System.Windows.Forms.MessageBox]::Show(
        ($summaryLines -join [Environment]::NewLine),
        'OSDStage - Update available cache items',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return [pscustomobject]@{ Updated=@(); Current=@(); Skipped=@('Cancelled'); Failed=@() }
    }

    $modulePath = Join-Path $script:moduleRoot 'OSDStage.psd1'
    $catalogUri = (Get-OSDStageConfiguration).CatalogUri
    $payload = [pscustomobject]@{
        ModulePath = $modulePath
        CatalogUri = if ($catalogUri) { $catalogUri.AbsoluteUri } else { $null }
        Tasks      = @($plan)
    }

    $worker = {
        param($Payload)

        $ErrorActionPreference = 'Stop'
        Import-Module -Name ([string]$Payload.ModulePath) -Force -ErrorAction Stop
        if ($Payload.CatalogUri) {
            Set-OSDStageConfiguration -CatalogUri ([uri]$Payload.CatalogUri) | Out-Null
        }

        $tasks = @($Payload.Tasks)
        $total = $tasks.Count
        $position = 0

        foreach ($task in $tasks) {
            $position++
            Write-Output ([pscustomobject]@{
                RecordType = 'Start'
                Position   = $position
                Total      = $total
                Label      = [string]$task.DisplayName
                Message    = "Checking and updating $($task.DisplayName)"
            })

            try {
                if ([string]$task.Source -eq 'Repository') {
                    $names = @($task.Names)
                    Sync-OSDStageRepository -Name $names -Confirm:$false -ErrorAction Stop | Out-Null
                    Write-Output ([pscustomobject]@{
                        RecordType='Complete'; Position=$position; Total=$total
                        Label=[string]$task.DisplayName; Status='Updated'
                        Message="Repository cache synchronized: $($names -join ', ')"
                    })
                    continue
                }

                $parameters = @{}
                if ($task.Architecture) { $parameters.Architecture = [string]$task.Architecture }
                if ($task.Channel) { $parameters.Channel = [string]$task.Channel }
                if ($task.RuntimeType) { $parameters.RuntimeType = [string]$task.RuntimeType }
                $parameters.Confirm = $false

                $result = @(& ([string]$task.Command) @parameters -ErrorAction Stop)
                $updatedFlag = @(
                    $result |
                        Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'Updated' } |
                        Select-Object -Last 1
                )
                $wasUpdated = if ($updatedFlag.Count -gt 0) { [bool]$updatedFlag[0].Updated } else { $true }
                $status = if ($wasUpdated) { 'Updated' } else { 'Already current' }

                Write-Output ([pscustomobject]@{
                    RecordType='Complete'; Position=$position; Total=$total
                    Label=[string]$task.DisplayName; Status=$status
                    Message="$($task.DisplayName): $status"
                })
            }
            catch {
                Write-Output ([pscustomobject]@{
                    RecordType='Failed'; Position=$position; Total=$total
                    Label=[string]$task.DisplayName; Status='Failed'
                    Message="$($task.DisplayName): $($_.Exception.Message)"
                })
            }
        }
    }

    $job = Start-Job -ScriptBlock $worker -ArgumentList $payload
    $progressForm = [System.Windows.Forms.Form]::new()
    $progressForm.Text = 'OSDStage - Updating cache'
    $progressForm.Size = [System.Drawing.Size]::new(660,410)
    $progressForm.MinimumSize = [System.Drawing.Size]::new(560,340)
    $progressForm.StartPosition = 'CenterParent'
    $progressForm.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $progressForm.Font = [System.Drawing.Font]::new('Segoe UI',9)
    $progressForm.ControlBox = $false
    $progressForm.ShowInTaskbar = $false

    $layout = [System.Windows.Forms.TableLayoutPanel]::new()
    $layout.Dock = 'Fill'
    $layout.Padding = [System.Windows.Forms.Padding]::new(12)
    $layout.RowCount = 5
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',32))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',28))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',26))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',42))
    $progressForm.Controls.Add($layout)

    $activity = [System.Windows.Forms.Label]::new()
    $activity.Dock = 'Fill'
    $activity.Font = [System.Drawing.Font]::new('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
    $activity.Text = 'Preparing cache update...'
    [void]$layout.Controls.Add($activity,0,0)

    $progress = [System.Windows.Forms.ProgressBar]::new()
    $progress.Dock = 'Fill'
    $progress.Minimum = 0
    $progress.Maximum = [math]::Max(1,$plan.Count)
    $progress.Value = 0
    $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    [void]$layout.Controls.Add($progress,0,1)

    $elapsed = [System.Windows.Forms.Label]::new()
    $elapsed.Dock = 'Fill'
    $elapsed.Text = 'Elapsed: 00:00'
    [void]$layout.Controls.Add($elapsed,0,2)

    $details = [System.Windows.Forms.TextBox]::new()
    $details.Dock = 'Fill'
    $details.Multiline = $true
    $details.ReadOnly = $true
    $details.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $details.BackColor = [System.Drawing.Color]::White
    $details.Font = [System.Drawing.Font]::new('Consolas',9)
    [void]$layout.Controls.Add($details,0,3)

    $closeProgress = [System.Windows.Forms.Button]::new()
    $closeProgress.Text = 'Close'
    $closeProgress.Enabled = $false
    $closeProgress.Width = 100
    $closeProgress.Anchor = 'Right'
    [void]$layout.Controls.Add($closeProgress,0,4)

    $updated = [System.Collections.Generic.List[string]]::new()
    $current = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()
    $processed = 0
    $completed = $false
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $appendLine = {
        param([string]$Text)
        $stamp = (Get-Date).ToString('HH:mm:ss')
        $details.AppendText("[$stamp] $Text$([Environment]::NewLine)")
        $details.SelectionStart = $details.TextLength
        $details.ScrollToCaret()
    }

    $processRecords = {
        param([object[]]$Records)
        foreach ($record in @($Records)) {
            if (-not $record -or -not $record.RecordType) { continue }
            switch ([string]$record.RecordType) {
                'Start' {
                    $activity.Text = "$($record.Message) ($($record.Position) of $($record.Total))"
                    & $appendLine $record.Message
                }
                'Complete' {
                    $processed = [math]::Max($processed,[int]$record.Position)
                    $progress.Value = [math]::Min($progress.Maximum,$processed)
                    if ([string]$record.Status -eq 'Updated') { $updated.Add([string]$record.Label) }
                    else { $current.Add([string]$record.Label) }
                    & $appendLine $record.Message
                }
                'Failed' {
                    $processed = [math]::Max($processed,[int]$record.Position)
                    $progress.Value = [math]::Min($progress.Maximum,$processed)
                    $failed.Add([string]$record.Message)
                    & $appendLine $record.Message
                }
            }
        }
    }

    $timer = [System.Windows.Forms.Timer]::new()
    $timer.Interval = 250
    $timer.Add_Tick({
        $elapsed.Text = 'Elapsed: ' + $stopwatch.Elapsed.ToString('mm\:ss')
        $records = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
        if ($records.Count -gt 0) { & $processRecords $records }

        if (-not $completed -and $job.State -in @('Completed','Failed','Stopped')) {
            $completed = $true
            $remaining = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
            if ($remaining.Count -gt 0) { & $processRecords $remaining }
            $stopwatch.Stop()
            $timer.Stop()

            if ($job.State -eq 'Failed' -and $job.ChildJobs.Count -gt 0 -and $job.ChildJobs[0].JobStateInfo.Reason) {
                $reason = [string]$job.ChildJobs[0].JobStateInfo.Reason.Message
                if ($reason) {
                    $failed.Add($reason)
                    & $appendLine "Worker failed: $reason"
                }
            }

            $progress.Value = $progress.Maximum
            $activity.Text = "Cache update complete: $($updated.Count) updated, $($current.Count) current, $($failed.Count) failed"
            $elapsed.Text = 'Elapsed: ' + $stopwatch.Elapsed.ToString('mm\:ss')
            $closeProgress.Enabled = $true
            $progressForm.ControlBox = $true
        }
    })
    $closeProgress.Add_Click({ if ($completed) { $progressForm.Close() } })
    $progressForm.Add_FormClosing({ if (-not $completed) { $_.Cancel = $true } })

    try {
        $State.Form.UseWaitCursor = $false
        & $appendLine "Starting $($plan.Count) available update(s)."
        $timer.Start()
        [void]$progressForm.ShowDialog($State.Form)
    }
    finally {
        $timer.Stop()
        $timer.Dispose()
        if ($job.State -notin @('Completed','Failed','Stopped')) { Stop-Job -Job $job -ErrorAction SilentlyContinue }
        Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $progressForm.Dispose()
    }

    [pscustomobject]@{
        Updated = @($updated)
        Current = @($current)
        Skipped = @($current | ForEach-Object { "Already current: $_" })
        Failed  = @($failed)
    }
}
) {
        throw 'Google Chrome VersionHistory did not return a concrete stable version.'
    }
    [string]$version
}

function Get-OSDStageUIFirefoxAvailableVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Rapid','ESR')][string]$Channel)

    $response = Invoke-RestMethod -Uri 'https://product-details.mozilla.org/1.0/firefox_versions.json' -TimeoutSec 30 -ErrorAction Stop
    $raw = if ($Channel -eq 'ESR') { [string]$response.FIREFOX_ESR } else { [string]$response.LATEST_FIREFOX_VERSION }
    $version = $raw -replace '(?i)esr
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)

    "$([string]$Entry.Source):$([string]$Entry.Id):$([string]$Entry.Architecture):$([string]$Entry.Channel):$([string]$Entry.RuntimeType)"
}

function New-OSDStageUICacheUpdatePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    if (-not $State.Snapshot -or -not $State.Snapshot.CachePath) {
        throw 'No OSDStage USB cache is currently connected.'
    }

    # Always refresh release metadata immediately before an update. This avoids
    # applying stale status from a previously connected USB device.
    $State.Status.Text = 'Checking available cache updates...'
    $State.Form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    [void](Update-OSDStageUICacheUpdateStatus -State $State)

    $available = @(
        foreach ($entry in @($State.Snapshot.CacheEntries)) {
            $key = Get-OSDStageUICacheUpdateKey -Entry $entry
            $status = $State.CacheUpdateStatus[$key]
            if ($status -and [string]$status.Status -eq 'Update available') {
                [pscustomobject]@{ Entry=$entry; Status=$status }
            }
        }
    )

    $plan = [System.Collections.Generic.List[object]]::new()

    $repositoryEntries = @($available | Where-Object { [string]$_.Entry.Source -eq 'Repository' })
    if ($repositoryEntries.Count -gt 0) {
        $names = @($repositoryEntries.Entry.Id | Sort-Object -Unique)
        $plan.Add([pscustomobject]@{
            Source       = 'Repository'
            Id           = 'Repository'
            DisplayName  = "Repository packages ($($names.Count))"
            Command      = 'Sync-OSDStageRepository'
            Names        = $names
            Architecture = $null
            Channel      = $null
            RuntimeType  = $null
            Current      = $null
            Latest       = $null
        })
    }

    foreach ($candidate in @($available | Where-Object { [string]$_.Entry.Source -eq 'BuiltIn' })) {
        $entry = $candidate.Entry

        # Only release resolvers that produced an explicit Update available
        # status can reach this plan. Microsoft 365 Apps and other unsupported
        # built-ins therefore cannot be downloaded accidentally.
        $commandName = "Sync-OSDStage$($entry.Id)"
        $command = Get-Command -Name $commandName -Module OSDStage -ErrorAction SilentlyContinue
        if (-not $command) { continue }

        $displayName = if ($entry.DisplayName) { [string]$entry.DisplayName } else { [string]$entry.Id }
        $plan.Add([pscustomobject]@{
            Source       = 'BuiltIn'
            Id           = [string]$entry.Id
            DisplayName  = $displayName
            Command      = $commandName
            Names        = @()
            Architecture = [string]$entry.Architecture
            Channel      = [string]$entry.Channel
            RuntimeType  = [string]$entry.RuntimeType
            Current      = [string]$entry.Version
            Latest       = [string]$candidate.Status.Latest
        })
    }

    @($plan)
}

function Invoke-OSDStageUICacheUpdate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    $plan = @(New-OSDStageUICacheUpdatePlan -State $State)
    if ($plan.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'No supported cache updates are currently available.',
            'OSDStage - Update cache',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return [pscustomobject]@{ Updated=@(); Current=@(); Skipped=@('No updates available'); Failed=@() }
    }

    $summaryLines = @(
        "Update $($plan.Count) available cache item(s)?"
        ''
        @($plan | ForEach-Object {
            if ($_.Latest) { "- $($_.DisplayName): $($_.Current) -> $($_.Latest)" }
            else { "- $($_.DisplayName)" }
        })
        ''
        'Only items marked Update available will be synchronized.'
    )
    $answer = [System.Windows.Forms.MessageBox]::Show(
        ($summaryLines -join [Environment]::NewLine),
        'OSDStage - Update available cache items',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return [pscustomobject]@{ Updated=@(); Current=@(); Skipped=@('Cancelled'); Failed=@() }
    }

    $modulePath = Join-Path $script:moduleRoot 'OSDStage.psd1'
    $catalogUri = (Get-OSDStageConfiguration).CatalogUri
    $payload = [pscustomobject]@{
        ModulePath = $modulePath
        CatalogUri = if ($catalogUri) { $catalogUri.AbsoluteUri } else { $null }
        Tasks      = @($plan)
    }

    $worker = {
        param($Payload)

        $ErrorActionPreference = 'Stop'
        Import-Module -Name ([string]$Payload.ModulePath) -Force -ErrorAction Stop
        if ($Payload.CatalogUri) {
            Set-OSDStageConfiguration -CatalogUri ([uri]$Payload.CatalogUri) | Out-Null
        }

        $tasks = @($Payload.Tasks)
        $total = $tasks.Count
        $position = 0

        foreach ($task in $tasks) {
            $position++
            Write-Output ([pscustomobject]@{
                RecordType = 'Start'
                Position   = $position
                Total      = $total
                Label      = [string]$task.DisplayName
                Message    = "Checking and updating $($task.DisplayName)"
            })

            try {
                if ([string]$task.Source -eq 'Repository') {
                    $names = @($task.Names)
                    Sync-OSDStageRepository -Name $names -Confirm:$false -ErrorAction Stop | Out-Null
                    Write-Output ([pscustomobject]@{
                        RecordType='Complete'; Position=$position; Total=$total
                        Label=[string]$task.DisplayName; Status='Updated'
                        Message="Repository cache synchronized: $($names -join ', ')"
                    })
                    continue
                }

                $parameters = @{}
                if ($task.Architecture) { $parameters.Architecture = [string]$task.Architecture }
                if ($task.Channel) { $parameters.Channel = [string]$task.Channel }
                if ($task.RuntimeType) { $parameters.RuntimeType = [string]$task.RuntimeType }
                $parameters.Confirm = $false

                $result = @(& ([string]$task.Command) @parameters -ErrorAction Stop)
                $updatedFlag = @(
                    $result |
                        Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'Updated' } |
                        Select-Object -Last 1
                )
                $wasUpdated = if ($updatedFlag.Count -gt 0) { [bool]$updatedFlag[0].Updated } else { $true }
                $status = if ($wasUpdated) { 'Updated' } else { 'Already current' }

                Write-Output ([pscustomobject]@{
                    RecordType='Complete'; Position=$position; Total=$total
                    Label=[string]$task.DisplayName; Status=$status
                    Message="$($task.DisplayName): $status"
                })
            }
            catch {
                Write-Output ([pscustomobject]@{
                    RecordType='Failed'; Position=$position; Total=$total
                    Label=[string]$task.DisplayName; Status='Failed'
                    Message="$($task.DisplayName): $($_.Exception.Message)"
                })
            }
        }
    }

    $job = Start-Job -ScriptBlock $worker -ArgumentList $payload
    $progressForm = [System.Windows.Forms.Form]::new()
    $progressForm.Text = 'OSDStage - Updating cache'
    $progressForm.Size = [System.Drawing.Size]::new(660,410)
    $progressForm.MinimumSize = [System.Drawing.Size]::new(560,340)
    $progressForm.StartPosition = 'CenterParent'
    $progressForm.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $progressForm.Font = [System.Drawing.Font]::new('Segoe UI',9)
    $progressForm.ControlBox = $false
    $progressForm.ShowInTaskbar = $false

    $layout = [System.Windows.Forms.TableLayoutPanel]::new()
    $layout.Dock = 'Fill'
    $layout.Padding = [System.Windows.Forms.Padding]::new(12)
    $layout.RowCount = 5
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',32))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',28))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',26))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',42))
    $progressForm.Controls.Add($layout)

    $activity = [System.Windows.Forms.Label]::new()
    $activity.Dock = 'Fill'
    $activity.Font = [System.Drawing.Font]::new('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
    $activity.Text = 'Preparing cache update...'
    [void]$layout.Controls.Add($activity,0,0)

    $progress = [System.Windows.Forms.ProgressBar]::new()
    $progress.Dock = 'Fill'
    $progress.Minimum = 0
    $progress.Maximum = [math]::Max(1,$plan.Count)
    $progress.Value = 0
    $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    [void]$layout.Controls.Add($progress,0,1)

    $elapsed = [System.Windows.Forms.Label]::new()
    $elapsed.Dock = 'Fill'
    $elapsed.Text = 'Elapsed: 00:00'
    [void]$layout.Controls.Add($elapsed,0,2)

    $details = [System.Windows.Forms.TextBox]::new()
    $details.Dock = 'Fill'
    $details.Multiline = $true
    $details.ReadOnly = $true
    $details.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $details.BackColor = [System.Drawing.Color]::White
    $details.Font = [System.Drawing.Font]::new('Consolas',9)
    [void]$layout.Controls.Add($details,0,3)

    $closeProgress = [System.Windows.Forms.Button]::new()
    $closeProgress.Text = 'Close'
    $closeProgress.Enabled = $false
    $closeProgress.Width = 100
    $closeProgress.Anchor = 'Right'
    [void]$layout.Controls.Add($closeProgress,0,4)

    $updated = [System.Collections.Generic.List[string]]::new()
    $current = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()
    $processed = 0
    $completed = $false
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $appendLine = {
        param([string]$Text)
        $stamp = (Get-Date).ToString('HH:mm:ss')
        $details.AppendText("[$stamp] $Text$([Environment]::NewLine)")
        $details.SelectionStart = $details.TextLength
        $details.ScrollToCaret()
    }

    $processRecords = {
        param([object[]]$Records)
        foreach ($record in @($Records)) {
            if (-not $record -or -not $record.RecordType) { continue }
            switch ([string]$record.RecordType) {
                'Start' {
                    $activity.Text = "$($record.Message) ($($record.Position) of $($record.Total))"
                    & $appendLine $record.Message
                }
                'Complete' {
                    $processed = [math]::Max($processed,[int]$record.Position)
                    $progress.Value = [math]::Min($progress.Maximum,$processed)
                    if ([string]$record.Status -eq 'Updated') { $updated.Add([string]$record.Label) }
                    else { $current.Add([string]$record.Label) }
                    & $appendLine $record.Message
                }
                'Failed' {
                    $processed = [math]::Max($processed,[int]$record.Position)
                    $progress.Value = [math]::Min($progress.Maximum,$processed)
                    $failed.Add([string]$record.Message)
                    & $appendLine $record.Message
                }
            }
        }
    }

    $timer = [System.Windows.Forms.Timer]::new()
    $timer.Interval = 250
    $timer.Add_Tick({
        $elapsed.Text = 'Elapsed: ' + $stopwatch.Elapsed.ToString('mm\:ss')
        $records = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
        if ($records.Count -gt 0) { & $processRecords $records }

        if (-not $completed -and $job.State -in @('Completed','Failed','Stopped')) {
            $completed = $true
            $remaining = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
            if ($remaining.Count -gt 0) { & $processRecords $remaining }
            $stopwatch.Stop()
            $timer.Stop()

            if ($job.State -eq 'Failed' -and $job.ChildJobs.Count -gt 0 -and $job.ChildJobs[0].JobStateInfo.Reason) {
                $reason = [string]$job.ChildJobs[0].JobStateInfo.Reason.Message
                if ($reason) {
                    $failed.Add($reason)
                    & $appendLine "Worker failed: $reason"
                }
            }

            $progress.Value = $progress.Maximum
            $activity.Text = "Cache update complete: $($updated.Count) updated, $($current.Count) current, $($failed.Count) failed"
            $elapsed.Text = 'Elapsed: ' + $stopwatch.Elapsed.ToString('mm\:ss')
            $closeProgress.Enabled = $true
            $progressForm.ControlBox = $true
        }
    })
    $closeProgress.Add_Click({ if ($completed) { $progressForm.Close() } })
    $progressForm.Add_FormClosing({ if (-not $completed) { $_.Cancel = $true } })

    try {
        $State.Form.UseWaitCursor = $false
        & $appendLine "Starting $($plan.Count) available update(s)."
        $timer.Start()
        [void]$progressForm.ShowDialog($State.Form)
    }
    finally {
        $timer.Stop()
        $timer.Dispose()
        if ($job.State -notin @('Completed','Failed','Stopped')) { Stop-Job -Job $job -ErrorAction SilentlyContinue }
        Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $progressForm.Dispose()
    }

    [pscustomobject]@{
        Updated = @($updated)
        Current = @($current)
        Skipped = @($current | ForEach-Object { "Already current: $_" })
        Failed  = @($failed)
    }
}
,''
    if ($version -notmatch '^\d+(?:\.\d+){1,3}
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)

    "$([string]$Entry.Source):$([string]$Entry.Id):$([string]$Entry.Architecture):$([string]$Entry.Channel):$([string]$Entry.RuntimeType)"
}

function New-OSDStageUICacheUpdatePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    if (-not $State.Snapshot -or -not $State.Snapshot.CachePath) {
        throw 'No OSDStage USB cache is currently connected.'
    }

    # Always refresh release metadata immediately before an update. This avoids
    # applying stale status from a previously connected USB device.
    $State.Status.Text = 'Checking available cache updates...'
    $State.Form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    [void](Update-OSDStageUICacheUpdateStatus -State $State)

    $available = @(
        foreach ($entry in @($State.Snapshot.CacheEntries)) {
            $key = Get-OSDStageUICacheUpdateKey -Entry $entry
            $status = $State.CacheUpdateStatus[$key]
            if ($status -and [string]$status.Status -eq 'Update available') {
                [pscustomobject]@{ Entry=$entry; Status=$status }
            }
        }
    )

    $plan = [System.Collections.Generic.List[object]]::new()

    $repositoryEntries = @($available | Where-Object { [string]$_.Entry.Source -eq 'Repository' })
    if ($repositoryEntries.Count -gt 0) {
        $names = @($repositoryEntries.Entry.Id | Sort-Object -Unique)
        $plan.Add([pscustomobject]@{
            Source       = 'Repository'
            Id           = 'Repository'
            DisplayName  = "Repository packages ($($names.Count))"
            Command      = 'Sync-OSDStageRepository'
            Names        = $names
            Architecture = $null
            Channel      = $null
            RuntimeType  = $null
            Current      = $null
            Latest       = $null
        })
    }

    foreach ($candidate in @($available | Where-Object { [string]$_.Entry.Source -eq 'BuiltIn' })) {
        $entry = $candidate.Entry

        # Only release resolvers that produced an explicit Update available
        # status can reach this plan. Microsoft 365 Apps and other unsupported
        # built-ins therefore cannot be downloaded accidentally.
        $commandName = "Sync-OSDStage$($entry.Id)"
        $command = Get-Command -Name $commandName -Module OSDStage -ErrorAction SilentlyContinue
        if (-not $command) { continue }

        $displayName = if ($entry.DisplayName) { [string]$entry.DisplayName } else { [string]$entry.Id }
        $plan.Add([pscustomobject]@{
            Source       = 'BuiltIn'
            Id           = [string]$entry.Id
            DisplayName  = $displayName
            Command      = $commandName
            Names        = @()
            Architecture = [string]$entry.Architecture
            Channel      = [string]$entry.Channel
            RuntimeType  = [string]$entry.RuntimeType
            Current      = [string]$entry.Version
            Latest       = [string]$candidate.Status.Latest
        })
    }

    @($plan)
}

function Invoke-OSDStageUICacheUpdate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    $plan = @(New-OSDStageUICacheUpdatePlan -State $State)
    if ($plan.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'No supported cache updates are currently available.',
            'OSDStage - Update cache',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return [pscustomobject]@{ Updated=@(); Current=@(); Skipped=@('No updates available'); Failed=@() }
    }

    $summaryLines = @(
        "Update $($plan.Count) available cache item(s)?"
        ''
        @($plan | ForEach-Object {
            if ($_.Latest) { "- $($_.DisplayName): $($_.Current) -> $($_.Latest)" }
            else { "- $($_.DisplayName)" }
        })
        ''
        'Only items marked Update available will be synchronized.'
    )
    $answer = [System.Windows.Forms.MessageBox]::Show(
        ($summaryLines -join [Environment]::NewLine),
        'OSDStage - Update available cache items',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return [pscustomobject]@{ Updated=@(); Current=@(); Skipped=@('Cancelled'); Failed=@() }
    }

    $modulePath = Join-Path $script:moduleRoot 'OSDStage.psd1'
    $catalogUri = (Get-OSDStageConfiguration).CatalogUri
    $payload = [pscustomobject]@{
        ModulePath = $modulePath
        CatalogUri = if ($catalogUri) { $catalogUri.AbsoluteUri } else { $null }
        Tasks      = @($plan)
    }

    $worker = {
        param($Payload)

        $ErrorActionPreference = 'Stop'
        Import-Module -Name ([string]$Payload.ModulePath) -Force -ErrorAction Stop
        if ($Payload.CatalogUri) {
            Set-OSDStageConfiguration -CatalogUri ([uri]$Payload.CatalogUri) | Out-Null
        }

        $tasks = @($Payload.Tasks)
        $total = $tasks.Count
        $position = 0

        foreach ($task in $tasks) {
            $position++
            Write-Output ([pscustomobject]@{
                RecordType = 'Start'
                Position   = $position
                Total      = $total
                Label      = [string]$task.DisplayName
                Message    = "Checking and updating $($task.DisplayName)"
            })

            try {
                if ([string]$task.Source -eq 'Repository') {
                    $names = @($task.Names)
                    Sync-OSDStageRepository -Name $names -Confirm:$false -ErrorAction Stop | Out-Null
                    Write-Output ([pscustomobject]@{
                        RecordType='Complete'; Position=$position; Total=$total
                        Label=[string]$task.DisplayName; Status='Updated'
                        Message="Repository cache synchronized: $($names -join ', ')"
                    })
                    continue
                }

                $parameters = @{}
                if ($task.Architecture) { $parameters.Architecture = [string]$task.Architecture }
                if ($task.Channel) { $parameters.Channel = [string]$task.Channel }
                if ($task.RuntimeType) { $parameters.RuntimeType = [string]$task.RuntimeType }
                $parameters.Confirm = $false

                $result = @(& ([string]$task.Command) @parameters -ErrorAction Stop)
                $updatedFlag = @(
                    $result |
                        Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'Updated' } |
                        Select-Object -Last 1
                )
                $wasUpdated = if ($updatedFlag.Count -gt 0) { [bool]$updatedFlag[0].Updated } else { $true }
                $status = if ($wasUpdated) { 'Updated' } else { 'Already current' }

                Write-Output ([pscustomobject]@{
                    RecordType='Complete'; Position=$position; Total=$total
                    Label=[string]$task.DisplayName; Status=$status
                    Message="$($task.DisplayName): $status"
                })
            }
            catch {
                Write-Output ([pscustomobject]@{
                    RecordType='Failed'; Position=$position; Total=$total
                    Label=[string]$task.DisplayName; Status='Failed'
                    Message="$($task.DisplayName): $($_.Exception.Message)"
                })
            }
        }
    }

    $job = Start-Job -ScriptBlock $worker -ArgumentList $payload
    $progressForm = [System.Windows.Forms.Form]::new()
    $progressForm.Text = 'OSDStage - Updating cache'
    $progressForm.Size = [System.Drawing.Size]::new(660,410)
    $progressForm.MinimumSize = [System.Drawing.Size]::new(560,340)
    $progressForm.StartPosition = 'CenterParent'
    $progressForm.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $progressForm.Font = [System.Drawing.Font]::new('Segoe UI',9)
    $progressForm.ControlBox = $false
    $progressForm.ShowInTaskbar = $false

    $layout = [System.Windows.Forms.TableLayoutPanel]::new()
    $layout.Dock = 'Fill'
    $layout.Padding = [System.Windows.Forms.Padding]::new(12)
    $layout.RowCount = 5
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',32))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',28))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',26))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',42))
    $progressForm.Controls.Add($layout)

    $activity = [System.Windows.Forms.Label]::new()
    $activity.Dock = 'Fill'
    $activity.Font = [System.Drawing.Font]::new('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
    $activity.Text = 'Preparing cache update...'
    [void]$layout.Controls.Add($activity,0,0)

    $progress = [System.Windows.Forms.ProgressBar]::new()
    $progress.Dock = 'Fill'
    $progress.Minimum = 0
    $progress.Maximum = [math]::Max(1,$plan.Count)
    $progress.Value = 0
    $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    [void]$layout.Controls.Add($progress,0,1)

    $elapsed = [System.Windows.Forms.Label]::new()
    $elapsed.Dock = 'Fill'
    $elapsed.Text = 'Elapsed: 00:00'
    [void]$layout.Controls.Add($elapsed,0,2)

    $details = [System.Windows.Forms.TextBox]::new()
    $details.Dock = 'Fill'
    $details.Multiline = $true
    $details.ReadOnly = $true
    $details.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $details.BackColor = [System.Drawing.Color]::White
    $details.Font = [System.Drawing.Font]::new('Consolas',9)
    [void]$layout.Controls.Add($details,0,3)

    $closeProgress = [System.Windows.Forms.Button]::new()
    $closeProgress.Text = 'Close'
    $closeProgress.Enabled = $false
    $closeProgress.Width = 100
    $closeProgress.Anchor = 'Right'
    [void]$layout.Controls.Add($closeProgress,0,4)

    $updated = [System.Collections.Generic.List[string]]::new()
    $current = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()
    $processed = 0
    $completed = $false
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $appendLine = {
        param([string]$Text)
        $stamp = (Get-Date).ToString('HH:mm:ss')
        $details.AppendText("[$stamp] $Text$([Environment]::NewLine)")
        $details.SelectionStart = $details.TextLength
        $details.ScrollToCaret()
    }

    $processRecords = {
        param([object[]]$Records)
        foreach ($record in @($Records)) {
            if (-not $record -or -not $record.RecordType) { continue }
            switch ([string]$record.RecordType) {
                'Start' {
                    $activity.Text = "$($record.Message) ($($record.Position) of $($record.Total))"
                    & $appendLine $record.Message
                }
                'Complete' {
                    $processed = [math]::Max($processed,[int]$record.Position)
                    $progress.Value = [math]::Min($progress.Maximum,$processed)
                    if ([string]$record.Status -eq 'Updated') { $updated.Add([string]$record.Label) }
                    else { $current.Add([string]$record.Label) }
                    & $appendLine $record.Message
                }
                'Failed' {
                    $processed = [math]::Max($processed,[int]$record.Position)
                    $progress.Value = [math]::Min($progress.Maximum,$processed)
                    $failed.Add([string]$record.Message)
                    & $appendLine $record.Message
                }
            }
        }
    }

    $timer = [System.Windows.Forms.Timer]::new()
    $timer.Interval = 250
    $timer.Add_Tick({
        $elapsed.Text = 'Elapsed: ' + $stopwatch.Elapsed.ToString('mm\:ss')
        $records = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
        if ($records.Count -gt 0) { & $processRecords $records }

        if (-not $completed -and $job.State -in @('Completed','Failed','Stopped')) {
            $completed = $true
            $remaining = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
            if ($remaining.Count -gt 0) { & $processRecords $remaining }
            $stopwatch.Stop()
            $timer.Stop()

            if ($job.State -eq 'Failed' -and $job.ChildJobs.Count -gt 0 -and $job.ChildJobs[0].JobStateInfo.Reason) {
                $reason = [string]$job.ChildJobs[0].JobStateInfo.Reason.Message
                if ($reason) {
                    $failed.Add($reason)
                    & $appendLine "Worker failed: $reason"
                }
            }

            $progress.Value = $progress.Maximum
            $activity.Text = "Cache update complete: $($updated.Count) updated, $($current.Count) current, $($failed.Count) failed"
            $elapsed.Text = 'Elapsed: ' + $stopwatch.Elapsed.ToString('mm\:ss')
            $closeProgress.Enabled = $true
            $progressForm.ControlBox = $true
        }
    })
    $closeProgress.Add_Click({ if ($completed) { $progressForm.Close() } })
    $progressForm.Add_FormClosing({ if (-not $completed) { $_.Cancel = $true } })

    try {
        $State.Form.UseWaitCursor = $false
        & $appendLine "Starting $($plan.Count) available update(s)."
        $timer.Start()
        [void]$progressForm.ShowDialog($State.Form)
    }
    finally {
        $timer.Stop()
        $timer.Dispose()
        if ($job.State -notin @('Completed','Failed','Stopped')) { Stop-Job -Job $job -ErrorAction SilentlyContinue }
        Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $progressForm.Dispose()
    }

    [pscustomobject]@{
        Updated = @($updated)
        Current = @($current)
        Skipped = @($current | ForEach-Object { "Already current: $_" })
        Failed  = @($failed)
    }
}
) {
        throw "Mozilla product details did not return a concrete $Channel version."
    }
    $version
}

function Get-OSDStageUIRemotePackageUri {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)

    switch ([string]$Entry.Id) {
        'MicrosoftTeams' {
            switch ([string]$Entry.Architecture) {
                'x86' { return [uri]'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196060' }
                'arm64' { return [uri]'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196207' }
                default { return [uri]'https://go.microsoft.com/fwlink/?linkid=2196106' }
            }
        }
        'AdobeAcrobatUnified' {
            if ([string]$Entry.Architecture -eq 'x86') { return [uri]'https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_WWMUI.zip' }
            return [uri]'https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_x64_WWMUI.zip'
        }
        'CiscoWebex' {
            if ([string]$Entry.Architecture -eq 'arm64') { return [uri]'https://binaries.webex.com/WebexOfclDesktop-Win-Arm-64-Gold/Webex_en.msi' }
            return [uri]'https://binaries.webex.com/WebexOfclDesktop-Win-64-Gold/Webex_en.msi'
        }
        'ZoomWorkplace' {
            if ([string]$Entry.Architecture -eq 'arm64') { return [uri]'https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=winarm64' }
            return [uri]'https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=x64'
        }
        'MicrosoftCompanyPortal' {
            return [uri]'https://download.microsoft.com/download/ac93b367-7b17-4838-a079-c6f3377bf582/CompanyPortal-Universal-Production_x64_x86_ARM_ARM64.appxupload_Windows10_PreinstallKit.zip'
        }
        default { return $null }
    }
}

function Get-OSDStageUIRemoteMetadataStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)

    $uri = Get-OSDStageUIRemotePackageUri -Entry $Entry
    if (-not $uri) { throw "No remote metadata resolver exists for '$($Entry.Id)'." }

    $infoPath = Join-Path ([string]$Entry.CachePath) 'CacheInfo.json'
    if (-not (Test-Path -LiteralPath $infoPath -PathType Leaf)) {
        throw 'CacheInfo.json is missing.'
    }
    $previous = Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $remote = Get-OSDStageRemoteFileMetadata -Uri $uri

    $matches = $false
    if ($remote.ETag -and $previous.RemoteETag) {
        $matches = [string]$remote.ETag -eq [string]$previous.RemoteETag
    }
    elseif ($remote.LastModified -and $previous.RemoteLastModified -and $remote.ContentLength -and $previous.RemoteContentLength) {
        $matches = (
            [string]$remote.LastModified -eq [string]$previous.RemoteLastModified -and
            [long]$remote.ContentLength -eq [long]$previous.RemoteContentLength
        )
    }

    [pscustomobject]@{
        Current = $matches
        Latest = if ($matches) { [string]$Entry.Version } else { $null }
        Detail = if ($matches) {
            'Remote vendor metadata matches the cached payload.'
        } else {
            'Remote vendor metadata changed. The vendor endpoint does not expose the exact product version before acquisition.'
        }
    }
}

function Get-OSDStageUICMTraceAvailableVersion {
    [CmdletBinding()]
    param()
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/adamgell/cmtraceopen/releases/latest' -Headers @{ 'User-Agent'='OSDStage'; Accept='application/vnd.github+json' } -TimeoutSec 30 -ErrorAction Stop
    if ($release.draft -or $release.prerelease -or [string]$release.tag_name -notmatch '^v(?<Version>\d+\.\d+\.\d+)
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)

    "$([string]$Entry.Source):$([string]$Entry.Id):$([string]$Entry.Architecture):$([string]$Entry.Channel):$([string]$Entry.RuntimeType)"
}

function New-OSDStageUICacheUpdatePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    if (-not $State.Snapshot -or -not $State.Snapshot.CachePath) {
        throw 'No OSDStage USB cache is currently connected.'
    }

    # Always refresh release metadata immediately before an update. This avoids
    # applying stale status from a previously connected USB device.
    $State.Status.Text = 'Checking available cache updates...'
    $State.Form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    [void](Update-OSDStageUICacheUpdateStatus -State $State)

    $available = @(
        foreach ($entry in @($State.Snapshot.CacheEntries)) {
            $key = Get-OSDStageUICacheUpdateKey -Entry $entry
            $status = $State.CacheUpdateStatus[$key]
            if ($status -and [string]$status.Status -eq 'Update available') {
                [pscustomobject]@{ Entry=$entry; Status=$status }
            }
        }
    )

    $plan = [System.Collections.Generic.List[object]]::new()

    $repositoryEntries = @($available | Where-Object { [string]$_.Entry.Source -eq 'Repository' })
    if ($repositoryEntries.Count -gt 0) {
        $names = @($repositoryEntries.Entry.Id | Sort-Object -Unique)
        $plan.Add([pscustomobject]@{
            Source       = 'Repository'
            Id           = 'Repository'
            DisplayName  = "Repository packages ($($names.Count))"
            Command      = 'Sync-OSDStageRepository'
            Names        = $names
            Architecture = $null
            Channel      = $null
            RuntimeType  = $null
            Current      = $null
            Latest       = $null
        })
    }

    foreach ($candidate in @($available | Where-Object { [string]$_.Entry.Source -eq 'BuiltIn' })) {
        $entry = $candidate.Entry

        # Only release resolvers that produced an explicit Update available
        # status can reach this plan. Microsoft 365 Apps and other unsupported
        # built-ins therefore cannot be downloaded accidentally.
        $commandName = "Sync-OSDStage$($entry.Id)"
        $command = Get-Command -Name $commandName -Module OSDStage -ErrorAction SilentlyContinue
        if (-not $command) { continue }

        $displayName = if ($entry.DisplayName) { [string]$entry.DisplayName } else { [string]$entry.Id }
        $plan.Add([pscustomobject]@{
            Source       = 'BuiltIn'
            Id           = [string]$entry.Id
            DisplayName  = $displayName
            Command      = $commandName
            Names        = @()
            Architecture = [string]$entry.Architecture
            Channel      = [string]$entry.Channel
            RuntimeType  = [string]$entry.RuntimeType
            Current      = [string]$entry.Version
            Latest       = [string]$candidate.Status.Latest
        })
    }

    @($plan)
}

function Invoke-OSDStageUICacheUpdate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    $plan = @(New-OSDStageUICacheUpdatePlan -State $State)
    if ($plan.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'No supported cache updates are currently available.',
            'OSDStage - Update cache',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return [pscustomobject]@{ Updated=@(); Current=@(); Skipped=@('No updates available'); Failed=@() }
    }

    $summaryLines = @(
        "Update $($plan.Count) available cache item(s)?"
        ''
        @($plan | ForEach-Object {
            if ($_.Latest) { "- $($_.DisplayName): $($_.Current) -> $($_.Latest)" }
            else { "- $($_.DisplayName)" }
        })
        ''
        'Only items marked Update available will be synchronized.'
    )
    $answer = [System.Windows.Forms.MessageBox]::Show(
        ($summaryLines -join [Environment]::NewLine),
        'OSDStage - Update available cache items',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return [pscustomobject]@{ Updated=@(); Current=@(); Skipped=@('Cancelled'); Failed=@() }
    }

    $modulePath = Join-Path $script:moduleRoot 'OSDStage.psd1'
    $catalogUri = (Get-OSDStageConfiguration).CatalogUri
    $payload = [pscustomobject]@{
        ModulePath = $modulePath
        CatalogUri = if ($catalogUri) { $catalogUri.AbsoluteUri } else { $null }
        Tasks      = @($plan)
    }

    $worker = {
        param($Payload)

        $ErrorActionPreference = 'Stop'
        Import-Module -Name ([string]$Payload.ModulePath) -Force -ErrorAction Stop
        if ($Payload.CatalogUri) {
            Set-OSDStageConfiguration -CatalogUri ([uri]$Payload.CatalogUri) | Out-Null
        }

        $tasks = @($Payload.Tasks)
        $total = $tasks.Count
        $position = 0

        foreach ($task in $tasks) {
            $position++
            Write-Output ([pscustomobject]@{
                RecordType = 'Start'
                Position   = $position
                Total      = $total
                Label      = [string]$task.DisplayName
                Message    = "Checking and updating $($task.DisplayName)"
            })

            try {
                if ([string]$task.Source -eq 'Repository') {
                    $names = @($task.Names)
                    Sync-OSDStageRepository -Name $names -Confirm:$false -ErrorAction Stop | Out-Null
                    Write-Output ([pscustomobject]@{
                        RecordType='Complete'; Position=$position; Total=$total
                        Label=[string]$task.DisplayName; Status='Updated'
                        Message="Repository cache synchronized: $($names -join ', ')"
                    })
                    continue
                }

                $parameters = @{}
                if ($task.Architecture) { $parameters.Architecture = [string]$task.Architecture }
                if ($task.Channel) { $parameters.Channel = [string]$task.Channel }
                if ($task.RuntimeType) { $parameters.RuntimeType = [string]$task.RuntimeType }
                $parameters.Confirm = $false

                $result = @(& ([string]$task.Command) @parameters -ErrorAction Stop)
                $updatedFlag = @(
                    $result |
                        Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'Updated' } |
                        Select-Object -Last 1
                )
                $wasUpdated = if ($updatedFlag.Count -gt 0) { [bool]$updatedFlag[0].Updated } else { $true }
                $status = if ($wasUpdated) { 'Updated' } else { 'Already current' }

                Write-Output ([pscustomobject]@{
                    RecordType='Complete'; Position=$position; Total=$total
                    Label=[string]$task.DisplayName; Status=$status
                    Message="$($task.DisplayName): $status"
                })
            }
            catch {
                Write-Output ([pscustomobject]@{
                    RecordType='Failed'; Position=$position; Total=$total
                    Label=[string]$task.DisplayName; Status='Failed'
                    Message="$($task.DisplayName): $($_.Exception.Message)"
                })
            }
        }
    }

    $job = Start-Job -ScriptBlock $worker -ArgumentList $payload
    $progressForm = [System.Windows.Forms.Form]::new()
    $progressForm.Text = 'OSDStage - Updating cache'
    $progressForm.Size = [System.Drawing.Size]::new(660,410)
    $progressForm.MinimumSize = [System.Drawing.Size]::new(560,340)
    $progressForm.StartPosition = 'CenterParent'
    $progressForm.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $progressForm.Font = [System.Drawing.Font]::new('Segoe UI',9)
    $progressForm.ControlBox = $false
    $progressForm.ShowInTaskbar = $false

    $layout = [System.Windows.Forms.TableLayoutPanel]::new()
    $layout.Dock = 'Fill'
    $layout.Padding = [System.Windows.Forms.Padding]::new(12)
    $layout.RowCount = 5
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',32))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',28))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',26))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',42))
    $progressForm.Controls.Add($layout)

    $activity = [System.Windows.Forms.Label]::new()
    $activity.Dock = 'Fill'
    $activity.Font = [System.Drawing.Font]::new('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
    $activity.Text = 'Preparing cache update...'
    [void]$layout.Controls.Add($activity,0,0)

    $progress = [System.Windows.Forms.ProgressBar]::new()
    $progress.Dock = 'Fill'
    $progress.Minimum = 0
    $progress.Maximum = [math]::Max(1,$plan.Count)
    $progress.Value = 0
    $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    [void]$layout.Controls.Add($progress,0,1)

    $elapsed = [System.Windows.Forms.Label]::new()
    $elapsed.Dock = 'Fill'
    $elapsed.Text = 'Elapsed: 00:00'
    [void]$layout.Controls.Add($elapsed,0,2)

    $details = [System.Windows.Forms.TextBox]::new()
    $details.Dock = 'Fill'
    $details.Multiline = $true
    $details.ReadOnly = $true
    $details.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $details.BackColor = [System.Drawing.Color]::White
    $details.Font = [System.Drawing.Font]::new('Consolas',9)
    [void]$layout.Controls.Add($details,0,3)

    $closeProgress = [System.Windows.Forms.Button]::new()
    $closeProgress.Text = 'Close'
    $closeProgress.Enabled = $false
    $closeProgress.Width = 100
    $closeProgress.Anchor = 'Right'
    [void]$layout.Controls.Add($closeProgress,0,4)

    $updated = [System.Collections.Generic.List[string]]::new()
    $current = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()
    $processed = 0
    $completed = $false
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $appendLine = {
        param([string]$Text)
        $stamp = (Get-Date).ToString('HH:mm:ss')
        $details.AppendText("[$stamp] $Text$([Environment]::NewLine)")
        $details.SelectionStart = $details.TextLength
        $details.ScrollToCaret()
    }

    $processRecords = {
        param([object[]]$Records)
        foreach ($record in @($Records)) {
            if (-not $record -or -not $record.RecordType) { continue }
            switch ([string]$record.RecordType) {
                'Start' {
                    $activity.Text = "$($record.Message) ($($record.Position) of $($record.Total))"
                    & $appendLine $record.Message
                }
                'Complete' {
                    $processed = [math]::Max($processed,[int]$record.Position)
                    $progress.Value = [math]::Min($progress.Maximum,$processed)
                    if ([string]$record.Status -eq 'Updated') { $updated.Add([string]$record.Label) }
                    else { $current.Add([string]$record.Label) }
                    & $appendLine $record.Message
                }
                'Failed' {
                    $processed = [math]::Max($processed,[int]$record.Position)
                    $progress.Value = [math]::Min($progress.Maximum,$processed)
                    $failed.Add([string]$record.Message)
                    & $appendLine $record.Message
                }
            }
        }
    }

    $timer = [System.Windows.Forms.Timer]::new()
    $timer.Interval = 250
    $timer.Add_Tick({
        $elapsed.Text = 'Elapsed: ' + $stopwatch.Elapsed.ToString('mm\:ss')
        $records = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
        if ($records.Count -gt 0) { & $processRecords $records }

        if (-not $completed -and $job.State -in @('Completed','Failed','Stopped')) {
            $completed = $true
            $remaining = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
            if ($remaining.Count -gt 0) { & $processRecords $remaining }
            $stopwatch.Stop()
            $timer.Stop()

            if ($job.State -eq 'Failed' -and $job.ChildJobs.Count -gt 0 -and $job.ChildJobs[0].JobStateInfo.Reason) {
                $reason = [string]$job.ChildJobs[0].JobStateInfo.Reason.Message
                if ($reason) {
                    $failed.Add($reason)
                    & $appendLine "Worker failed: $reason"
                }
            }

            $progress.Value = $progress.Maximum
            $activity.Text = "Cache update complete: $($updated.Count) updated, $($current.Count) current, $($failed.Count) failed"
            $elapsed.Text = 'Elapsed: ' + $stopwatch.Elapsed.ToString('mm\:ss')
            $closeProgress.Enabled = $true
            $progressForm.ControlBox = $true
        }
    })
    $closeProgress.Add_Click({ if ($completed) { $progressForm.Close() } })
    $progressForm.Add_FormClosing({ if (-not $completed) { $_.Cancel = $true } })

    try {
        $State.Form.UseWaitCursor = $false
        & $appendLine "Starting $($plan.Count) available update(s)."
        $timer.Start()
        [void]$progressForm.ShowDialog($State.Form)
    }
    finally {
        $timer.Stop()
        $timer.Dispose()
        if ($job.State -notin @('Completed','Failed','Stopped')) { Stop-Job -Job $job -ErrorAction SilentlyContinue }
        Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $progressForm.Dispose()
    }

    [pscustomobject]@{
        Updated = @($updated)
        Current = @($current)
        Skipped = @($current | ForEach-Object { "Already current: $_" })
        Failed  = @($failed)
    }
}
) {
        throw 'CMTrace Open latest release is not a supported stable release.'
    }
    [string]$Matches.Version
}

function Get-OSDStageUICacheUpdateStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter()]$RepositoryCatalog
    )

    $current = [string]$Entry.Version
    $latest = $null
    $status = 'Check failed'
    $detail = $null

    try {
        if ([string]$Entry.Source -eq 'Repository') {
            if (-not $RepositoryCatalog) {
                return [pscustomobject]@{ Latest=$null; Status='Catalog not configured'; Detail='No repository catalog is available.' }
            }
            $matches = @($RepositoryCatalog.Packages | Where-Object {
                [string]$_.Id -eq [string]$Entry.Id -and
                (-not $_.Architecture -or -not $Entry.Architecture -or [string]$_.Architecture -eq [string]$Entry.Architecture)
            })
            if ($matches.Count -eq 1) {
                $latest = [string]$matches[0].Version
                $status = if ($latest -and $current -and $latest -ne $current) { 'Update available' } else { 'Current' }
            }
            elseif ($matches.Count -eq 0) { $status = 'Not in catalog' }
            else { $status = 'Check failed'; $detail = 'Multiple repository variants matched this cached configuration.' }
        }
        else {
            switch ([string]$Entry.Id) {
                'Microsoft365Apps' {
                    $latest = Get-OSDStageUIOfficeAvailableVersion -Entry $Entry
                }
                'GoogleChromeEnterprise' {
                    $latest = Get-OSDStageUIChromeAvailableVersion -Architecture ([string]$Entry.Architecture)
                }
                'MozillaFirefoxEnterprise' {
                    $latest = Get-OSDStageUIFirefoxAvailableVersion -Channel $(if ($Entry.Channel) { [string]$Entry.Channel } else { 'Rapid' })
                }
                '7Zip' {
                    $latest = [string](Get-OSDStage7ZipRelease -Architecture ([string]$Entry.Architecture)).Version
                }
                'VisualStudioCode' {
                    $latest = [string](Get-OSDStageVisualStudioCodeRelease -Architecture ([string]$Entry.Architecture)).Version
                }
                'DotNetRuntime' {
                    $spec = Get-OSDStagePrerequisiteSpec -Family DotNetRuntime -Architecture ([string]$Entry.Architecture) -Channel ([string]$Entry.Channel) -RuntimeType ([string]$Entry.RuntimeType)
                    $latest = [string](Get-OSDStagePrerequisiteRelease -Spec $spec).Version
                }
                'VisualCRedist' {
                    $spec = Get-OSDStagePrerequisiteSpec -Family VisualCRedist -Architecture ([string]$Entry.Architecture)
                    $latest = [string](Get-OSDStagePrerequisiteRelease -Spec $spec).Version
                }
                'CMTraceOpen' {
                    $latest = Get-OSDStageUICMTraceAvailableVersion
                }
                default {
                    $remoteStatus = Get-OSDStageUIRemoteMetadataStatus -Entry $Entry
                    $latest = $remoteStatus.Latest
                    $status = if ($remoteStatus.Current) { 'Current' } else { 'Update available' }
                    $detail = $remoteStatus.Detail
                }
            }

            if ($status -ne 'Update available' -and $status -ne 'Current') {
                if (-not $latest) { throw "No available version could be resolved for '$($Entry.Id)'." }
                $status = if ($current -and $latest -ne $current) { 'Update available' } else { 'Current' }
            }
        }
    }
    catch {
        $status = 'Check failed'
        $detail = $_.Exception.Message
    }

    [pscustomobject]@{ Latest=$latest; Status=$status; Detail=$detail }
}

function Get-OSDStageUICacheUpdateKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)

    "$([string]$Entry.Source):$([string]$Entry.Id):$([string]$Entry.Architecture):$([string]$Entry.Channel):$([string]$Entry.RuntimeType)"
}

function New-OSDStageUICacheUpdatePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    if (-not $State.Snapshot -or -not $State.Snapshot.CachePath) {
        throw 'No OSDStage USB cache is currently connected.'
    }

    # Always refresh release metadata immediately before an update. This avoids
    # applying stale status from a previously connected USB device.
    $State.Status.Text = 'Checking available cache updates...'
    $State.Form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    [void](Update-OSDStageUICacheUpdateStatus -State $State)

    $available = @(
        foreach ($entry in @($State.Snapshot.CacheEntries)) {
            $key = Get-OSDStageUICacheUpdateKey -Entry $entry
            $status = $State.CacheUpdateStatus[$key]
            if ($status -and [string]$status.Status -eq 'Update available') {
                [pscustomobject]@{ Entry=$entry; Status=$status }
            }
        }
    )

    $plan = [System.Collections.Generic.List[object]]::new()

    $repositoryEntries = @($available | Where-Object { [string]$_.Entry.Source -eq 'Repository' })
    if ($repositoryEntries.Count -gt 0) {
        $names = @($repositoryEntries.Entry.Id | Sort-Object -Unique)
        $plan.Add([pscustomobject]@{
            Source       = 'Repository'
            Id           = 'Repository'
            DisplayName  = "Repository packages ($($names.Count))"
            Command      = 'Sync-OSDStageRepository'
            Names        = $names
            Architecture = $null
            Channel      = $null
            RuntimeType  = $null
            Current      = $null
            Latest       = $null
        })
    }

    foreach ($candidate in @($available | Where-Object { [string]$_.Entry.Source -eq 'BuiltIn' })) {
        $entry = $candidate.Entry

        # Only release resolvers that produced an explicit Update available
        # status can reach this plan. Microsoft 365 Apps and other unsupported
        # built-ins therefore cannot be downloaded accidentally.
        $commandName = "Sync-OSDStage$($entry.Id)"
        $command = Get-Command -Name $commandName -Module OSDStage -ErrorAction SilentlyContinue
        if (-not $command) { continue }

        $displayName = if ($entry.DisplayName) { [string]$entry.DisplayName } else { [string]$entry.Id }
        $plan.Add([pscustomobject]@{
            Source       = 'BuiltIn'
            Id           = [string]$entry.Id
            DisplayName  = $displayName
            Command      = $commandName
            Names        = @()
            Architecture = [string]$entry.Architecture
            Channel      = [string]$entry.Channel
            RuntimeType  = [string]$entry.RuntimeType
            Current      = [string]$entry.Version
            Latest       = [string]$candidate.Status.Latest
        })
    }

    @($plan)
}

function Invoke-OSDStageUICacheUpdate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    $plan = @(New-OSDStageUICacheUpdatePlan -State $State)
    if ($plan.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'No supported cache updates are currently available.',
            'OSDStage - Update cache',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return [pscustomobject]@{ Updated=@(); Current=@(); Skipped=@('No updates available'); Failed=@() }
    }

    $summaryLines = @(
        "Update $($plan.Count) available cache item(s)?"
        ''
        @($plan | ForEach-Object {
            if ($_.Latest) { "- $($_.DisplayName): $($_.Current) -> $($_.Latest)" }
            else { "- $($_.DisplayName)" }
        })
        ''
        'Only items marked Update available will be synchronized.'
    )
    $answer = [System.Windows.Forms.MessageBox]::Show(
        ($summaryLines -join [Environment]::NewLine),
        'OSDStage - Update available cache items',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return [pscustomobject]@{ Updated=@(); Current=@(); Skipped=@('Cancelled'); Failed=@() }
    }

    $modulePath = Join-Path $script:moduleRoot 'OSDStage.psd1'
    $catalogUri = (Get-OSDStageConfiguration).CatalogUri
    $payload = [pscustomobject]@{
        ModulePath = $modulePath
        CatalogUri = if ($catalogUri) { $catalogUri.AbsoluteUri } else { $null }
        Tasks      = @($plan)
    }

    $worker = {
        param($Payload)

        $ErrorActionPreference = 'Stop'
        Import-Module -Name ([string]$Payload.ModulePath) -Force -ErrorAction Stop
        if ($Payload.CatalogUri) {
            Set-OSDStageConfiguration -CatalogUri ([uri]$Payload.CatalogUri) | Out-Null
        }

        $tasks = @($Payload.Tasks)
        $total = $tasks.Count
        $position = 0

        foreach ($task in $tasks) {
            $position++
            Write-Output ([pscustomobject]@{
                RecordType = 'Start'
                Position   = $position
                Total      = $total
                Label      = [string]$task.DisplayName
                Message    = "Checking and updating $($task.DisplayName)"
            })

            try {
                if ([string]$task.Source -eq 'Repository') {
                    $names = @($task.Names)
                    Sync-OSDStageRepository -Name $names -Confirm:$false -ErrorAction Stop | Out-Null
                    Write-Output ([pscustomobject]@{
                        RecordType='Complete'; Position=$position; Total=$total
                        Label=[string]$task.DisplayName; Status='Updated'
                        Message="Repository cache synchronized: $($names -join ', ')"
                    })
                    continue
                }

                $parameters = @{}
                if ($task.Architecture) { $parameters.Architecture = [string]$task.Architecture }
                if ($task.Channel) { $parameters.Channel = [string]$task.Channel }
                if ($task.RuntimeType) { $parameters.RuntimeType = [string]$task.RuntimeType }
                $parameters.Confirm = $false

                $result = @(& ([string]$task.Command) @parameters -ErrorAction Stop)
                $updatedFlag = @(
                    $result |
                        Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'Updated' } |
                        Select-Object -Last 1
                )
                $wasUpdated = if ($updatedFlag.Count -gt 0) { [bool]$updatedFlag[0].Updated } else { $true }
                $status = if ($wasUpdated) { 'Updated' } else { 'Already current' }

                Write-Output ([pscustomobject]@{
                    RecordType='Complete'; Position=$position; Total=$total
                    Label=[string]$task.DisplayName; Status=$status
                    Message="$($task.DisplayName): $status"
                })
            }
            catch {
                Write-Output ([pscustomobject]@{
                    RecordType='Failed'; Position=$position; Total=$total
                    Label=[string]$task.DisplayName; Status='Failed'
                    Message="$($task.DisplayName): $($_.Exception.Message)"
                })
            }
        }
    }

    $job = Start-Job -ScriptBlock $worker -ArgumentList $payload
    $progressForm = [System.Windows.Forms.Form]::new()
    $progressForm.Text = 'OSDStage - Updating cache'
    $progressForm.Size = [System.Drawing.Size]::new(660,410)
    $progressForm.MinimumSize = [System.Drawing.Size]::new(560,340)
    $progressForm.StartPosition = 'CenterParent'
    $progressForm.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $progressForm.Font = [System.Drawing.Font]::new('Segoe UI',9)
    $progressForm.ControlBox = $false
    $progressForm.ShowInTaskbar = $false

    $layout = [System.Windows.Forms.TableLayoutPanel]::new()
    $layout.Dock = 'Fill'
    $layout.Padding = [System.Windows.Forms.Padding]::new(12)
    $layout.RowCount = 5
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',32))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',28))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',26))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',42))
    $progressForm.Controls.Add($layout)

    $activity = [System.Windows.Forms.Label]::new()
    $activity.Dock = 'Fill'
    $activity.Font = [System.Drawing.Font]::new('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
    $activity.Text = 'Preparing cache update...'
    [void]$layout.Controls.Add($activity,0,0)

    $progress = [System.Windows.Forms.ProgressBar]::new()
    $progress.Dock = 'Fill'
    $progress.Minimum = 0
    $progress.Maximum = [math]::Max(1,$plan.Count)
    $progress.Value = 0
    $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    [void]$layout.Controls.Add($progress,0,1)

    $elapsed = [System.Windows.Forms.Label]::new()
    $elapsed.Dock = 'Fill'
    $elapsed.Text = 'Elapsed: 00:00'
    [void]$layout.Controls.Add($elapsed,0,2)

    $details = [System.Windows.Forms.TextBox]::new()
    $details.Dock = 'Fill'
    $details.Multiline = $true
    $details.ReadOnly = $true
    $details.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $details.BackColor = [System.Drawing.Color]::White
    $details.Font = [System.Drawing.Font]::new('Consolas',9)
    [void]$layout.Controls.Add($details,0,3)

    $closeProgress = [System.Windows.Forms.Button]::new()
    $closeProgress.Text = 'Close'
    $closeProgress.Enabled = $false
    $closeProgress.Width = 100
    $closeProgress.Anchor = 'Right'
    [void]$layout.Controls.Add($closeProgress,0,4)

    $updated = [System.Collections.Generic.List[string]]::new()
    $current = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()
    $processed = 0
    $completed = $false
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $appendLine = {
        param([string]$Text)
        $stamp = (Get-Date).ToString('HH:mm:ss')
        $details.AppendText("[$stamp] $Text$([Environment]::NewLine)")
        $details.SelectionStart = $details.TextLength
        $details.ScrollToCaret()
    }

    $processRecords = {
        param([object[]]$Records)
        foreach ($record in @($Records)) {
            if (-not $record -or -not $record.RecordType) { continue }
            switch ([string]$record.RecordType) {
                'Start' {
                    $activity.Text = "$($record.Message) ($($record.Position) of $($record.Total))"
                    & $appendLine $record.Message
                }
                'Complete' {
                    $processed = [math]::Max($processed,[int]$record.Position)
                    $progress.Value = [math]::Min($progress.Maximum,$processed)
                    if ([string]$record.Status -eq 'Updated') { $updated.Add([string]$record.Label) }
                    else { $current.Add([string]$record.Label) }
                    & $appendLine $record.Message
                }
                'Failed' {
                    $processed = [math]::Max($processed,[int]$record.Position)
                    $progress.Value = [math]::Min($progress.Maximum,$processed)
                    $failed.Add([string]$record.Message)
                    & $appendLine $record.Message
                }
            }
        }
    }

    $timer = [System.Windows.Forms.Timer]::new()
    $timer.Interval = 250
    $timer.Add_Tick({
        $elapsed.Text = 'Elapsed: ' + $stopwatch.Elapsed.ToString('mm\:ss')
        $records = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
        if ($records.Count -gt 0) { & $processRecords $records }

        if (-not $completed -and $job.State -in @('Completed','Failed','Stopped')) {
            $completed = $true
            $remaining = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
            if ($remaining.Count -gt 0) { & $processRecords $remaining }
            $stopwatch.Stop()
            $timer.Stop()

            if ($job.State -eq 'Failed' -and $job.ChildJobs.Count -gt 0 -and $job.ChildJobs[0].JobStateInfo.Reason) {
                $reason = [string]$job.ChildJobs[0].JobStateInfo.Reason.Message
                if ($reason) {
                    $failed.Add($reason)
                    & $appendLine "Worker failed: $reason"
                }
            }

            $progress.Value = $progress.Maximum
            $activity.Text = "Cache update complete: $($updated.Count) updated, $($current.Count) current, $($failed.Count) failed"
            $elapsed.Text = 'Elapsed: ' + $stopwatch.Elapsed.ToString('mm\:ss')
            $closeProgress.Enabled = $true
            $progressForm.ControlBox = $true
        }
    })
    $closeProgress.Add_Click({ if ($completed) { $progressForm.Close() } })
    $progressForm.Add_FormClosing({ if (-not $completed) { $_.Cancel = $true } })

    try {
        $State.Form.UseWaitCursor = $false
        & $appendLine "Starting $($plan.Count) available update(s)."
        $timer.Start()
        [void]$progressForm.ShowDialog($State.Form)
    }
    finally {
        $timer.Stop()
        $timer.Dispose()
        if ($job.State -notin @('Completed','Failed','Stopped')) { Stop-Job -Job $job -ErrorAction SilentlyContinue }
        Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $progressForm.Dispose()
    }

    [pscustomobject]@{
        Updated = @($updated)
        Current = @($current)
        Skipped = @($current | ForEach-Object { "Already current: $_" })
        Failed  = @($failed)
    }
}
