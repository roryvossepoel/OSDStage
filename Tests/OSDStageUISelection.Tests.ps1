Describe 'OSDStage experimental selection preview model' {
    BeforeAll {
        $script:root = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
    }

    It 'keeps the preview in memory and distinguishes equal IDs from different sources' {
        InModuleScope OSDStage {
            $draft = @{ Entries=@{}; Order=[System.Collections.Generic.List[string]]::new() }
            $builtIn = [pscustomobject]@{ Id='MicrosoftTeams'; Source='BuiltIn'; DisplayName='Microsoft Teams' }
            $repository = [pscustomobject]@{ Id='MicrosoftTeams'; Source='Repository'; DisplayName='Microsoft Teams'; PackageType='Script' }

            Set-OSDStageUISelection -Draft $draft -App $builtIn -Selected $true
            Set-OSDStageUISelection -Draft $draft -App $repository -Selected $true

            $draft.Order | Should -Be @('BuiltIn:MicrosoftTeams','Repository:MicrosoftTeams')
            $draft.Entries.Keys.Count | Should -Be 2
        }
    }

    It 'preserves built-in preview settings when an item is unchecked and selected again' {
        InModuleScope OSDStage {
            $draft = @{ Entries=@{}; Order=[System.Collections.Generic.List[string]]::new() }
            $app = [pscustomobject]@{ Id='MicrosoftTeams'; Source='BuiltIn'; DisplayName='Microsoft Teams' }

            Set-OSDStageUISelection -Draft $draft -App $app -Selected $true
            $draft.Entries['BuiltIn:MicrosoftTeams'].Configuration.Architecture = 'arm64'
            Set-OSDStageUISelection -Draft $draft -App $app -Selected $false
            Set-OSDStageUISelection -Draft $draft -App $app -Selected $true

            $draft.Entries['BuiltIn:MicrosoftTeams'].Configuration.Architecture | Should -Be 'arm64'
        }
    }

    It 'derives Office defaults from the loaded OSDStage cmdlet without staging anything' {
        InModuleScope OSDStage {
            Mock Add-OSDStageMicrosoft365Apps { throw 'Unexpected staging' }
            Mock Set-OSDStageConfiguration { throw 'Unexpected session mutation' }

            $values = New-OSDStageUIConfiguration -Id Microsoft365Apps
            $values.Channel | Should -Not -BeNullOrEmpty
            $values.Architecture | Should -Not -BeNullOrEmpty

            Should -Invoke Add-OSDStageMicrosoft365Apps -Exactly 0
            Should -Invoke Set-OSDStageConfiguration -Exactly 0
        }
    }

    It 'validates edited values through the existing cmdlet metadata' {
        InModuleScope OSDStage {
            $office = New-OSDStageUIConfiguration -Id Microsoft365Apps
            $office.Channel = 'invented'
            { ConvertTo-OSDStageUIConfiguration -Id Microsoft365Apps -Values $office } | Should -Throw '*Channel*'
        }
    }

    It 'keeps the public Viewer free of staging actions' {
        $uiSource = Get-Content -LiteralPath (Join-Path $script:root 'Public\Show-OSDStageUI.ps1') -Raw
        $uiSource | Should -Match 'EXPERIMENTAL'
        $uiSource | Should -Match 'staging is not implemented yet'
        $uiSource | Should -Not -Match '(?i)\bInvoke-OSDStageUIStage\b'
        $uiSource | Should -Not -Match '(?i)\bAdd-OSDStage(?:Microsoft|Adobe|Cisco|Mozilla|Google|Zoom|Visual|DotNet|7Zip)'
        $uiSource | Should -Not -Match '(?i)\bSet-OSDStageConfiguration\b'
        $uiSource | Should -Not -Match '(?i)\bRemove-OSDStageStaging\b'
    }
}
