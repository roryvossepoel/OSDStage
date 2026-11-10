
function Get-OSDStageUIManagerAppKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Item)
    "$([string]$Item.Source):$([string]$Item.Id)"
}

function Get-OSDStageUIManagerGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][object[]]$BuiltInMetadata
    )
    $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($Snapshot.CatalogApps) + @($Snapshot.CacheEntries)) {
        if (-not $item -or -not $item.Id -or -not $item.Source) { continue }
        [void]$keys.Add((Get-OSDStageUIManagerAppKey -Item $item))
    }
    foreach ($key in @($keys | Sort-Object)) {
        $parts = $key -split ':',2
        $source = $parts[0]; $id = $parts[1]
        $catalog = @($Snapshot.CatalogApps | Where-Object { [string]$_.Source -eq $source -and [string]$_.Id -eq $id })
        $cache = @($Snapshot.CacheEntries | Where-Object { [string]$_.Source -eq $source -and [string]$_.Id -eq $id })
        $sample = if ($cache.Count -gt 0) { $cache[0] } else { $catalog[0] }
        if (-not $sample) { continue }
        $display = Get-OSDStageUIDisplayInfo -App $sample -CatalogApps $Snapshot.CatalogApps -BuiltInMetadata $BuiltInMetadata
        [pscustomobject]@{
            Key=$key; Id=$id; Source=$source; DisplayName=[string]$display.DisplayName; Vendor=[string]$display.Vendor
            PackageType=(Get-OSDStageUIPackageType -App $sample); CacheEntries=@($cache); CatalogEntries=@($catalog)
        }
    }
}

function Get-OSDStageUIManagerGroupSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Group,[Parameter(Mandatory)][hashtable]$State)

    $cache=@($Group.CacheEntries)
    $cachedLabel = if($cache.Count -eq 0){'Not cached'}elseif($cache.Count -eq 1){
        $v=[string]$cache[0].Version; if([string]::IsNullOrWhiteSpace($v)-or $v -eq 'Current'){'Cached'}else{$v}
    }else{"$($cache.Count) cached configurations"}

    if($cache.Count -eq 0){
        $status=if([string]$Group.Source -eq 'Repository'){if($State.CatalogMode -eq 'Online'){'Not cached'}else{'Catalog not configured'}}else{'Not cached - use CLI'}
        return [pscustomobject]@{Cached=$cachedLabel;Available='-';Status=$status;UpdateCount=0;FailedCount=0}
    }

    $results=@(foreach($entry in $cache){$k=Get-OSDStageUICacheUpdateKey -Entry $entry;if($State.CacheUpdateStatus.ContainsKey($k)){$State.CacheUpdateStatus[$k]}})
    if($results.Count -eq 0){return [pscustomobject]@{Cached=$cachedLabel;Available='-';Status='Not checked yet';UpdateCount=0;FailedCount=0}}

    $updateCount=@($results|Where-Object Status -eq 'Update available').Count
    $failedCount=@($results|Where-Object Status -eq 'Check failed').Count
    $catalogMissing=@($results|Where-Object Status -eq 'Catalog not configured').Count
    $allCurrent=($results.Count -eq $cache.Count -and @($results|Where-Object Status -eq 'Current').Count -eq $cache.Count)
    $available=if($cache.Count -eq 1){
        $single=$results|Select-Object -First 1
        if($single.Latest){[string]$single.Latest}elseif($single.Status -eq 'Current'){[string]$cache[0].Version}elseif($single.Status -eq 'Update available'){'New release'}else{'-'}
    }else{"$($cache.Count) configurations"}
    $status=if($failedCount -gt 0){"Check failed ($failedCount)"}elseif($updateCount -gt 0){if($updateCount -eq 1){'Update available'}else{"Updates available ($updateCount)"}}elseif($catalogMissing -gt 0){'Catalog not configured'}elseif($allCurrent){'Current'}else{'Review details'}
    [pscustomobject]@{Cached=$cachedLabel;Available=$available;Status=$status;UpdateCount=$updateCount;FailedCount=$failedCount}
}

function Update-OSDStageUIManagerRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State,[switch]$PreserveChecks)
    if(-not $State.ManagerList -or -not $State.Snapshot){return}

    $checked=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if($PreserveChecks){foreach($item in @($State.ManagerList.Items)){if($item.Checked -and $item.Tag -and $item.Tag.Key){[void]$checked.Add([string]$item.Tag.Key)}}}

    $groups=@(Get-OSDStageUIManagerGroups -Snapshot $State.Snapshot -BuiltInMetadata @(Get-OSDStageUIBuiltInMetadata))
    $items=@(foreach($group in $groups){
        $summary=Get-OSDStageUIManagerGroupSummary -Group $group -State $State
        $item=[System.Windows.Forms.ListViewItem]::new([string]$group.DisplayName)
        [void]$item.SubItems.Add($(if($group.Source -eq 'BuiltIn'){'Built-in'}else{'Repository'}))
        [void]$item.SubItems.Add([string]$group.PackageType);[void]$item.SubItems.Add([string]$group.Vendor)
        [void]$item.SubItems.Add([string]$summary.Cached);[void]$item.SubItems.Add([string]$summary.Available);[void]$item.SubItems.Add([string]$summary.Status)
        $item.Tag=$group;$item.Checked=$checked.Contains([string]$group.Key)
        if($summary.UpdateCount -gt 0){$item.ForeColor=[System.Drawing.Color]::DarkOrange}elseif($summary.FailedCount -gt 0){$item.ForeColor=[System.Drawing.Color]::Firebrick}elseif(@($group.CacheEntries).Count -eq 0){$item.ForeColor=[System.Drawing.Color]::DimGray}
        $item
    })
    $State.Rows['Packages']=$items
    Show-OSDStageUIRows -State $State -Key Packages
    Set-OSDStageUIColumnWidths -State $State -Key Packages
    $cachedApps=@($groups|Where-Object{@($_.CacheEntries).Count -gt 0}).Count
    $updates=0;foreach($group in $groups){$updates+=(Get-OSDStageUIManagerGroupSummary -Group $group -State $State).UpdateCount}
    $State.ManagerInfo.Text="$($groups.Count) apps | $cachedApps cached | $updates update(s) available | New built-in cache configurations are created with the CLI"
}

function Format-OSDStageUIManagerDetails {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Group,[Parameter(Mandatory)][hashtable]$State)
    $lines=[System.Collections.Generic.List[string]]::new()
    $lines.Add("$($Group.DisplayName) | $(if($Group.Source -eq 'BuiltIn'){'Built-in'}else{'Repository'}) | $($Group.PackageType)")
    if($Group.Vendor){$lines.Add("Vendor: $($Group.Vendor)")};$lines.Add('')
    $cache=@($Group.CacheEntries)
    if($cache.Count -eq 0){
        if($Group.Source -eq 'BuiltIn'){$lines.Add('Not cached. Define a new built-in cache configuration with the PowerShell CLI.')}else{$lines.Add('Not cached. Repository packages can be cached here when an online catalog is configured.')}
        return ($lines -join [Environment]::NewLine)
    }
    $lines.Add("Cached configurations: $($cache.Count)")
    foreach($entry in $cache){
        $parts=[System.Collections.Generic.List[string]]::new()
        if($entry.Architecture){$parts.Add([string]$entry.Architecture)};if($entry.Channel){$parts.Add([string]$entry.Channel)};if($entry.RuntimeType){$parts.Add([string]$entry.RuntimeType)};if($entry.Language){$parts.Add((@($entry.Language)-join ','))}
        $variant=if($parts.Count -gt 0){$parts -join ' | '}else{'default configuration'}
        $k=Get-OSDStageUICacheUpdateKey -Entry $entry;$result=if($State.CacheUpdateStatus.ContainsKey($k)){$State.CacheUpdateStatus[$k]}else{$null}
        $lines.Add('');$lines.Add("- $variant");$lines.Add("  Cached version: $([string]$entry.Version)")
        if($result){$lines.Add("  Available version: $(if($result.Latest){[string]$result.Latest}else{'-'})");$lines.Add("  Update status: $([string]$result.Status)");if($result.Detail){$lines.Add("  Detail: $([string]$result.Detail)")}}else{$lines.Add('  Update status: Not checked yet')}
        if($entry.CachePath){$lines.Add("  Path: $([string]$entry.CachePath)")}
    }
    $lines -join [Environment]::NewLine
}

function Update-OSDStageUIManagerDetails {
    [CmdletBinding()]param([Parameter(Mandatory)][hashtable]$State)
    if(-not $State.ManagerDetails){return}
    if($State.ManagerList.SelectedItems.Count -eq 0){$State.ManagerDetails.Text='Select an app to view its cached configurations.';return}
    $State.ManagerDetails.Text=Format-OSDStageUIManagerDetails -Group $State.ManagerList.SelectedItems[0].Tag -State $State
}

function Get-OSDStageUIManagerCheckedKeys {
    [CmdletBinding()]param([Parameter(Mandatory)][hashtable]$State)
    @(foreach($item in @($State.ManagerList.Items)){if($item.Checked -and $item.Tag -and $item.Tag.Key){[string]$item.Tag.Key}})
}

function Invoke-OSDStageUIManagerJob {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State,[Parameter(Mandatory)][string]$Title,[Parameter(Mandatory)][string]$InitialActivity,[Parameter(Mandatory)][scriptblock]$Worker,[Parameter()]$Payload)
    $job=Start-Job -ScriptBlock $Worker -ArgumentList $Payload
    $form=[System.Windows.Forms.Form]::new();$form.Text=$Title;$form.Size=[System.Drawing.Size]::new(660,390);$form.MinimumSize=[System.Drawing.Size]::new(560,320);$form.StartPosition='CenterParent';$form.Font=[System.Drawing.Font]::new('Segoe UI',9);$form.ControlBox=$false;$form.ShowInTaskbar=$false
    $layout=[System.Windows.Forms.TableLayoutPanel]::new();$layout.Dock='Fill';$layout.Padding=[System.Windows.Forms.Padding]::new(12);$layout.RowCount=5
    [void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',34));[void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',28));[void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',26));[void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100));[void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',42));$form.Controls.Add($layout)
    $activity=[System.Windows.Forms.Label]::new();$activity.Dock='Fill';$activity.Font=[System.Drawing.Font]::new('Segoe UI',10,[System.Drawing.FontStyle]::Bold);$activity.Text=$InitialActivity;[void]$layout.Controls.Add($activity,0,0)
    $progress=[System.Windows.Forms.ProgressBar]::new();$progress.Dock='Fill';$progress.Style=[System.Windows.Forms.ProgressBarStyle]::Marquee;[void]$layout.Controls.Add($progress,0,1)
    $elapsed=[System.Windows.Forms.Label]::new();$elapsed.Dock='Fill';$elapsed.Text='Elapsed: 00:00';[void]$layout.Controls.Add($elapsed,0,2)
    $details=[System.Windows.Forms.TextBox]::new();$details.Dock='Fill';$details.Multiline=$true;$details.ReadOnly=$true;$details.ScrollBars=[System.Windows.Forms.ScrollBars]::Vertical;$details.BackColor=[System.Drawing.Color]::White;$details.Font=[System.Drawing.Font]::new('Consolas',9);[void]$layout.Controls.Add($details,0,3)
    $close=[System.Windows.Forms.Button]::new();$close.Text='Close';$close.Enabled=$false;$close.Width=100;$close.Anchor='Right';[void]$layout.Controls.Add($close,0,4)
    $records=[System.Collections.Generic.List[object]]::new();$operation=[pscustomobject]@{Completed=$false};$watch=[System.Diagnostics.Stopwatch]::StartNew()
    $timer=[System.Windows.Forms.Timer]::new();$timer.Interval=250
    $timer.Add_Tick({
        $elapsed.Text='Elapsed: '+$watch.Elapsed.ToString('mm\:ss')
        foreach($record in @(Receive-Job -Job $job -ErrorAction SilentlyContinue)){
            if(-not $record){continue};$records.Add($record)
            if($record.RecordType -eq 'Progress'){
                $activity.Text=[string]$record.Message
                if($record.Total -and [int]$record.Total -gt 0){$progress.Style=[System.Windows.Forms.ProgressBarStyle]::Continuous;$progress.Maximum=[math]::Max(1,[int]$record.Total);$progress.Value=[math]::Min($progress.Maximum,[math]::Max(0,[int]$record.Position))}
                $details.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $($record.Message)$([Environment]::NewLine)");$details.SelectionStart=$details.TextLength;$details.ScrollToCaret()
            }
        }
        if(-not $operation.Completed -and $job.State -in @('Completed','Failed','Stopped')){
            $operation.Completed=$true;foreach($record in @(Receive-Job -Job $job -ErrorAction SilentlyContinue)){if($record){$records.Add($record)}};$watch.Stop();$timer.Stop()
            $progress.Style=[System.Windows.Forms.ProgressBarStyle]::Continuous;$progress.Maximum=1;$progress.Value=1;$activity.Text=if($job.State -eq 'Completed'){'Completed'}else{"Finished: $($job.State)"};$elapsed.Text='Elapsed: '+$watch.Elapsed.ToString('mm\:ss');$close.Enabled=$true;$form.ControlBox=$true
        }
    })
    $close.Add_Click({ $form.Close() });$form.Add_FormClosing({ param($sender,$eventArgs) if(-not $operation.Completed){$eventArgs.Cancel=$true} })
    try{$timer.Start();[void]$form.ShowDialog($State.Form)}finally{$timer.Stop();$timer.Dispose();if($job.State -notin @('Completed','Failed','Stopped')){Stop-Job -Job $job -ErrorAction SilentlyContinue};foreach($record in @(Receive-Job -Job $job -ErrorAction SilentlyContinue)){if($record){$records.Add($record)}};Remove-Job -Job $job -Force -ErrorAction SilentlyContinue;$form.Dispose()}
    @($records)
}

function Invoke-OSDStageUIManagerCheckUpdates {
    [CmdletBinding()]param([Parameter(Mandatory)][hashtable]$State,[string[]]$AppKey)
    $keys=@($AppKey|Where-Object{$_});$entries=@(foreach($entry in @($State.Snapshot.CacheEntries)){$k="$([string]$entry.Source):$([string]$entry.Id)";if($keys.Count -eq 0 -or $k -in $keys){$entry}})
    if($entries.Count -eq 0){[void][System.Windows.Forms.MessageBox]::Show('No cached configurations are in scope.','OSDStage - Check updates','OK','Information');return}
    $configured=(Get-OSDStageConfiguration).CatalogUri
    $payload=[pscustomobject]@{ModulePath=Join-Path $script:moduleRoot 'OSDStage.psd1';CatalogUri=$(if($configured){$configured.AbsoluteUri}else{$null});Entries=$entries}
    $worker={
        param($Payload);$ErrorActionPreference='Stop';Import-Module -Name ([string]$Payload.ModulePath) -Force -ErrorAction Stop;$module=Get-Module OSDStage;$catalog=$null
        if($Payload.CatalogUri){$catalog=& $module {param($uri)Get-OSDStageCatalogPackages -CatalogUri ([uri]$uri)} ([string]$Payload.CatalogUri)}
        $position=0;$total=@($Payload.Entries).Count
        foreach($entry in @($Payload.Entries)){$position++;Write-Output([pscustomobject]@{RecordType='Progress';Position=$position-1;Total=$total;Message="Checking $($entry.DisplayName) ($position of $total)"})
            $result=& $module {param($e,$c)Get-OSDStageUICacheUpdateStatus -Entry $e -RepositoryCatalog $c} $entry $catalog
            $variantKey=& $module {param($e)Get-OSDStageUICacheUpdateKey -Entry $e} $entry
            Write-Output([pscustomobject]@{RecordType='UpdateResult';Position=$position;Total=$total;Key=$variantKey;Latest=$result.Latest;Status=$result.Status;Detail=$result.Detail})
            Write-Output([pscustomobject]@{RecordType='Progress';Position=$position;Total=$total;Message="$($entry.DisplayName): $($result.Status)"})
        }
    }
    $records=@(Invoke-OSDStageUIManagerJob -State $State -Title 'OSDStage - Checking updates' -InitialActivity 'Checking cached app versions...' -Worker $worker -Payload $payload)
    foreach($record in @($records|Where-Object RecordType -eq 'UpdateResult')){$State.CacheUpdateStatus[[string]$record.Key]=[pscustomobject]@{Latest=$record.Latest;Status=[string]$record.Status;Detail=[string]$record.Detail}}
    Update-OSDStageUIManagerRows -State $State -PreserveChecks;Update-OSDStageUIManagerDetails -State $State
    $scoped=@($records|Where-Object RecordType -eq 'UpdateResult');$updates=@($scoped|Where-Object Status -eq 'Update available').Count;$failed=@($scoped|Where-Object Status -eq 'Check failed').Count;$current=@($scoped|Where-Object Status -eq 'Current').Count
    $State.Status.Text="Update check complete | $current current | $updates update(s) available | $failed failed"
}

function Show-OSDStageUIManagerHealth {
    [CmdletBinding()]param([Parameter(Mandatory)][hashtable]$State,[Parameter(Mandatory)]$Health)
    $form=[System.Windows.Forms.Form]::new();$form.Text='OSDStage - Cache health';$form.Size=[System.Drawing.Size]::new(860,520);$form.MinimumSize=[System.Drawing.Size]::new(720,420);$form.StartPosition='CenterParent';$form.Font=[System.Drawing.Font]::new('Segoe UI',9)
    $layout=[System.Windows.Forms.TableLayoutPanel]::new();$layout.Dock='Fill';$layout.Padding=[System.Windows.Forms.Padding]::new(12);$layout.RowCount=4;[void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',44));[void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',54));[void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100));[void]$layout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',42));$form.Controls.Add($layout)
    $headline=[System.Windows.Forms.Label]::new();$issueCount=@($Health.Entries|Where-Object State -notin @('Active','Pinned')).Count;$headline.Text=if($Health.Healthy){'Cache is healthy'}else{"$issueCount item(s) need attention"};$headline.Font=[System.Drawing.Font]::new('Segoe UI',14,[System.Drawing.FontStyle]::Bold);$headline.Dock='Fill';[void]$layout.Controls.Add($headline,0,0)
    $summary=[System.Windows.Forms.Label]::new();$summary.Dock='Fill';$summary.Text="Active: $($Health.ActiveCount)   Orphaned: $($Health.OrphanedCount)   Obsolete: $($Health.ObsoleteCount)   Incomplete: $($Health.IncompleteCount)   Corrupt: $($Health.CorruptCount)   Cleanup candidate: $($Health.RemovableSizeMB) MB"+[Environment]::NewLine+$(if($Health.DesiredStateAvailable){'Repository desired-state comparison available.'}else{'Repository comparison unavailable - no catalog configured or offline mode is active.'});[void]$layout.Controls.Add($summary,0,1)
    $list=[System.Windows.Forms.ListView]::new();$list.Dock='Fill';$list.View='Details';$list.FullRowSelect=$true;$list.GridLines=$true;[void]$list.Columns.Add('Item',180);[void]$list.Columns.Add('Source',85);[void]$list.Columns.Add('State',90);[void]$list.Columns.Add('Integrity',90);[void]$list.Columns.Add('Recommended action',125);[void]$list.Columns.Add('Size',80);[void]$list.Columns.Add('Reason',260)
    foreach($entry in @($Health.Entries|Where-Object State -notin @('Active','Pinned'))){$item=[System.Windows.Forms.ListViewItem]::new([string]$entry.DisplayName);[void]$item.SubItems.Add([string]$entry.Source);[void]$item.SubItems.Add([string]$entry.State);[void]$item.SubItems.Add([string]$entry.Integrity);[void]$item.SubItems.Add([string]$entry.Action);[void]$item.SubItems.Add("$($entry.SizeMB) MB");[void]$item.SubItems.Add([string]$entry.Reason);$item.ToolTipText="Path: $($entry.CachePath)";[void]$list.Items.Add($item)}
    if($list.Items.Count -eq 0){[void]$list.Items.Add([System.Windows.Forms.ListViewItem]::new('No cache health issues found.'))};[void]$layout.Controls.Add($list,0,2)
    $close=[System.Windows.Forms.Button]::new();$close.Text='Close';$close.Width=100;$close.Anchor='Right';$close.Add_Click({$form.Close()});[void]$layout.Controls.Add($close,0,3);[void]$form.ShowDialog($State.Form);$form.Dispose()
}

function Invoke-OSDStageUIManagerHealthCheck {
    [CmdletBinding()]param([Parameter(Mandatory)][hashtable]$State)
    $payload=[pscustomobject]@{ModulePath=Join-Path $script:moduleRoot 'OSDStage.psd1';CachePath=[string]$State.Snapshot.CachePath;Offline=[bool]$State.Offline}
    $worker={param($Payload);Import-Module -Name ([string]$Payload.ModulePath) -Force -ErrorAction Stop;Write-Output([pscustomobject]@{RecordType='Progress';Position=0;Total=1;Message='Scanning cache integrity and desired state...'});$health=Get-OSDStageCacheHealth -CachePath ([string]$Payload.CachePath) -Offline:([bool]$Payload.Offline);Write-Output([pscustomobject]@{RecordType='HealthResult';Data=$health});Write-Output([pscustomobject]@{RecordType='Progress';Position=1;Total=1;Message='Cache health check complete'})}
    $records=@(Invoke-OSDStageUIManagerJob -State $State -Title 'OSDStage - Cache health' -InitialActivity 'Checking cache health...' -Worker $worker -Payload $payload);$record=@($records|Where-Object RecordType -eq 'HealthResult'|Select-Object -Last 1)
    if($record.Count -eq 1){Show-OSDStageUIManagerHealth -State $State -Health $record[0].Data;$State.Status.Text="Cache health: $(if($record[0].Data.Healthy){'Healthy'}else{'Needs attention'})"}
}

function Invoke-OSDStageUIManagerRemoveSelected {
    [CmdletBinding()]param([Parameter(Mandatory)][hashtable]$State)
    $groups=@($State.ManagerList.Items|Where-Object Checked|ForEach-Object{$_.Tag}|Where-Object{@($_.CacheEntries).Count -gt 0})
    if($groups.Count -eq 0){[void][System.Windows.Forms.MessageBox]::Show('Select one or more cached apps first.','OSDStage - Remove selected','OK','Information');return}
    $duplicateIds=@($State.ManagerList.Items|ForEach-Object{$_.Tag}|Group-Object Id|Where-Object Count -gt 1|ForEach-Object Name);if(@($groups|Where-Object{$_.Id -in $duplicateIds}).Count -gt 0){[void][System.Windows.Forms.MessageBox]::Show('One or more selected Ids exist in both cache namespaces. Remove those with the CLI so the source can be specified safely.','OSDStage - Remove selected','OK','Warning');return}
    $lines=[System.Collections.Generic.List[string]]::new();$lines.Add("Remove $($groups.Count) selected app(s) from the cache?");$lines.Add('')
    foreach($group in $groups){$versions=@($group.CacheEntries|ForEach-Object{[string]$_.Version}|Select-Object -Unique);$size=[math]::Round([double](($group.CacheEntries|Measure-Object SizeMB -Sum).Sum),1);$lines.Add("- $($group.DisplayName) | $(@($group.CacheEntries).Count) configuration(s) | $($versions -join ', ') | $size MB")}
    $answer=[System.Windows.Forms.MessageBox]::Show(($lines -join [Environment]::NewLine),'OSDStage - Remove selected','YesNo','Warning');if($answer -ne [System.Windows.Forms.DialogResult]::Yes){return}
    $payload=[pscustomobject]@{ModulePath=Join-Path $script:moduleRoot 'OSDStage.psd1';Names=@($groups.Id)}
    $worker={param($Payload);Import-Module -Name ([string]$Payload.ModulePath) -Force -ErrorAction Stop;$position=0;$total=@($Payload.Names).Count;foreach($name in @($Payload.Names)){$position++;Write-Output([pscustomobject]@{RecordType='Progress';Position=$position-1;Total=$total;Message="Removing $name ($position of $total)"});Clear-OSDStageCache -Name ([string]$name) -Confirm:$false -ErrorAction Stop|Out-Null;Write-Output([pscustomobject]@{RecordType='Progress';Position=$position;Total=$total;Message="Removed $name"})}}
    [void](Invoke-OSDStageUIManagerJob -State $State -Title 'OSDStage - Removing cache items' -InitialActivity 'Removing selected cache items...' -Worker $worker -Payload $payload)
}

function Invoke-OSDStageUIManagerClearEntireCache {
    [CmdletBinding()]param([Parameter(Mandatory)][hashtable]$State)
    $count=@($State.Snapshot.CacheEntries).Count;$size=[math]::Round([double](($State.Snapshot.CacheEntries|Measure-Object SizeMB -Sum).Sum),1);$nl=[Environment]::NewLine
    $message="Clear the entire connected OSDStage cache?"+$nl+$nl+"$count cached configuration(s), approximately $size MB."+$nl+"Logs are preserved."+$nl+$nl+"This cannot be undone."
    $answer=[System.Windows.Forms.MessageBox]::Show($message,'OSDStage - Clear entire cache','YesNo','Warning');if($answer -ne [System.Windows.Forms.DialogResult]::Yes){return}
    $payload=[pscustomobject]@{ModulePath=Join-Path $script:moduleRoot 'OSDStage.psd1'}
    $worker={param($Payload);Import-Module -Name ([string]$Payload.ModulePath) -Force -ErrorAction Stop;Write-Output([pscustomobject]@{RecordType='Progress';Position=0;Total=1;Message='Clearing connected cache...'});Clear-OSDStageCache -All -Confirm:$false -ErrorAction Stop|Out-Null;Write-Output([pscustomobject]@{RecordType='Progress';Position=1;Total=1;Message='Cache cleared'})}
    [void](Invoke-OSDStageUIManagerJob -State $State -Title 'OSDStage - Clear entire cache' -InitialActivity 'Clearing cache...' -Worker $worker -Payload $payload)
}


function Invoke-OSDStageUIManagerRefresh {
    [CmdletBinding()]param([Parameter(Mandatory)][hashtable]$State)
    $configured=(Get-OSDStageConfiguration).CatalogUri
    $payload=[pscustomobject]@{
        ModulePath=Join-Path $script:moduleRoot 'OSDStage.psd1'
        WindowsPath=$State.Target
        Offline=[bool]$State.Offline
        SkipSignatureVerification=[bool]$State.SkipSignatureVerification
        CatalogUri=$(if($configured){$configured.AbsoluteUri}else{$null})
    }
    $worker={
        param($Payload)
        Import-Module -Name ([string]$Payload.ModulePath) -Force -ErrorAction Stop
        if($Payload.CatalogUri){Set-OSDStageConfiguration -CatalogUri ([uri]$Payload.CatalogUri)|Out-Null}
        $module=Get-Module OSDStage
        Write-Output([pscustomobject]@{RecordType='Progress';Position=0;Total=1;Message='Reading device, cache and signatures...'})
        $snapshot=& $module {
            param($WindowsPath,$Offline,$Skip)
            Get-OSDStageUIReadOnlySnapshot -WindowsPath $WindowsPath -Offline:$Offline -SkipSignatureVerification:$Skip
        } $Payload.WindowsPath ([bool]$Payload.Offline) ([bool]$Payload.SkipSignatureVerification)
        Write-Output([pscustomobject]@{RecordType='SnapshotResult';Data=$snapshot})
        Write-Output([pscustomobject]@{RecordType='Progress';Position=1;Total=1;Message='Inventory refreshed'})
    }
    $records=@(Invoke-OSDStageUIManagerJob -State $State -Title 'OSDStage - Refreshing' -InitialActivity 'Refreshing inventory...' -Worker $worker -Payload $payload)
    $record=@($records|Where-Object RecordType -eq 'SnapshotResult'|Select-Object -Last 1)
    if($record.Count -eq 1){
        Update-OSDStageUIReadOnlyView -State $State -Snapshot $record[0].Data
        $State.Status.Text='Inventory refreshed.'
    }
}

function Invoke-OSDStageUIManagerCacheSelected {
    [CmdletBinding()]param([Parameter(Mandatory)][hashtable]$State)
    $groups=@($State.ManagerList.Items|Where-Object Checked|ForEach-Object{$_.Tag})
    if($groups.Count -eq 0){
        [void][System.Windows.Forms.MessageBox]::Show('Select one or more uncached repository apps first.','OSDStage - Cache selected','OK','Information')
        return
    }

    $eligible=@($groups|Where-Object{$_.Source -eq 'Repository' -and @($_.CacheEntries).Count -eq 0})
    $builtIn=@($groups|Where-Object{$_.Source -eq 'BuiltIn' -and @($_.CacheEntries).Count -eq 0})
    $alreadyCached=@($groups|Where-Object{@($_.CacheEntries).Count -gt 0})

    if($builtIn.Count -gt 0){
        [void][System.Windows.Forms.MessageBox]::Show(
            'New built-in cache configurations are created with the PowerShell CLI. They are not created by the Cache Manager.',
            'OSDStage - Cache selected','OK','Information'
        )
    }
    if($alreadyCached.Count -gt 0){
        [void][System.Windows.Forms.MessageBox]::Show(
            'One or more selected apps are already cached. Use Check updates or Update selected for those apps.',
            'OSDStage - Cache selected','OK','Information'
        )
    }
    if($eligible.Count -eq 0){return}

    $catalogUri=(Get-OSDStageConfiguration).CatalogUri
    if(-not $catalogUri){
        [void][System.Windows.Forms.MessageBox]::Show('No repository catalog is configured in this PowerShell session.','OSDStage - Cache selected','OK','Warning')
        return
    }

    $names=@($eligible.Id|Sort-Object -Unique)
    $nl=[Environment]::NewLine
    $answer=[System.Windows.Forms.MessageBox]::Show(
        ('Cache selected repository apps?'+$nl+$nl+'- '+($names -join ($nl+'- '))),
        'OSDStage - Cache selected','YesNo','Question'
    )
    if($answer -ne [System.Windows.Forms.DialogResult]::Yes){return}

    $payload=[pscustomobject]@{
        ModulePath=Join-Path $script:moduleRoot 'OSDStage.psd1'
        CatalogUri=$catalogUri.AbsoluteUri
        Names=$names
    }
    $worker={
        param($Payload)
        Import-Module -Name ([string]$Payload.ModulePath) -Force -ErrorAction Stop
        Set-OSDStageConfiguration -CatalogUri ([uri]$Payload.CatalogUri)|Out-Null
        Write-Output([pscustomobject]@{RecordType='Progress';Position=0;Total=1;Message="Caching $(@($Payload.Names).Count) repository app(s)..."})
        Sync-OSDStageRepository -Name @($Payload.Names) -Confirm:$false -ErrorAction Stop|Out-Null
        Write-Output([pscustomobject]@{RecordType='Progress';Position=1;Total=1;Message='Repository cache synchronized'})
    }
    [void](Invoke-OSDStageUIManagerJob -State $State -Title 'OSDStage - Caching selected apps' -InitialActivity 'Preparing repository cache...' -Worker $worker -Payload $payload)
    Invoke-OSDStageUIManagerRefresh -State $State
}
