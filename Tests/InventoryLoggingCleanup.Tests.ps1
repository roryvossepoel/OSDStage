Describe 'Inventory and client logging analyzer cleanup' {
    BeforeAll {
        $script:moduleRoot = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:moduleRoot 'OSDStage.psd1') -Force
    }

    It 'writes byte-identical CMTrace records using Event and EventName' {
        InModuleScope OSDStage {
            Mock Get-Date { [datetime]::SpecifyKind([datetime]'2026-01-02T03:04:05', [DateTimeKind]::Utc) }
            $legacyPath = Join-Path $TestDrive 'legacy.log'
            $namedPath = Join-Path $TestDrive 'named.log'
            $parameters = @{
                Component = 'Cache'
                Level = 'Warning'
                Message = 'Cache inspection'
                Data = @{ Z = @(1,2); A = 'first' }
            }
            @(Write-OSDStageLog -LogPath $legacyPath -Event 'CacheInspected' @parameters).Count | Should -Be 0
            @(Write-OSDStageLog -LogPath $namedPath -EventName 'CacheInspected' @parameters).Count | Should -Be 0
            (Get-FileHash -LiteralPath $legacyPath).Hash | Should -Be (Get-FileHash -LiteralPath $namedPath).Hash
            $line = Get-Content -LiteralPath $legacyPath
            $line | Should -Match ([regex]::Escape('[CacheInspected] Cache inspection | A=first; Z=1,2'))
            $line | Should -Match 'component="Cache"'
            $line | Should -Match 'type="2"'
        }
    }

    It 'accepts legacy Event splatting and preserves single-line escaping' {
        InModuleScope OSDStage {
            $path = Join-Path $TestDrive 'splat.log'
            $parameters = @{
                LogPath = $path; Component = 'Client'; Event = 'Inspect'
                Message = "first`nsecond ]LOG]!> text"
            }
            Write-OSDStageLog @parameters
            $lines = @(Get-Content -LiteralPath $path)
            $lines.Count | Should -Be 1
            $lines[0] | Should -Match ([regex]::Escape('[Inspect] first second ]LOG]! > text'))
        }
    }

    It 'keeps event-only records in CMTrace format' {
        InModuleScope OSDStage {
            $path = Join-Path $TestDrive 'event-only.log'
            Write-OSDStageLog -LogPath $path -Component 'Client' -Event 'Ready'
            (Get-Content -LiteralPath $path) | Should -Match ([regex]::Escape('<![LOG[[Ready]]LOG]!>'))
        }
    }





    It 'retains one trimmed MSI version and reports a failed view close only on the verbose stream' {
        InModuleScope OSDStage {
            $file = Join-Path $TestDrive 'cleanup.msi'
            Set-Content -LiteralPath $file -Value 'sentinel, not an installer' -Encoding ASCII
            $before = (Get-FileHash -LiteralPath $file).Hash
            Mock Test-OSDStageWinPE { $false }
            Mock New-Object {
                $record = [pscustomobject]@{}
                $record | Add-Member ScriptMethod StringData { param([int]$column) ' 123.4.5 ' }
                $view = [pscustomobject]@{Record=$record}
                $view | Add-Member ScriptMethod Execute { '' }
                $view | Add-Member ScriptMethod Fetch { $this.Record }
                $view | Add-Member ScriptMethod Close { throw 'simulated close failure' }
                $database = [pscustomobject]@{View=$view}
                $database | Add-Member ScriptMethod OpenView { param([string]$sql) $this.View }
                $installer = [pscustomobject]@{Database=$database}
                $installer | Add-Member ScriptMethod OpenDatabase {
                    param([string]$path,[int]$mode)
                    if ($mode -ne 0) { throw 'Only read-only database access is permitted.' }
                    $this.Database
                }
                $installer
            } -ParameterFilter { $ComObject -eq 'WindowsInstaller.Installer' }

            $normal = @(Get-OSDStageMsiProductVersion -Path $file -Verbose:$false)
            $normal.Count | Should -Be 1
            $normal[0] | Should -Be '123.4.5'
            $withDiagnostics = @(Get-OSDStageMsiProductVersion -Path $file -Verbose 4>&1)
            @($withDiagnostics | Where-Object { $_ -is [string] }).Count | Should -Be 1
            @($withDiagnostics | Where-Object {
                $_ -is [System.Management.Automation.VerboseRecord] -and
                $_.Message -like '*MSI view cleanup failed*simulated close failure*'
            }).Count | Should -Be 1
            (Get-FileHash -LiteralPath $file).Hash | Should -Be $before
        }
    }

    It 'does not regress the specific analyzer rules addressed in the reviewed files' {
        $rules = @(
            'PSAvoidAssignmentToAutomaticVariable',
            'PSAvoidUsingEmptyCatchBlock',
            'PSPossibleIncorrectComparisonWithNull'
        )
        foreach ($relative in @(
            'Private/Write-OSDStageLog.ps1',
            'Private/Get-OSDStageCachedPackageVersion.ps1',
            'Public/Test-OSDStageRepository.ps1'
        )) {
            $findings = @(Invoke-ScriptAnalyzer -Path (Join-Path $script:moduleRoot $relative) -IncludeRule $rules)
            $findings.Count | Should -Be 0 -Because "$relative must retain the reviewed cleanup"
        }
    }
}
