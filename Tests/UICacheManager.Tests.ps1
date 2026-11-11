Describe 'OSDStage simple Cache UI' {
    BeforeAll {
        $script:root = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
        $script:managerSource = Get-Content -LiteralPath (Join-Path $script:root 'Runtime\OSDStageUIManager.ps1') -Raw
        $script:uiSource = Get-Content -LiteralPath (Join-Path $script:root 'Public\Show-OSDStageUI.ps1') -Raw
    }

    It 'shows only apps that actually exist in the cache' {
        $script:managerSource | Should -Match 'foreach \(\$item in @\(\$Snapshot\.CacheEntries\)\)'
        $script:managerSource | Should -Not -Match 'foreach \(\$item in @\(\$Snapshot\.CatalogApps\) \+ @\(\$Snapshot\.CacheEntries\)\)'
    }

    It 'keeps the visible table to App Version and Status' {
        $script:uiSource | Should -Match "catalogList.Columns.Add\('App'"
        $script:uiSource | Should -Match "catalogList.Columns.Add\('Version'"
        $script:uiSource | Should -Match "catalogList.Columns.Add\('Status'"
        $script:uiSource | Should -Not -Match "catalogList.Columns.Add\('Source'"
        $script:uiSource | Should -Not -Match "catalogList.Columns.Add\('Vendor'"
        $script:uiSource | Should -Not -Match 'CheckBoxes = \$true'
    }

    It 'keeps only Refresh Check cache Update and More as primary actions' {
        $script:uiSource | Should -Match "managerRefresh.Text = 'Refresh'"
        $script:uiSource | Should -Match "managerCheck.Text = 'Check cache'"
        $script:uiSource | Should -Match "managerUpdate.Text = 'Update'"
        $script:uiSource | Should -Match "managerMore.Text = 'More\.\.\.'"
        $script:uiSource | Should -Not -Match "managerCacheSelected.Text = 'Cache selected'"
        $script:uiSource | Should -Not -Match "managerUpdateAll.Text = 'Update all available'"
    }

    It 'uses row selection to scope check and update actions' {
        $script:managerSource | Should -Match 'Get-OSDStageUIManagerSelectedKey'
        $script:uiSource | Should -Match 'Get-OSDStageUIManagerSelectedKey -State \$state'
        $script:uiSource | Should -Match "ManagerUpdate.Text=if\(\$selected\)\{'Update selected'\}else\{'Update all'\}"
    }

    It 'uses background jobs for slow cache operations' {
        $script:managerSource | Should -Match '\bStart-Job\b'
        $script:managerSource | Should -Match '\bReceive-Job\b'
        $script:managerSource | Should -Match 'Invoke-OSDStageUIManagerCheckUpdates'
        $script:managerSource | Should -Match 'Invoke-OSDStageUIManagerRefresh'
        $script:managerSource | Should -Match 'Invoke-OSDStageUIManagerRemoveSelected'
    }

    It 'allows the completed progress dialog to close while blocking early closure' {
        $script:managerSource | Should -Match '\$operation=\[pscustomobject\]@\{Completed=\$false\}'
        $script:managerSource | Should -Match '\$operation\.Completed=\$true'
        $script:managerSource | Should -Match '\$close\.Add_Click\(\{ \$form\.Close\(\) \}\)'
        $script:managerSource | Should -Match 'param\(\$sender,\$eventArgs\) if\(-not \$operation\.Completed\)\{\$eventArgs\.Cancel=\$true\}'
    }

    It 'keeps destructive maintenance behind More and separates remove from clear-all' {
        $script:uiSource | Should -Match "ToolStripMenuItem\]::new\('Remove selected\.\.\.'\)"
        $script:uiSource | Should -Match "ToolStripMenuItem\]::new\('Clear entire cache\.\.\.'\)"
        $script:managerSource | Should -Match 'Clear-OSDStageCache -Name'
        $script:managerSource | Should -Match 'Clear-OSDStageCache -All'
    }
}
