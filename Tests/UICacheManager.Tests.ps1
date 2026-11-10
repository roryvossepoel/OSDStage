Describe 'OSDStage Cache manager' {
    BeforeAll {
        $script:root = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
        $script:managerSource = Get-Content -LiteralPath (Join-Path $script:root 'Runtime\OSDStageUIManager.ps1') -Raw
        $script:updateSource = Get-Content -LiteralPath (Join-Path $script:root 'Runtime\OSDStageUICacheUpdate.ps1') -Raw
    }

    It 'groups the visible cache view by app identity rather than cache variant' {
        $script:managerSource | Should -Match 'Get-OSDStageUIManagerAppKey'
        $script:managerSource | Should -Match 'CacheEntries=@\(\$cache\)'
        $script:managerSource | Should -Match 'cached configurations'
        $script:managerSource | Should -Match 'Select an app to view its cached configurations'
    }

    It 'keeps new built-in cache configurations CLI-only' {
        $script:managerSource | Should -Match 'New built-in cache configurations are created with the PowerShell CLI'
        $script:managerSource | Should -Match 'Not cached - use CLI'
        $script:managerSource | Should -Match 'uncached repository apps'
    }

    It 'uses background jobs for update checks health refresh removal and cache preparation' {
        $script:managerSource | Should -Match '\bStart-Job\b'
        $script:managerSource | Should -Match '\bReceive-Job\b'
        $script:managerSource | Should -Match 'Invoke-OSDStageUIManagerCheckUpdates'
        $script:managerSource | Should -Match 'Invoke-OSDStageUIManagerHealthCheck'
        $script:managerSource | Should -Match 'Invoke-OSDStageUIManagerRefresh'
        $script:managerSource | Should -Match 'Invoke-OSDStageUIManagerRemoveSelected'
        $script:managerSource | Should -Match 'Invoke-OSDStageUIManagerClearEntireCache'
    }

    It 'allows the completed progress dialog to close while blocking early closure' {
        $script:managerSource | Should -Match '\$operation=\[pscustomobject\]@\{Completed=\$false\}'
        $script:managerSource | Should -Match '\$operation\.Completed=\$true'
        $script:managerSource | Should -Match '\$close\.Add_Click\(\{ \$form\.Close\(\) \}\)'
        $script:managerSource | Should -Match 'param\(\$sender,\$eventArgs\) if\(-not \$operation\.Completed\)\{\$eventArgs\.Cancel=\$true\}'
    }

    It 'separates selected removal from entire cache clearing' {
        $script:managerSource | Should -Match 'Remove selected'
        $script:managerSource | Should -Match 'Clear the entire connected OSDStage cache'
        $script:managerSource | Should -Match 'Clear-OSDStageCache -Name'
        $script:managerSource | Should -Match 'Clear-OSDStageCache -All'
    }

    It 'checks exact versions through official sources where OSDStage has safe resolvers' {
        $script:updateSource | Should -Match 'versionhistory\.googleapis\.com'
        $script:updateSource | Should -Match 'product-details\.mozilla\.org'
        $script:updateSource | Should -Match 'Get-OSDStageUIOfficeAvailableVersion'
        $script:updateSource | Should -Match 'Get-OSDStagePrerequisiteRelease'
        $script:updateSource | Should -Match 'Get-OSDStage7ZipRelease'
        $script:updateSource | Should -Match 'Get-OSDStageVisualStudioCodeRelease'
    }

    It 'does not silently call an unchecked vendor cache current' {
        $script:updateSource | Should -Match "status = 'Check failed'"
        $script:updateSource | Should -Match 'Get-OSDStageUIRemoteMetadataStatus'
        $script:updateSource | Should -Match 'Remote vendor metadata changed'
    }
}
