Describe 'OSDStage deployment profiles' {
    BeforeAll {
        $script:root = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
    }

    It 'validates the standard workplace example' {
        Test-OSDStageDeploymentProfile -Path (Join-Path $script:root 'Examples\DeploymentProfile.StandardWorkplace.json') | Should -BeTrue
    }

    It 'rejects unknown built-in parameters and invalid ValidateSet values' {
        $profile = [pscustomobject]@{
            SchemaVersion = 1
            Name = 'Invalid'
            Packages = @(
                [pscustomobject]@{
                    Source='BuiltIn'; Id='Microsoft365Apps'
                    Parameters=[pscustomobject]@{ Channel='Invented'; UnknownOption='x' }
                }
            )
        }
        $result = Test-OSDStageDeploymentProfile -InputObject $profile -Detailed
        $result.Valid | Should -BeFalse
        ($result.Errors -join "`n") | Should -Match 'Channel'
        ($result.Errors -join "`n") | Should -Match 'UnknownOption'
    }

    It 'rejects duplicate package identities and reserved generator parameters' {
        $profile = [pscustomobject]@{
            SchemaVersion = 1
            Name = 'Duplicate'
            Packages = @(
                [pscustomobject]@{Source='Repository';Id='Tool';Parameters=[pscustomobject]@{WindowsPath='D:\'}},
                [pscustomobject]@{Source='Repository';Id='Tool'}
            )
        }
        $result = Test-OSDStageDeploymentProfile -InputObject $profile -Detailed
        $result.Valid | Should -BeFalse
        ($result.Errors -join "`n") | Should -Match 'WindowsPath'
        ($result.Errors -join "`n") | Should -Match 'duplicates package'
    }

    It 'generates deterministic PowerShell without executing staging commands' {
        $profile = [pscustomobject]@{
            SchemaVersion = 1
            Name = "O'Brien Workplace"
            Packages = @(
                [pscustomobject]@{Source='BuiltIn';Id='MicrosoftTeams';Parameters=[pscustomobject]@{Architecture='x64'}},
                [pscustomobject]@{Source='Repository';Id='CustomTool'}
            )
        }

        # Conversion only inspects exported command metadata and returns text.
        # Do not mock the staging commands here: Pester proxy functions replace
        # their parameter metadata and would make this a test of the mock rather
        # than of the deployment profile generator.
        $scriptText = ConvertTo-OSDStageDeploymentScript -InputObject $profile

        $scriptText | Should -Match 'Add-OSDStageMicrosoftTeams -Architecture ''x64'''
        $scriptText | Should -Match "Add-OSDStage -Name 'CustomTool'"
        $scriptText | Should -Not -Match 'Invoke-Expression'

        # If conversion had executed either staging command, it would require a
        # deployment target/cache and would not reach this assertion successfully.
        $tokens=$null; $errors=$null
        [void][System.Management.Automation.Language.Parser]::ParseInput($scriptText,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
    }

    It 'escapes string values as PowerShell literals' {
        InModuleScope OSDStage {
            (ConvertTo-OSDStagePowerShellLiteral -Value "O'Brien") | Should -Be "'O''Brien'"
            (ConvertTo-OSDStagePowerShellLiteral -Value @('nl-nl','en-us')) | Should -Be "@('nl-nl', 'en-us')"
        }
    }
}
