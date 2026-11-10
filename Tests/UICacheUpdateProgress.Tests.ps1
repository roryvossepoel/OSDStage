Describe 'OSDStage Inspector cache update progress' {
    BeforeAll {
        $script:root = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
        $script:source = Get-Content -LiteralPath (Join-Path $script:root 'Runtime\OSDStageUICacheUpdate.ps1') -Raw
    }

    It 'updates only entries explicitly marked Update available' {
        $script:source | Should -Match "Status -eq 'Update available'"
        $script:source | Should -Match 'Only items marked Update available will be synchronized'
        $script:source | Should -Not -Match "Sync-OSDStageMicrosoft365Apps"
    }

    It 'keeps the Windows Forms UI responsive with a background job and progress dialog' {
        $script:source | Should -Match '\bStart-Job\b'
        $script:source | Should -Match '\bReceive-Job\b'
        $script:source | Should -Match 'System\.Windows\.Forms\.ProgressBar'
        $script:source | Should -Match 'Elapsed:'
        $script:source | Should -Match 'Checking and updating'
    }

    It 'distinguishes updated, already current and failed results' {
        $script:source | Should -Match "'Updated'"
        $script:source | Should -Match "'Already current'"
        $script:source | Should -Match "'Failed'"
    }

    It 'loads the responsive implementation after the embedded prototype' {
        $moduleSource = Get-Content -LiteralPath (Join-Path $script:root 'OSDStage.psm1') -Raw
        $moduleSource | Should -Match "Runtime\\OSDStageUICacheUpdate\.ps1"
        $moduleSource | Should -Match "Runtime\\OSDStageUICacheUpdateCompatibility\.ps1"
    }
}
