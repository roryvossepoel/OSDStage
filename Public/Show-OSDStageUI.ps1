function Set-OSDStageUIColumnWidths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][ValidateSet('Staged','Packages','Cache','Logs')][string]$Key
    )

    $list = $State.Lists[$Key]
    if (-not $list -or $list.Columns.Count -eq 0) { return }

    # Reserve enough room for Teams' four-part package version, and let
    # App / Message absorb remaining space on window resize.
    $fixed = switch ($Key) {
        'Staged'       { @(65,0,90,95,100,125,185,105) }
        'Packages' { @(0,80,95,90,150,130,150) }
        'Cache'        { @(0,75,95,88,145,90,105,70,105,105,120) }
        'Logs'         { @(185,78,135,125,0) }
    }
    $flexIndex = if ($Key -in @('Staged','Packages','Cache')) {
        if ($Key -eq 'Staged') { 1 } else { 0 }
    } else { 4 }
    $minimumFlex = if ($Key -eq 'Logs') { 270 } elseif ($Key -in @('Packages','Cache')) { 180 } else { 200 }
    $reserved = 0
    foreach ($width in $fixed) { $reserved += [int]$width }
    $available = [math]::Max(0,$list.ClientSize.Width - 22)
    $flexWidth = [math]::Max($minimumFlex,$available - $reserved)

    for ($i=0; $i -lt $fixed.Count -and $i -lt $list.Columns.Count; $i++) {
        $width = if ($i -eq $flexIndex) { $flexWidth } else { [int]$fixed[$i] }
        if ($width -gt 0 -and $list.Columns[$i].Width -ne $width) {
            $list.Columns[$i].Width = $width
        }
    }
}

function Show-OSDStageUIRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][ValidateSet('Staged','Packages','Cache','Logs')][string]$Key
    )

    $view = $State.Lists[$Key]
    $rows = @($State.Rows[$Key])
    $needle = [string]$State.Search.Text
    if (-not [string]::IsNullOrWhiteSpace($needle)) {
        $rows = @($rows | Where-Object {
            $searchable = @($_.SubItems | ForEach-Object { [string]$_.Text }) -join ' '
            $searchable.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
    }

    $sorting = $State.Sorts[$Key]
    if ($sorting.Column -ge 0) {
        $column = [int]$sorting.Column
        $rows = @($rows | Sort-Object -Property @{
            Expression = {
                $value = [string]$_.SubItems[$column].Text
                if ($Key -eq 'Staged' -and $column -eq 0) {
                    [int]$value
                }
                elseif ($Key -eq 'Cache' -and $column -eq 7) {
                    $parsed = [double]0
                    $rawValue = $value.Replace(' MB','').Replace(',','.')
                    if ([double]::TryParse($rawValue,[System.Globalization.NumberStyles]::Float,
                        [System.Globalization.CultureInfo]::InvariantCulture,[ref]$parsed)) { $parsed } else { -1.0 }
                }
                else { $value.ToLowerInvariant() }
            }
        } -Descending:([bool]$sorting.Descending))
    }

    $view.BeginUpdate()
    try {
        $view.Items.Clear()
        foreach ($item in $rows) {
            [void]$view.Items.Add($item)
        }
    }
    finally { $view.EndUpdate() }
}

function Set-OSDStageUIListSort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][ValidateSet('Staged','Packages','Cache','Logs')][string]$Key,
        [Parameter(Mandatory)][int]$Column
    )

    $previous = $State.Sorts[$Key]
    $descending = if ($previous.Column -eq $Column) { -not [bool]$previous.Descending } else { $false }
    $State.Sorts[$Key] = @{ Column=$Column; Descending=$descending }
    Show-OSDStageUIRows -State $State -Key $Key
}

function Update-OSDStageUILogViewer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    $State.Rows['Logs'] = @()
    $State.LogDetails.Text = ''
    $selected = $State.LogFiles.SelectedIndex
    if ($selected -lt 0 -or $selected -ge @($State.LogEntries).Count) {
        $State.LogInfo.Text = 'Select an available log file.'
        Show-OSDStageUIRows -State $State -Key Logs
        return
    }

    $path = [string]$State.LogEntries[$selected].Path
    try {
        $entries = @(Get-OSDStageUILogRows -Path $path -Tail 500)
        $items = @(
            foreach ($entry in $entries) {
                $item = [System.Windows.Forms.ListViewItem]::new([string]$entry.Timestamp)
                [void]$item.SubItems.Add([string]$entry.Level)
                [void]$item.SubItems.Add([string]$entry.Component)
                [void]$item.SubItems.Add([string]$entry.Event)
                [void]$item.SubItems.Add([string]$entry.Message)
                if ($entry.Level -eq 'Error') {
                    $item.ForeColor = [System.Drawing.Color]::Firebrick
                }
                elseif ($entry.Level -eq 'Warning') {
                    $item.ForeColor = [System.Drawing.Color]::DarkOrange
                }
                $item.Tag = $entry
                $item.ToolTipText = [string]$entry.Raw
                $item
            }
        )
        $State.Rows['Logs'] = $items
        $State.LogInfo.Text = "$($entries.Count) recent lines | $path"
        Show-OSDStageUIRows -State $State -Key Logs
        Set-OSDStageUIColumnWidths -State $State -Key Logs

        # The log details pane should be useful immediately after opening.
        # Select the most recent visible entry without changing log order.
        $visible = $State.Lists['Logs']
        if ($visible.Items.Count -gt 0) {
            $last = $visible.Items[$visible.Items.Count - 1]
            $last.Selected = $true
            $entry = $last.Tag
            $State.LogDetails.Text = "Time: $($entry.Timestamp) | Level: $($entry.Level) | Component: $($entry.Component) | Event: $($entry.Event)" +
                [Environment]::NewLine + [Environment]::NewLine + [string]$entry.Message
        }
        else {
            $State.LogDetails.Text = 'No log entries match the current search.'
        }
    }
    catch {
        $State.LogInfo.Text = "Cannot read log: $($_.Exception.Message)"
        $State.LogDetails.Text = 'Unable to load the selected log file.'
        Show-OSDStageUIRows -State $State -Key Logs
    }
}

function Update-OSDStageUIReadOnlyView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter()]$Snapshot
    )

    $data = if ($Snapshot) { $Snapshot } else { Get-OSDStageUIReadOnlySnapshot -WindowsPath $State.Target -Offline:$State.Offline -SkipSignatureVerification:$State.SkipSignatureVerification }
    $State.Snapshot = $data
    $builtInMetadata = @(Get-OSDStageUIBuiltInMetadata)

    $stagedItems = @(
        $number = 0
        foreach ($app in @($data.StagedApps)) {
            $number++
            $item = [System.Windows.Forms.ListViewItem]::new([string]$number)
            $displayInfo = Get-OSDStageUIDisplayInfo -App $app -CatalogApps $data.CatalogApps -BuiltInMetadata $builtInMetadata
            [void]$item.SubItems.Add([string]$displayInfo.DisplayName)
            [void]$item.SubItems.Add($(if ($app.Source -eq 'BuiltIn') { 'Built-in' } else { 'Repository' }))
            [void]$item.SubItems.Add((Get-OSDStageUIPackageType -App $app))
            [void]$item.SubItems.Add([string]$displayInfo.Vendor)
            [void]$item.SubItems.Add((Get-OSDStageUIDisplayVersion -App $app))
            [void]$item.SubItems.Add((Get-OSDStageUICachedVersion -App $app -CacheEntries $data.CacheEntries))
            [void]$item.SubItems.Add([string]$app.Architecture)
            $item.Tag = [pscustomobject]@{ App=$app; Vendor=$displayInfo.Vendor }
            $item
        }
    )
    $State.Rows['Staged'] = $stagedItems

    $appItems = @(
        foreach ($app in @($data.CatalogApps | Sort-Object Source,DisplayName)) {
            $displayInfo = Get-OSDStageUIDisplayInfo -App $app -CatalogApps $data.CatalogApps -BuiltInMetadata $builtInMetadata
            $item = [System.Windows.Forms.ListViewItem]::new([string]$displayInfo.DisplayName)
            [void]$item.SubItems.Add($(if ($app.Source -eq 'BuiltIn') { 'Built-in' } else { 'Repository' }))
            [void]$item.SubItems.Add((Get-OSDStageUIPackageType -App $app))
            [void]$item.SubItems.Add([string]$displayInfo.Vendor)
            [void]$item.SubItems.Add((Get-OSDStageUIDisplayVersion -App $app))
            [void]$item.SubItems.Add((Get-OSDStageUICachedVersion -App $app -CacheEntries $data.CacheEntries))
            [void]$item.SubItems.Add([string]$app.Architecture)
            [void]$item.SubItems.Add((Get-OSDStageUIAvailabilityLabel -Availability $app.Availability -Offline:$State.Offline))
            [void]$item.SubItems.Add($(if ([string]$app.Id -in @($data.StagedApps.Id)) { 'Staged' } else { '-' }))
            $item
        }
        # Staged apps absent from the current catalog/cache remain visible.
        foreach ($app in @($data.StagedApps)) {
            if ([string]$app.Id -in @($data.CatalogApps.Id)) { continue }
            $displayInfo = Get-OSDStageUIDisplayInfo -App $app -CatalogApps $data.CatalogApps -BuiltInMetadata $builtInMetadata
            $item = [System.Windows.Forms.ListViewItem]::new([string]$displayInfo.DisplayName)
            [void]$item.SubItems.Add($(if ($app.Source -eq 'BuiltIn') { 'Built-in' } else { 'Repository' }))
            [void]$item.SubItems.Add((Get-OSDStageUIPackageType -App $app))
            [void]$item.SubItems.Add([string]$displayInfo.Vendor)
            [void]$item.SubItems.Add((Get-OSDStageUIDisplayVersion -App $app))
            [void]$item.SubItems.Add((Get-OSDStageUICachedVersion -App $app -CacheEntries $data.CacheEntries))
            [void]$item.SubItems.Add([string]$app.Architecture)
            [void]$item.SubItems.Add('Not in current catalog/cache')
            [void]$item.SubItems.Add('Staged')
            $item
        }
    )
    $State.Rows['Packages'] = $appItems

    $cacheItems = @(
        foreach ($entry in @($data.CacheEntries)) {
            $displayInfo = Get-OSDStageUIDisplayInfo -App $entry -CatalogApps $data.CatalogApps -BuiltInMetadata $builtInMetadata
            $item = [System.Windows.Forms.ListViewItem]::new([string]$displayInfo.DisplayName)
            [void]$item.SubItems.Add($(if ($entry.Source -eq 'BuiltIn') { 'Built-in' } else { 'Repository' }))
            [void]$item.SubItems.Add((Get-OSDStageUIPackageType -App $entry))
            [void]$item.SubItems.Add([string]$displayInfo.Vendor)
            $cacheVersion = [string]$entry.Version
            if ([string]::IsNullOrWhiteSpace($cacheVersion) -or $cacheVersion -eq 'Current') { $cacheVersion = 'Not recorded' }
            [void]$item.SubItems.Add($cacheVersion)
            [void]$item.SubItems.Add([string]$entry.Architecture)
            $integrity = if (-not $entry.Valid) {
                'Missing / invalid'
            }
            elseif ($entry.Source -eq 'Repository') {
                'SHA-256 verified'
            }
            else {
                'Files present'
            }
            [void]$item.SubItems.Add($integrity)
            [void]$item.SubItems.Add($(if ($null -ne $entry.SizeMB) { "$($entry.SizeMB) MB" } else { '-' }))
            [void]$item.SubItems.Add((Get-OSDStageUISignatureLabel -Status ([string]$entry.SignatureStatus) -Source ([string]$entry.Source)))
            if ([string]$entry.Source -eq 'BuiltIn' -and
                [string]$entry.SignatureStatus -in @('NotSigned','NotTrusted','HashMismatch','PublisherMismatch','Check failed','File missing','UnknownError')) {
                $item.ForeColor = [System.Drawing.Color]::Firebrick
            }
            $item.ToolTipText = @(
                "Integrity: $integrity"
                "Signature: $($entry.SignatureStatus)"
                "Scope: $($entry.SignatureScope)"
                "Signed file: $($entry.SignatureFile)"
                "Signer: $($entry.SignatureSigner)"
            ) -join [Environment]::NewLine
            $item.Tag = $entry
            $item
        }
    )
    $State.Rows['Cache'] = $cacheItems

    foreach ($key in @('Staged','Packages','Cache')) {
        Show-OSDStageUIRows -State $State -Key $key
        Set-OSDStageUIColumnWidths -State $State -Key $key
    }

    $State.LogFiles.Items.Clear()
    $State.LogEntries = @($data.Logs)
    foreach ($entry in $State.LogEntries) {
        [void]$State.LogFiles.Items.Add([string]$entry.Label)
    }
    if ($State.LogFiles.Items.Count -gt 0) {
        $State.LogFiles.SelectedIndex = 0
    }
    else {
        $State.Rows['Logs'] = @()
        $State.LogInfo.Text = 'No existing OSDStage log files found on the device or USB cache.'
        $State.LogDetails.Text = ''
        Show-OSDStageUIRows -State $State -Key Logs
    }

    $stagedCount = @($data.StagedApps).Count
    $builtInCount = @($data.StagedApps | Where-Object Source -eq 'BuiltIn').Count
    $repositoryCount = @($data.StagedApps | Where-Object Source -eq 'Repository').Count
    $setupStatus = if ($data.SetupCompleteExists) { 'Present' } else { 'Not found' }
    $State.StagedInfo.Text = "$stagedCount staged for SetupComplete | $builtInCount built-in, $repositoryCount repository | SetupComplete.cmd: $setupStatus"
    $State.CacheInfo.Text = if ($data.CachePath) {
        "USB cache: $($data.CachePath) | $(@($data.CacheEntries).Count) entries | Signatures: $(if ($State.SkipSignatureVerification) { 'skipped' } elseif ($State.WinPE) { 'unavailable in WinPE' } else { 'checked where supported' })"
    } else {
        'USB cache: not connected / not found.'
    }
    $usbLabel = if ($data.CachePath) { [string]$data.CachePath } else { 'not connected' }
    $State.ContextStatus.Text = "Target: $($State.TargetKind)  |  USB: $usbLabel  |  $($State.CatalogMode)"
    $detail = "Target: $($State.TargetDescription)" + [Environment]::NewLine +
        "USB: $usbLabel" + [Environment]::NewLine + $State.CatalogDescription
    $State.ContextToolTip.SetToolTip($State.ContextStatus,$detail)
    # Show a real staged manifest entry by default instead of an empty panel.
    # This is only a UI selection; it does not change DeviceManifest ordering.
    if ($State.StagedList.Items.Count -gt 0) {
        $first = $State.StagedList.Items[0]
        $first.Selected = $true
        $selected = $first.Tag
        $State.Details.Text = Format-OSDStageUIStagedDetails -App $selected.App -Vendor $selected.Vendor
    }
    else {
        $State.Details.Text = if ($stagedCount) {
            'No staged apps match the current search.'
        } else {
            'No staged apps found. Stage apps using the PowerShell CLI first.'
        }
    }
    $State.Status.Text = "$stagedCount staged | $(@($data.CacheEntries).Count) USB cache entries | $(@($data.Logs).Count) logs"
    if (Get-Command Update-OSDStageUIManagerRows -ErrorAction SilentlyContinue) { Update-OSDStageUIManagerRows -State $State -PreserveChecks }
}

function Get-OSDStageUICacheUpdateStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter()]$RepositoryCatalog
    )

    $current = [string]$Entry.Version
    $latest = $null
    $status = 'Not checked'
    $detail = $null

    try {
        if ([string]$Entry.Source -eq 'Repository') {
            if (-not $RepositoryCatalog) {
                return [pscustomobject]@{ Latest=$null; Status='No catalog'; Detail='No repository catalog is available.' }
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
            else { $status = 'Ambiguous' }
        }
        elseif ([string]$Entry.Id -eq '7Zip') {
            $release = Get-OSDStage7ZipRelease -Architecture ([string]$Entry.Architecture)
            $latest = [string]$release.Version
            $status = if ($latest -ne $current) { 'Update available' } else { 'Current' }
        }
        elseif ([string]$Entry.Id -eq 'VisualStudioCode') {
            $release = Get-OSDStageVisualStudioCodeRelease -Architecture ([string]$Entry.Architecture)
            $latest = [string]$release.Version
            $status = if ($latest -ne $current) { 'Update available' } else { 'Current' }
        }
        elseif ([string]$Entry.Id -eq 'DotNetRuntime') {
            $spec = Get-OSDStagePrerequisiteSpec -Family DotNetRuntime -Architecture ([string]$Entry.Architecture) -Channel ([string]$Entry.Channel) -RuntimeType ([string]$Entry.RuntimeType)
            $release = Get-OSDStagePrerequisiteRelease -Spec $spec
            $latest = [string]$release.Version
            $status = if ($latest -and $latest -ne $current) { 'Update available' } else { 'Current' }
        }
    }
    catch {
        $status = 'Check failed'
        $detail = $_.Exception.Message
    }

    [pscustomobject]@{ Latest=$latest; Status=$status; Detail=$detail }
}

function Update-OSDStageUICacheUpdateStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    if (-not $State.Snapshot -or -not $State.Snapshot.CachePath) { throw 'No OSDStage USB cache is currently connected.' }

    $repositoryCatalog = $null
    $catalogUri = (Get-OSDStageConfiguration).CatalogUri
    if ($catalogUri) {
        try { $repositoryCatalog = Get-OSDStageCatalogPackages -CatalogUri $catalogUri }
        catch { Write-Verbose "Repository update check unavailable: $($_.Exception.Message)" }
    }

    $results = @{}
    foreach ($entry in @($State.Snapshot.CacheEntries)) {
        $key = "$([string]$entry.Source):$([string]$entry.Id):$([string]$entry.Architecture):$([string]$entry.Channel):$([string]$entry.RuntimeType)"
        $results[$key] = Get-OSDStageUICacheUpdateStatus -Entry $entry -RepositoryCatalog $repositoryCatalog
    }
    $State.CacheUpdateStatus = $results

    foreach ($item in @($State.Rows['Cache'])) {
        $entry = $item.Tag
        $key = "$([string]$entry.Source):$([string]$entry.Id):$([string]$entry.Architecture):$([string]$entry.Channel):$([string]$entry.RuntimeType)"
        $result = $results[$key]
        while ($item.SubItems.Count -lt 11) { [void]$item.SubItems.Add('') }
        $item.SubItems[9].Text = if ($result -and $result.Latest) { [string]$result.Latest } else { '-' }
        $item.SubItems[10].Text = if ($result) { [string]$result.Status } else { 'Not checked' }
        if ($result -and $result.Status -eq 'Update available') { $item.ForeColor = [System.Drawing.Color]::DarkOrange }
        elseif ($result -and $result.Status -eq 'Check failed') { $item.ForeColor = [System.Drawing.Color]::Firebrick }
        if ($result -and $result.Detail) { $item.ToolTipText += [Environment]::NewLine + "Update check: $($result.Detail)" }
    }

    Show-OSDStageUIRows -State $State -Key Cache
    Set-OSDStageUIColumnWidths -State $State -Key Cache
    $available = @($results.Values | Where-Object Status -eq 'Update available').Count
    $failed = @($results.Values | Where-Object Status -eq 'Check failed').Count
    $State.Status.Text = "Update check complete | $available update(s) available | $failed check(s) failed"
    [pscustomobject]@{ Available=$available; Failed=$failed; Results=$results }
}
function Invoke-OSDStageUICacheUpdate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    if (-not $State.Snapshot -or -not $State.Snapshot.CachePath) {
        throw 'No OSDStage USB cache is currently connected.'
    }

    $entries = @($State.Snapshot.CacheEntries)
    $updated = [System.Collections.Generic.List[string]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()

    if (@($entries | Where-Object Source -eq 'Repository').Count -gt 0) {
        try {
            $catalogUri = (Get-OSDStageConfiguration).CatalogUri
            if ($catalogUri) {
                Sync-OSDStageRepository -Confirm:$false | Out-Null
                $updated.Add('Repository')
            }
            else {
                $skipped.Add('Repository: no CatalogUri configured')
            }
        }
        catch {
            $failed.Add("Repository: $($_.Exception.Message)")
        }
    }

    $builtInEntries = @(
        $entries |
            Where-Object Source -eq 'BuiltIn' |
            Sort-Object Id,Architecture,Channel,RuntimeType,CachePath -Unique
    )

    foreach ($entry in $builtInEntries) {
        $commandName = "Sync-OSDStage$($entry.Id)"
        $command = Get-Command -Name $commandName -Module OSDStage -ErrorAction SilentlyContinue
        if (-not $command) {
            $skipped.Add("$($entry.Id): no sync command")
            continue
        }

        $parameters = @{}
        if ($command.Parameters.ContainsKey('Architecture') -and $entry.Architecture) {
            $parameters.Architecture = [string]$entry.Architecture
        }
        if ($command.Parameters.ContainsKey('Channel') -and $entry.Channel) {
            $parameters.Channel = [string]$entry.Channel
        }
        if ($command.Parameters.ContainsKey('RuntimeType') -and $entry.RuntimeType) {
            $parameters.RuntimeType = [string]$entry.RuntimeType
        }

        if ([string]$entry.Id -eq 'Microsoft365Apps') {
            $configurationXml = Join-Path ([string]$entry.CachePath) 'configuration.xml'
            if (-not (Test-Path -LiteralPath $configurationXml -PathType Leaf)) {
                $skipped.Add('Microsoft365Apps: cached configuration.xml not found')
                continue
            }
            $parameters.ConfigurationXml = $configurationXml
        }

        $missingMandatory = @(
            foreach ($parameter in $command.Parameters.Values) {
                if (-not $parameter.Attributes) { continue }
                $mandatory = @($parameter.Attributes | Where-Object {
                    $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
                }).Count -gt 0
                if ($mandatory -and -not $parameters.ContainsKey($parameter.Name)) {
                    $parameter.Name
                }
            }
        )
        if ($missingMandatory.Count -gt 0) {
            $skipped.Add("$($entry.Id): missing $($missingMandatory -join ', ')")
            continue
        }

        try {
            if ($command.Parameters.ContainsKey('Confirm')) { $parameters.Confirm = $false }
            & $commandName @parameters | Out-Null
            $label = [string]$entry.Id
            if ($entry.Architecture) { $label += " ($($entry.Architecture))" }
            $updated.Add($label)
        }
        catch {
            $failed.Add("$($entry.Id): $($_.Exception.Message)")
        }
    }

    [pscustomobject]@{
        Updated = @($updated)
        Skipped = @($skipped)
        Failed  = @($failed)
    }
}

function Format-OSDStageUICacheHealth {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Health)

    @(
        "Cache: $(if ($Health.CacheAvailable) { 'Available' } else { 'Not available' })"
        "Health: $(if ($Health.Healthy) { 'Healthy' } else { 'Needs attention' })"
        "Entries: $($Health.EntryCount)"
        "Active: $($Health.ActiveCount)"
        "Obsolete: $($Health.ObsoleteCount)"
        "Orphaned: $($Health.OrphanedCount)"
        "Incomplete: $($Health.IncompleteCount)"
        "Corrupt: $($Health.CorruptCount)"
        "Removable: $($Health.RemovableSizeMB) MB"
        "Desired state: $(if ($Health.DesiredStateAvailable) { 'Available' } else { 'Unavailable' })"
    ) -join [Environment]::NewLine
}

function Show-OSDStageUI {
    <#
    .SYNOPSIS
    Read-only inspector for staged OSDStage content, package availability,
    USB cache, and logs. All staging and configuration stay PowerShell CLI-only.
    .EXAMPLE
    Show-OSDStageUI -Offline
    .EXAMPLE
    Show-OSDStageUI -TestMode -Offline
    .EXAMPLE
    Show-OSDStageUI -WindowsPath 'D:\' -Offline
    #>
    [CmdletBinding()]
    param(
        [string]$WindowsPath,
        [switch]$Offline,
        [switch]$PreviewOnly,
        [switch]$TestMode,
        [switch]$SkipSignatureVerification
    )

    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
        throw 'An STA session is required. Run Windows PowerShell with powershell.exe -STA -NoProfile.'
    }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    }
    catch {
        throw "Windows Forms is unavailable in this Windows/WinPE image: $($_.Exception.Message)"
    }
    if ($script:OSDStageUIState) { throw 'OSDStage Viewer is already open.' }
    if ($TestMode -and $PSBoundParameters.ContainsKey('WindowsPath')) {
        throw '-TestMode points to the existing isolated TEMP test folder. Do not also specify -WindowsPath.'
    }

    $winPE = Test-OSDStageWinPE
    $target = $null
    $targetText = 'No Windows target detected'
    if ($TestMode) {
        $candidate = Get-OSDStageUITestWindowsPath
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $target = $candidate
            $targetText = "Test folder: $target"
        }
        else {
            $targetText = "Test folder not present: $candidate"
        }
    }
    elseif ($PSBoundParameters.ContainsKey('WindowsPath')) {
        $target = Resolve-OSDStageWindowsPath -WindowsPath $WindowsPath
        $targetText = "Read-only Windows target: $target"
    }
    elseif ($winPE) {
        try {
            $target = Resolve-OSDStageWindowsPath
            $targetText = "WinPE target: $target"
        }
        catch {
            $targetText = "WinPE: $($_.Exception.Message)"
        }
    }
    elseif ($env:SystemDrive) {
        $target = [System.IO.Path]::GetPathRoot((Join-Path $env:SystemDrive '\Windows'))
        $targetText = "Windows target: $target"
    }

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'OSDStage Inspector'
    $form.Size = [System.Drawing.Size]::new(980,710)
    $form.MinimumSize = [System.Drawing.Size]::new(800,580)
    $form.StartPosition = 'CenterScreen'
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.Font = [System.Drawing.Font]::new('Segoe UI',9)

    $root = [System.Windows.Forms.TableLayoutPanel]::new()
    $root.Dock = 'Fill'
    $root.RowCount = 5
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',80))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',34))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',42))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',45))
    $form.Controls.Add($root)

    $header = [System.Windows.Forms.Panel]::new()
    $header.Dock = 'Fill'
    $header.BackColor = [System.Drawing.Color]::FromArgb(35,59,95)
    [void]$root.Controls.Add($header,0,0)

    $title = [System.Windows.Forms.Label]::new()
    $title.Text = 'OSDStage Inspector'
    $title.Font = [System.Drawing.Font]::new('Segoe UI',17,[System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::White
    $title.SetBounds(18,9,670,37)
    $title.Anchor = 'Top,Left,Right'
    $header.Controls.Add($title)

    $subtitle = [System.Windows.Forms.Label]::new()
    $subtitle.Text = 'Staged content, cache and diagnostics'
    $subtitle.ForeColor = [System.Drawing.Color]::Gainsboro
    $subtitle.SetBounds(20,49,560,23)
    $header.Controls.Add($subtitle)

    $context = [System.Windows.Forms.Panel]::new()
    $context.Dock = 'Fill'
    $context.BackColor = [System.Drawing.Color]::FromArgb(242,244,247)
    [void]$root.Controls.Add($context,0,1)

    $targetKind = if ($TestMode) { 'Test environment' } elseif ($winPE) { 'Offline Windows' } else { 'Windows' }
    $catalogUri = (Get-OSDStageConfiguration).CatalogUri
    $catalogMode = if ($Offline) { 'Offline' } elseif ($catalogUri) { 'Online' } else { 'No catalog' }
    $catalogDescription = if ($Offline) {
        'Catalog lookup disabled (-Offline).'
    } elseif ($catalogUri) {
        "Catalog: $($catalogUri.AbsoluteUri)"
    } else {
        'Repository not configured in this PowerShell session.'
    }

    $contextStatus = [System.Windows.Forms.Label]::new()
    $contextStatus.Dock = 'Fill'
    $contextStatus.Padding = [System.Windows.Forms.Padding]::new(14,0,8,0)
    $contextStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $contextStatus.AutoEllipsis = $true
    $contextStatus.Text = "Target: $targetKind  |  USB: detecting...  |  $catalogMode"
    [void]$context.Controls.Add($contextStatus)

    $toolTip = [System.Windows.Forms.ToolTip]::new()
    $contextToolTip = "Target: $targetText" + [Environment]::NewLine + $catalogDescription
    $toolTip.SetToolTip($contextStatus,$contextToolTip)


    $searchPanel = [System.Windows.Forms.TableLayoutPanel]::new()
    $searchPanel.Dock = 'Fill'
    $searchPanel.ColumnCount = 2
    $searchPanel.Padding = [System.Windows.Forms.Padding]::new(8,5,8,5)
    [void]$searchPanel.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Absolute',73))
    [void]$searchPanel.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent',100))
    [void]$root.Controls.Add($searchPanel,0,2)
    $searchLabel = [System.Windows.Forms.Label]::new()
    $searchLabel.Text = 'Search'
    $searchLabel.Dock = 'Fill'
    $searchLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    [void]$searchPanel.Controls.Add($searchLabel,0,0)
    $searchBox = [System.Windows.Forms.TextBox]::new()
    $searchBox.Dock = 'Fill'
    [void]$searchPanel.Controls.Add($searchBox,1,0)

    $tabs = [System.Windows.Forms.TabControl]::new()
    $tabs.Dock = 'Fill'
    [void]$root.Controls.Add($tabs,0,3)
    $stagedTab = [System.Windows.Forms.TabPage]::new('Staged for device')
    $catalogTab = [System.Windows.Forms.TabPage]::new('Cache manager')
    $cacheTab = [System.Windows.Forms.TabPage]::new('Cache')
    $logsTab = [System.Windows.Forms.TabPage]::new('Logs')
    foreach ($tab in @($stagedTab,$catalogTab,$logsTab)) { [void]$tabs.TabPages.Add($tab) }

    $stagedLayout = [System.Windows.Forms.TableLayoutPanel]::new()
    $stagedLayout.Dock = 'Fill'
    $stagedLayout.RowCount = 3
    [void]$stagedLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',38))
    [void]$stagedLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$stagedLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',160))
    $stagedTab.Controls.Add($stagedLayout)
    $stagedInfo = [System.Windows.Forms.Label]::new()
    $stagedInfo.Dock = 'Fill'
    $stagedInfo.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    [void]$stagedLayout.Controls.Add($stagedInfo,0,0)
    $stagedList = [System.Windows.Forms.ListView]::new()
    $stagedList.Dock = 'Fill'
    $stagedList.View = 'Details'
    $stagedList.FullRowSelect = $true
    $stagedList.GridLines = $true
    $stagedList.MultiSelect = $false
    [void]$stagedList.Columns.Add('Order',65)
    [void]$stagedList.Columns.Add('Display Name',270)
    [void]$stagedList.Columns.Add('Source',90)
    [void]$stagedList.Columns.Add('Package Type',95)
    [void]$stagedList.Columns.Add('Vendor',100)
    [void]$stagedList.Columns.Add('Version / policy',125)
    [void]$stagedList.Columns.Add('USB version',185)
    [void]$stagedList.Columns.Add('Architecture',105)
    [void]$stagedLayout.Controls.Add($stagedList,0,1)
    $details = [System.Windows.Forms.TextBox]::new()
    $details.Multiline = $true
    $details.ReadOnly = $true
    $details.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $details.Dock = 'Fill'
    $details.BackColor = [System.Drawing.Color]::White
    [void]$stagedLayout.Controls.Add($details,0,2)

    $catalogLayout = [System.Windows.Forms.TableLayoutPanel]::new()
    $catalogLayout.Dock = 'Fill'
    $catalogLayout.RowCount = 4
    [void]$catalogLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',34))
    [void]$catalogLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',42))
    [void]$catalogLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$catalogLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',145))
    $catalogTab.Controls.Add($catalogLayout)

    $catalogInfo = [System.Windows.Forms.Label]::new()
    $catalogInfo.Text = 'Loading cache manager...'
    $catalogInfo.Dock = 'Fill'
    $catalogInfo.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $catalogInfo.AutoEllipsis = $true
    [void]$catalogLayout.Controls.Add($catalogInfo,0,0)

    $managerActions = [System.Windows.Forms.FlowLayoutPanel]::new()
    $managerActions.Dock = 'Fill'
    $managerActions.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $managerActions.WrapContents = $false
    $managerActions.Padding = [System.Windows.Forms.Padding]::new(0,3,0,3)
    [void]$catalogLayout.Controls.Add($managerActions,0,1)

    $managerRefresh = [System.Windows.Forms.Button]::new()
    $managerRefresh.Text = 'Refresh'
    $managerRefresh.AutoSize = $true
    $managerActions.Controls.Add($managerRefresh)

    $managerHealth = [System.Windows.Forms.Button]::new()
    $managerHealth.Text = 'Check health'
    $managerHealth.AutoSize = $true
    $managerActions.Controls.Add($managerHealth)

    $managerCheckUpdates = [System.Windows.Forms.Button]::new()
    $managerCheckUpdates.Text = 'Check updates'
    $managerCheckUpdates.AutoSize = $true
    $managerActions.Controls.Add($managerCheckUpdates)

    $managerCacheSelected = [System.Windows.Forms.Button]::new()
    $managerCacheSelected.Text = 'Cache selected'
    $managerCacheSelected.AutoSize = $true
    $managerActions.Controls.Add($managerCacheSelected)

    $managerUpdateSelected = [System.Windows.Forms.Button]::new()
    $managerUpdateSelected.Text = 'Update selected'
    $managerUpdateSelected.AutoSize = $true
    $managerActions.Controls.Add($managerUpdateSelected)

    $managerUpdateAll = [System.Windows.Forms.Button]::new()
    $managerUpdateAll.Text = 'Update all available'
    $managerUpdateAll.AutoSize = $true
    $managerActions.Controls.Add($managerUpdateAll)

    $managerRemoveSelected = [System.Windows.Forms.Button]::new()
    $managerRemoveSelected.Text = 'Remove selected...'
    $managerRemoveSelected.AutoSize = $true
    $managerActions.Controls.Add($managerRemoveSelected)

    $managerClearAll = [System.Windows.Forms.Button]::new()
    $managerClearAll.Text = 'Clear entire cache...'
    $managerClearAll.AutoSize = $true
    $managerActions.Controls.Add($managerClearAll)

    $catalogList = [System.Windows.Forms.ListView]::new()
    $catalogList.Dock = 'Fill'
    $catalogList.View = 'Details'
    $catalogList.FullRowSelect = $true
    $catalogList.MultiSelect = $false
    $catalogList.CheckBoxes = $true
    $catalogList.GridLines = $true
    $catalogList.ShowItemToolTips = $true
    [void]$catalogList.Columns.Add('App',260)
    [void]$catalogList.Columns.Add('Source',80)
    [void]$catalogList.Columns.Add('Package Type',95)
    [void]$catalogList.Columns.Add('Vendor',90)
    [void]$catalogList.Columns.Add('Cached version',150)
    [void]$catalogList.Columns.Add('Available version',130)
    [void]$catalogList.Columns.Add('Status',150)
    [void]$catalogLayout.Controls.Add($catalogList,0,2)

    $managerDetails = [System.Windows.Forms.TextBox]::new()
    $managerDetails.Multiline = $true
    $managerDetails.ReadOnly = $true
    $managerDetails.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $managerDetails.Dock = 'Fill'
    $managerDetails.BackColor = [System.Drawing.Color]::White
    $managerDetails.Font = [System.Drawing.Font]::new('Consolas',9)
    $managerDetails.Text = 'Select an app to view its cached configurations.'
    [void]$catalogLayout.Controls.Add($managerDetails,0,3)

    $cacheLayout = [System.Windows.Forms.TableLayoutPanel]::new()
    $cacheLayout.Dock = 'Fill'
    $cacheLayout.RowCount = 3
    [void]$cacheLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',38))
    [void]$cacheLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',42))
    [void]$cacheLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    $cacheTab.Controls.Add($cacheLayout)
    $cacheInfo = [System.Windows.Forms.Label]::new()
    $cacheInfo.Dock = 'Fill'
    $cacheInfo.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $cacheInfo.AutoEllipsis = $true
    [void]$cacheLayout.Controls.Add($cacheInfo,0,0)

    $cacheActions = [System.Windows.Forms.FlowLayoutPanel]::new()
    $cacheActions.Dock = 'Fill'
    $cacheActions.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $cacheActions.WrapContents = $false
    $cacheActions.Padding = [System.Windows.Forms.Padding]::new(0,3,0,3)
    [void]$cacheLayout.Controls.Add($cacheActions,0,1)

    $cacheRefresh = [System.Windows.Forms.Button]::new()
    $cacheRefresh.Text = 'Refresh'
    $cacheRefresh.AutoSize = $true
    $cacheActions.Controls.Add($cacheRefresh)

    $cacheHealth = [System.Windows.Forms.Button]::new()
    $cacheHealth.Text = 'Check health'
    $cacheHealth.AutoSize = $true
    $cacheActions.Controls.Add($cacheHealth)

    $cacheCheckUpdates = [System.Windows.Forms.Button]::new()
    $cacheCheckUpdates.Text = 'Check updates'
    $cacheCheckUpdates.AutoSize = $true
    $cacheActions.Controls.Add($cacheCheckUpdates)

    $cacheUpdate = [System.Windows.Forms.Button]::new()
    $cacheUpdate.Text = 'Update cache'
    $cacheUpdate.AutoSize = $true
    $cacheActions.Controls.Add($cacheUpdate)

    $cacheClear = [System.Windows.Forms.Button]::new()
    $cacheClear.Text = 'Clear cache...'
    $cacheClear.AutoSize = $true
    $cacheActions.Controls.Add($cacheClear)

    $cacheList = [System.Windows.Forms.ListView]::new()
    $cacheList.Dock = 'Fill'
    $cacheList.View = 'Details'
    $cacheList.FullRowSelect = $true
    $cacheList.MultiSelect = $false
    $cacheList.GridLines = $true
    $cacheList.ShowItemToolTips = $true
    [void]$cacheList.Columns.Add('Display Name',265)
    [void]$cacheList.Columns.Add('Source',75)
    [void]$cacheList.Columns.Add('Package Type',95)
    [void]$cacheList.Columns.Add('Vendor',88)
    [void]$cacheList.Columns.Add('USB version',175)
    [void]$cacheList.Columns.Add('Architecture',105)
    [void]$cacheList.Columns.Add('Integrity',145)
    [void]$cacheList.Columns.Add('Size',100)
    [void]$cacheList.Columns.Add('Signature',120)
    [void]$cacheList.Columns.Add('Latest',105)
    [void]$cacheList.Columns.Add('Update status',120)
    [void]$cacheLayout.Controls.Add($cacheList,0,2)

    $logsLayout = [System.Windows.Forms.TableLayoutPanel]::new()
    $logsLayout.Dock = 'Fill'
    $logsLayout.RowCount = 4
    [void]$logsLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',43))
    [void]$logsLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',30))
    [void]$logsLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Percent',100))
    [void]$logsLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new('Absolute',110))
    $logsTab.Controls.Add($logsLayout)
    $logFiles = [System.Windows.Forms.ComboBox]::new()
    $logFiles.Dock = 'Fill'
    $logFiles.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $logFiles.Margin = [System.Windows.Forms.Padding]::new(7,8,7,4)
    [void]$logsLayout.Controls.Add($logFiles,0,0)
    $logInfo = [System.Windows.Forms.Label]::new()
    $logInfo.Text = 'Select a log entry to view its full details below.'
    $logInfo.Dock = 'Fill'
    $logInfo.AutoEllipsis = $true
    [void]$logsLayout.Controls.Add($logInfo,0,1)
    $logList = [System.Windows.Forms.ListView]::new()
    $logList.View = 'Details'
    $logList.Dock = 'Fill'
    $logList.FullRowSelect = $true
    $logList.MultiSelect = $false
    $logList.GridLines = $true
    $logList.ShowItemToolTips = $true
    [void]$logList.Columns.Add('Timestamp',185)
    [void]$logList.Columns.Add('Level',78)
    [void]$logList.Columns.Add('Component',135)
    [void]$logList.Columns.Add('Event',125)
    [void]$logList.Columns.Add('Message',420)
    [void]$logsLayout.Controls.Add($logList,0,2)
    $logDetails = [System.Windows.Forms.TextBox]::new()
    $logDetails.Multiline = $true
    $logDetails.ReadOnly = $true
    $logDetails.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $logDetails.Dock = 'Fill'
    $logDetails.BackColor = [System.Drawing.Color]::White
    $logDetails.Font = [System.Drawing.Font]::new('Consolas',9)
    [void]$logsLayout.Controls.Add($logDetails,0,3)

    $footer = [System.Windows.Forms.TableLayoutPanel]::new()
    $footer.Dock = 'Fill'
    $footer.ColumnCount = 3
    [void]$footer.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Percent',100))
    [void]$footer.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Absolute',120))
    [void]$footer.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new('Absolute',100))
    [void]$root.Controls.Add($footer,0,4)
    $status = [System.Windows.Forms.Label]::new()
    $status.Text = 'Loading inventory...'
    $status.Dock = 'Fill'
    $status.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    [void]$footer.Controls.Add($status,0,0)
    $refresh = [System.Windows.Forms.Button]::new()
    $refresh.Text = 'Refresh'
    $refresh.Dock = 'Fill'
    [void]$footer.Controls.Add($refresh,1,0)
    $close = [System.Windows.Forms.Button]::new()
    $close.Text = 'Close'
    $close.Dock = 'Fill'
    [void]$footer.Controls.Add($close,2,0)

    $script:OSDStageUIState = @{
        Form=$form; Target=$target; Offline=[bool]$Offline; Search=$searchBox
        SkipSignatureVerification=[bool]$SkipSignatureVerification; WinPE=[bool]$winPE
        ContextStatus=$contextStatus; ContextToolTip=$toolTip
        TargetKind=$targetKind; TargetDescription=$targetText
        CatalogMode=$catalogMode; CatalogDescription=$catalogDescription
        StagedList=$stagedList; CatalogList=$catalogList; CacheList=$cacheList
        ManagerList=$catalogList; ManagerInfo=$catalogInfo; ManagerDetails=$managerDetails
        ManagerRefresh=$managerRefresh; ManagerHealth=$managerHealth; ManagerCheckUpdates=$managerCheckUpdates
        ManagerCacheSelected=$managerCacheSelected; ManagerUpdateSelected=$managerUpdateSelected; ManagerUpdateAll=$managerUpdateAll
        ManagerRemoveSelected=$managerRemoveSelected; ManagerClearAll=$managerClearAll
        StagedInfo=$stagedInfo; CacheInfo=$cacheInfo; Details=$details
        CacheRefresh=$cacheRefresh; CacheHealth=$cacheHealth; CacheCheckUpdates=$cacheCheckUpdates; CacheUpdate=$cacheUpdate; CacheClear=$cacheClear
        CacheUpdateStatus=@{}
        LogFiles=$logFiles; LogList=$logList; LogDetails=$logDetails; LogInfo=$logInfo
        LogEntries=@(); Status=$status; Snapshot=$null
        Lists=@{ Staged=$stagedList; Packages=$catalogList; Cache=$cacheList; Logs=$logList }
        Rows=@{ Staged=@(); Packages=@(); Cache=@(); Logs=@() }
        Sorts=@{
            Staged=@{Column=-1;Descending=$false}
            Packages=@{Column=-1;Descending=$false}
            Cache=@{Column=-1;Descending=$false}
            Logs=@{Column=-1;Descending=$false}
        }
    }

    $stagedList.Add_SelectedIndexChanged({
        $state=$script:OSDStageUIState
        if (-not $state -or $state.StagedList.SelectedItems.Count -eq 0) { return }
        $selected = $state.StagedList.SelectedItems[0].Tag
        $state.Details.Text = Format-OSDStageUIStagedDetails -App $selected.App -Vendor $selected.Vendor
    })
    $catalogList.Add_SelectedIndexChanged({
        $state=$script:OSDStageUIState
        if ($state) { Update-OSDStageUIManagerDetails -State $state }
    })
    $managerRefresh.Add_Click({
        $state=$script:OSDStageUIState
        if ($state) { Invoke-OSDStageUIManagerRefresh -State $state }
    })
    $managerHealth.Add_Click({
        $state=$script:OSDStageUIState
        if ($state) { Invoke-OSDStageUIManagerHealthCheck -State $state }
    })
    $managerCheckUpdates.Add_Click({
        $state=$script:OSDStageUIState
        if (-not $state) { return }
        Invoke-OSDStageUIManagerCheckUpdates -State $state -AppKey @(Get-OSDStageUIManagerCheckedKeys -State $state)
    })
    $managerCacheSelected.Add_Click({
        $state=$script:OSDStageUIState
        if ($state) { Invoke-OSDStageUIManagerCacheSelected -State $state }
    })
    $managerUpdateSelected.Add_Click({
        $state=$script:OSDStageUIState
        if (-not $state) { return }
        $keys=@(Get-OSDStageUIManagerCheckedKeys -State $state)
        if ($keys.Count -eq 0) {
            [void][System.Windows.Forms.MessageBox]::Show('Select one or more cached apps first.','OSDStage - Update selected','OK','Information')
            return
        }
        Invoke-OSDStageUIManagerCheckUpdates -State $state -AppKey $keys
        [void](Invoke-OSDStageUICacheUpdate -State $state -SelectedAppKey $keys -SkipRecheck)
        Invoke-OSDStageUIManagerRefresh -State $state
    })
    $managerUpdateAll.Add_Click({
        $state=$script:OSDStageUIState
        if (-not $state) { return }
        Invoke-OSDStageUIManagerCheckUpdates -State $state
        [void](Invoke-OSDStageUICacheUpdate -State $state -SkipRecheck)
        Invoke-OSDStageUIManagerRefresh -State $state
    })
    $managerRemoveSelected.Add_Click({
        $state=$script:OSDStageUIState
        if ($state) { Invoke-OSDStageUIManagerRemoveSelected -State $state; Invoke-OSDStageUIManagerRefresh -State $state }
    })
    $managerClearAll.Add_Click({
        $state=$script:OSDStageUIState
        if ($state) { Invoke-OSDStageUIManagerClearEntireCache -State $state; Invoke-OSDStageUIManagerRefresh -State $state }
    })
    $logFiles.Add_SelectedIndexChanged({
        $state=$script:OSDStageUIState
        if ($state) { Update-OSDStageUILogViewer -State $state }
    })
    $logList.Add_SelectedIndexChanged({
        $state=$script:OSDStageUIState
        if (-not $state -or $state.LogList.SelectedItems.Count -eq 0) { return }
        $entry=$state.LogList.SelectedItems[0].Tag
        $state.LogDetails.Text = "Time: $($entry.Timestamp) | Level: $($entry.Level) | Component: $($entry.Component) | Event: $($entry.Event)" +
            [Environment]::NewLine + [Environment]::NewLine + [string]$entry.Message
    })
    $searchBox.Add_TextChanged({
        $state=$script:OSDStageUIState
        if (-not $state) { return }
        foreach ($key in @('Staged','Packages','Cache','Logs')) {
            Show-OSDStageUIRows -State $state -Key $key
        }
    })
    $stagedList.Add_ColumnClick({
        $state=$script:OSDStageUIState
        if ($state) { Set-OSDStageUIListSort -State $state -Key Staged -Column $_.Column }
    })
    $catalogList.Add_ColumnClick({
        $state=$script:OSDStageUIState
        if ($state) { Set-OSDStageUIListSort -State $state -Key Packages -Column $_.Column }
    })
    $cacheList.Add_ColumnClick({
        $state=$script:OSDStageUIState
        if ($state) { Set-OSDStageUIListSort -State $state -Key Cache -Column $_.Column }
    })
    $logList.Add_ColumnClick({
        $state=$script:OSDStageUIState
        if ($state) { Set-OSDStageUIListSort -State $state -Key Logs -Column $_.Column }
    })
    $stagedList.Add_ClientSizeChanged({
        $state = $script:OSDStageUIState
        if ($state) { Set-OSDStageUIColumnWidths -State $state -Key Staged }
    })
    $catalogList.Add_ClientSizeChanged({
        $state = $script:OSDStageUIState
        if ($state) { Set-OSDStageUIColumnWidths -State $state -Key Packages }
    })
    $cacheList.Add_ClientSizeChanged({
        $state = $script:OSDStageUIState
        if ($state) { Set-OSDStageUIColumnWidths -State $state -Key Cache }
    })
    $logList.Add_ClientSizeChanged({
        $state = $script:OSDStageUIState
        if ($state) { Set-OSDStageUIColumnWidths -State $state -Key Logs }
    })
    $cacheRefresh.Add_Click({
        $state = $script:OSDStageUIState
        if (-not $state) { return }
        $state.Status.Text = 'Refreshing cache inventory...'
        $state.Form.Refresh()
        try {
            Update-OSDStageUIReadOnlyView -State $state
        }
        catch {
            $state.Status.Text = "Refresh failed: $($_.Exception.Message)"
            [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'OSDStage - Cache refresh','OK','Error')
        }
    })
    $cacheHealth.Add_Click({
        $state = $script:OSDStageUIState
        if (-not $state) { return }
        try {
            if (-not $state.Snapshot -or -not $state.Snapshot.CachePath) { throw 'No OSDStage USB cache is currently connected.' }
            $health = Get-OSDStageCacheHealth -CachePath $state.Snapshot.CachePath -Offline:$state.Offline
            $summary = Format-OSDStageUICacheHealth -Health $health
            $state.Status.Text = "Cache health: $(if ($health.Healthy) { 'Healthy' } else { 'Needs attention' })"
            [void][System.Windows.Forms.MessageBox]::Show($summary,'OSDStage - Cache health','OK','Information')
        }
        catch {
            $state.Status.Text = "Cache health check failed: $($_.Exception.Message)"
            [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'OSDStage - Cache health','OK','Error')
        }
    })
    $cacheCheckUpdates.Add_Click({
        $state = $script:OSDStageUIState
        if (-not $state) { return }
        $state.Status.Text = 'Checking for cache updates...'
        $state.Form.UseWaitCursor = $true
        $state.Form.Refresh()
        try { [void](Update-OSDStageUICacheUpdateStatus -State $state) }
        catch {
            $state.Status.Text = "Update check failed: $($_.Exception.Message)"
            [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'OSDStage - Check updates','OK','Error')
        }
        finally { $state.Form.UseWaitCursor = $false }
    })
    $cacheUpdate.Add_Click({
        $state = $script:OSDStageUIState
        if (-not $state) { return }
        $answer = [System.Windows.Forms.MessageBox]::Show(
            'Update the connected cache using the current repository catalog and the existing built-in cache configuration?',
            'OSDStage - Update cache',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $state.Status.Text = 'Updating cache...'
        $state.Form.UseWaitCursor = $true
        $state.Form.Refresh()
        try {
            $result = Invoke-OSDStageUICacheUpdate -State $state
            Update-OSDStageUIReadOnlyView -State $state
            $summary = @(
                "Updated: $(@($result.Updated).Count)"
                "Skipped: $(@($result.Skipped).Count)"
                "Failed: $(@($result.Failed).Count)"
            )
            if ($result.Skipped.Count -gt 0) { $summary += ''; $summary += 'Skipped:'; $summary += @($result.Skipped) }
            if ($result.Failed.Count -gt 0) { $summary += ''; $summary += 'Failed:'; $summary += @($result.Failed) }
            $state.Status.Text = "Cache update complete | $(@($result.Updated).Count) updated | $(@($result.Failed).Count) failed"
            [void][System.Windows.Forms.MessageBox]::Show(
                ($summary -join [Environment]::NewLine),
                'OSDStage - Update cache',
                'OK',
                $(if ($result.Failed.Count -gt 0) { 'Warning' } else { 'Information' })
            )
        }
        catch {
            $state.Status.Text = "Cache update failed: $($_.Exception.Message)"
            [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'OSDStage - Update cache','OK','Error')
        }
        finally {
            $state.Form.UseWaitCursor = $false
        }
    })
    $cacheClear.Add_Click({
        $state = $script:OSDStageUIState
        if (-not $state) { return }
        try {
            if (-not $state.Snapshot -or -not $state.Snapshot.CachePath) { throw 'No OSDStage USB cache is currently connected.' }

            if ($state.CacheList.SelectedItems.Count -gt 0) {
                $entry = $state.CacheList.SelectedItems[0].Tag
                $message = "Remove '$($entry.DisplayName)' ($($entry.Id)) from the connected cache?"
                $answer = [System.Windows.Forms.MessageBox]::Show(
                    $message,'OSDStage - Clear cache','YesNo','Warning'
                )
                if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
                Clear-OSDStageCache -Name ([string]$entry.Id) -Confirm:$false | Out-Null
            }
            else {
                $answer = [System.Windows.Forms.MessageBox]::Show(
                    'No cache item is selected. Clear the entire connected OSDStage cache? Logs are preserved.',
                    'OSDStage - Clear cache',
                    'YesNo',
                    'Warning'
                )
                if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
                Clear-OSDStageCache -All -Confirm:$false | Out-Null
            }

            Update-OSDStageUIReadOnlyView -State $state
            $state.Status.Text = 'Cache clear completed.'
        }
        catch {
            $state.Status.Text = "Cache clear failed: $($_.Exception.Message)"
            [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'OSDStage - Clear cache','OK','Error')
        }
    })

    $refresh.Add_Click({
        $state = $script:OSDStageUIState
        if ($state) { Invoke-OSDStageUIManagerRefresh -State $state }
    })
    $close.Add_Click({ $script:OSDStageUIState.Form.Close() })

    try {
        try {
            Update-OSDStageUIReadOnlyView -State $script:OSDStageUIState
        }
        catch {
            $script:OSDStageUIState.Status.Text = "Load failed: $($_.Exception.Message)"
            Write-Warning "OSDStage UI: $($_.Exception.Message)"
        }
        [void]$form.ShowDialog()
    }
    finally {
        $script:OSDStageUIState = $null
        $form.Dispose()
    }
}
