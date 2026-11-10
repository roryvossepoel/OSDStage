function Get-OSDStageUICacheUpdateKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)

    "$([string]$Entry.Source):$([string]$Entry.Id):$([string]$Entry.Architecture):$([string]$Entry.Channel):$([string]$Entry.RuntimeType)"
}

function New-OSDStageUICacheUpdatePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [string[]]$SelectedAppKey,
        [switch]$SkipRecheck
    )

    if (-not $State.Snapshot -or -not $State.Snapshot.CachePath) {
        throw 'No OSDStage USB cache is currently connected.'
    }

    if (-not $SkipRecheck) {
        # Recheck immediately before mutation unless the Cache Manager already
        # completed a responsive background check for the same action.
        $State.Status.Text = 'Checking available cache updates...'
        $State.Form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
        [void](Update-OSDStageUICacheUpdateStatus -State $State)
    }

    $selected = @($SelectedAppKey | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $available = @(
        foreach ($entry in @($State.Snapshot.CacheEntries)) {
            $appKey = "$([string]$entry.Source):$([string]$entry.Id)"
            if ($selected.Count -gt 0 -and $appKey -notin $selected) { continue }
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
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [string[]]$SelectedAppKey,
        [switch]$SkipRecheck
    )

    $plan = @(New-OSDStageUICacheUpdatePlan -State $State -SelectedAppKey $SelectedAppKey -SkipRecheck:$SkipRecheck)
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
