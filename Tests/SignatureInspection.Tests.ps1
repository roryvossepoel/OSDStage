BeforeAll { . (Join-Path $PSScriptRoot 'Helpers/NativePayloadFixtures.ps1') }
Describe 'Built-in Authenticode cache inspection (read-only)' {
    BeforeAll {
        $script:root = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
    }

    It 'checks MSI files without changing them or initiating an installation' {
        InModuleScope OSDStage {
            $dir = Join-Path $TestDrive 'Msi'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            $msi = Join-Path $dir 'vendor-installer.msi'
            Set-Content -LiteralPath $msi -Value 'original mock package' -Encoding ASCII
            Set-OSDStageTestPayloadInfo -Path $msi -Id GoogleChromeEnterprise
            $before = (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash
            Mock Test-OSDStageWinPE { $false }
            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{
                    Status='Valid'; StatusMessage='Signature check succeeded'
                    SignerCertificate=[pscustomobject]@{Subject='CN=Example Publisher'}
                }
            }
            foreach ($id in @('GoogleChromeEnterprise','CiscoWebex','ZoomWorkplace','MozillaFirefoxEnterprise')) {
                $result = Get-OSDStageBuiltInSignature -Id $id -CacheEntryPath $dir
                $result.Status | Should -Be 'Valid'
                $result.Scope | Should -Be 'MSI package'
                $result.File | Should -Be $msi
                $result.Signer | Should -Be 'CN=Example Publisher'
            }
            Should -Invoke Get-AuthenticodeSignature -Exactly 4 -ParameterFilter { $LiteralPath -eq $msi }
            (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash | Should -Be $before
        }
    }

    It 'does not report an unsigned or untrusted MSI as valid' {
        InModuleScope OSDStage {
            $dir = Join-Path $TestDrive 'Untrusted'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'vendor-installer.msi') -Value 'unsigned' -Encoding ASCII
            Set-OSDStageTestPayloadInfo -Path (Join-Path $dir 'vendor-installer.msi') -Id CiscoWebex
            Mock Test-OSDStageWinPE { $false }
            Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='NotSigned';SignerCertificate=$null;StatusMessage='No digital signature'} }
            $found = Get-OSDStageBuiltInSignature -Id CiscoWebex -CacheEntryPath $dir
            $found.Status | Should -Be 'NotSigned'
            $found.Scope | Should -Be 'MSI package'
            $found.Signer | Should -BeNullOrEmpty
        }
    }

    It 'identifies the limited scope of Office and Teams EXE signature checks' {
        InModuleScope OSDStage {
            $dir = Join-Path $TestDrive 'Exe'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'setup.exe') -Value 'setup' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $dir 'teamsbootstrapper.exe') -Value 'bootstrapper' -Encoding ASCII
            Mock Test-OSDStageWinPE { $false }
            Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='Valid';StatusMessage='Valid';SignerCertificate=$null} }
            $office = Get-OSDStageBuiltInSignature -Id Microsoft365Apps -CacheEntryPath $dir
            $teams = Get-OSDStageBuiltInSignature -Id MicrosoftTeams -CacheEntryPath $dir
            $office.Scope | Should -Match 'setup.exe only'
            $teams.Scope | Should -Match 'MSIX not checked'
            $teams.File | Should -Be (Join-Path $dir 'teamsbootstrapper.exe')
        }
    }

    It 'does not incorrectly declare an outer Acrobat ZIP signed' {
        InModuleScope OSDStage {
            Mock Get-AuthenticodeSignature { throw 'Should not inspect ZIP' }
            $r = Get-OSDStageBuiltInSignature -Id AdobeAcrobatUnified -CacheEntryPath $TestDrive
            $r.Status | Should -Be 'Not assessed'
            $r.Scope | Should -Match 'ZIP'
            Should -Invoke Get-AuthenticodeSignature -Exactly 0
        }
    }

    It 'does not attempt Windows trust verification in WinPE' {
        InModuleScope OSDStage {
            $dir = Join-Path $TestDrive 'WinPE'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'vendor-installer.msi') -Value 'package' -Encoding ASCII
            Set-OSDStageTestPayloadInfo -Path (Join-Path $dir 'vendor-installer.msi') -Id MozillaFirefoxEnterprise
            Mock Test-OSDStageWinPE { $true }
            Mock Get-AuthenticodeSignature { throw 'Do not invoke in WinPE' }
            $r = Get-OSDStageBuiltInSignature -Id MozillaFirefoxEnterprise -CacheEntryPath $dir
            $r.Status | Should -Be 'Unavailable in WinPE'
            Should -Invoke Get-AuthenticodeSignature -Exactly 0
        }
    }

    It 'returns a separate signature result from Get-OSDStageCache without altering Valid or cache files' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'USB\OSDStage'
            $root = Join-Path $cache 'BuiltIn\CiscoWebex\x64'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $msi = Join-Path $root 'vendor-installer.msi'
            $metadata = Join-Path $root 'CacheInfo.json'
            Set-Content -LiteralPath $msi -Value 'existing installer' -Encoding ASCII
            '{"Id":"CiscoWebex","Version":"46.9.0.35800","Architecture":"x64"}' |
                Set-Content -LiteralPath $metadata -Encoding UTF8
            Set-OSDStageTestPayloadInfo -Path $msi -Id CiscoWebex -Metadata @{Version='46.9.0.35800'}
            $before = (Get-FileHash -LiteralPath $metadata -Algorithm SHA256).Hash
            $script:SignatureTestCacheRoot = $cache
            Mock Get-OSDStageCachePath { $script:SignatureTestCacheRoot }
            Mock Get-OSDStageBuiltInSignature {
                [pscustomobject]@{
                    Status='Valid';Scope='MSI package';File=$msi
                    Signer='CN=Vendor';Detail='Trusted'
                }
            }
            $default = @(Get-OSDStageCache)
            $default[0].Valid | Should -BeTrue
            $default[0].SignatureStatus | Should -Be 'Not checked'
            Should -Invoke Get-OSDStageBuiltInSignature -Exactly 0

            $checked = @(Get-OSDStageCache -VerifySignatures)
            $checked[0].Valid | Should -BeTrue
            $checked[0].SignatureStatus | Should -Be 'Valid'
            $checked[0].SignatureScope | Should -Be 'MSI package'
            $checked[0].SignatureSigner | Should -Be 'CN=Vendor'
            Should -Invoke Get-OSDStageBuiltInSignature -Exactly 1
            (Get-FileHash -LiteralPath $metadata -Algorithm SHA256).Hash | Should -Be $before
        }
    }






}
