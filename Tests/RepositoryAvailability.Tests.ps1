BeforeDiscovery {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDStage.psd1') -Force
}

Describe 'Repository selection availability before staging' {
    InModuleScope OSDStage {
        BeforeEach {
            $script:cache = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            $script:catalog = [pscustomobject]@{
                SchemaVersion = 2
                Packages = @([pscustomobject]@{
                    Id = 'Fixture'; Aliases = @('OldFixture')
                    Architectures = @([pscustomobject]@{Architecture='x64'; Manifest='Fixture/manifest.json'})
                })
            }
            $script:package = [pscustomobject]@{
                SchemaVersion=2; Id='Fixture'; Version='1.0'; Architecture='x64'
                Payload=[pscustomobject]@{FileName='Package.zip'; Sha256=('a' * 64)}
            }
            Mock Get-OSDStageConfiguration { [pscustomobject]@{CatalogUri='https://example.invalid/catalog.json'; EnableRepository=$true} }
            Mock Get-OSDStageHostArchitecture { 'x64' }
            Mock Get-OSDStageCachePath { $script:cache }
            Mock Get-OSDStageManifest {
                if ($Uri) {
                    if ($Uri.AbsoluteUri.EndsWith('/catalog.json')) { return $script:catalog }
                    return $script:package
                }
                Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json
            }
            Mock Invoke-WebRequest { throw 'Unexpected archive/network request.' }
            Mock Sync-OSDStageCache { throw 'Preflight must not synchronize.' }
            Mock Add-OSDStageGoogleChromeEnterprise { throw 'Unexpected staging.' }
            function New-AvailabilityCache {
                param([string]$Architecture='x64')
                $folder = Join-Path $script:cache 'Packages/Fixture'
                New-Item -ItemType Directory -Path $folder -Force | Out-Null
                $archive = Join-Path $folder 'Package.zip'
                Set-Content -LiteralPath $archive -Value 'archive sentinel'
                [pscustomobject]@{Packages=@([pscustomobject]@{
                    Id='Fixture';Aliases=@('OldFixture');Architecture=$Architecture;Version='1.0'
                    Payload=@{Sha256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash}
                })} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $script:cache 'CacheCatalog.json')
            }
        }

        It 'accepts online metadata and aliases without requiring or creating a cache' {
            $result = Test-OSDStageRepositoryAvailability -Name OldFixture -ThrowOnFailure
            $result.Valid | Should -BeTrue
            $result.Packages[0].Id | Should -Be Fixture
            $result.Packages[0].Source | Should -Be Catalog
            $result.UsesCacheFallback | Should -BeFalse
            Test-Path $script:cache | Should -BeFalse
            Should -Invoke Get-OSDStageManifest -Exactly 1 -ParameterFilter { $Uri.AbsoluteUri -eq 'https://example.invalid/catalog.json' }
            Should -Invoke Invoke-WebRequest -Exactly 0
            Should -Invoke Sync-OSDStageCache -Exactly 0
        }

        It 'reports every missing item and stops before an earlier built-in Add call' {
            $target = Join-Path $TestDrive 'unchanged-target'
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            $marker = Join-Path $target 'sentinel.txt'
            Set-Content $marker 'unchanged'
            $before = (Get-FileHash $marker).Hash
            {
                Test-OSDStageRepositoryAvailability -Name Fixture,MissingFirst,NotepadPlusPlus -WindowsPath $target -ThrowOnFailure
                Add-OSDStageGoogleChromeEnterprise -WindowsPath $target
            } | Should -Throw '*MissingFirst*NotepadPlusPlus*'
            $result = Test-OSDStageRepositoryAvailability -Name MissingFirst,NotepadPlusPlus
            @($result.Packages | Where-Object CatalogStatus -eq PackageNotFound).Count | Should -Be 2
            (Get-FileHash $marker).Hash | Should -Be $before
            @(Get-ChildItem $target -Recurse).Count | Should -Be 1
            Test-Path $script:cache | Should -BeFalse
            Should -Invoke Add-OSDStageGoogleChromeEnterprise -Exactly 0
            Should -Invoke Sync-OSDStageCache -Exactly 0
        }

        It 'distinguishes unreachable catalog from a missing ID and permits verified offline fallback' {
            New-AvailabilityCache
            $before = @(Get-ChildItem $script:cache -File -Recurse | Get-FileHash | Select-Object -ExpandProperty Hash)
            Mock Get-OSDStageManifest { throw 'connection unavailable' } -ParameterFilter { $Uri }
            $result = Test-OSDStageRepositoryAvailability -Name OldFixture -ThrowOnFailure
            $result.CatalogStatus | Should -Be CatalogUnavailable
            $result.Packages[0].Source | Should -Be Cache
            $result.Packages[0].Id | Should -Be Fixture
            $result.Packages[0].CatalogDetail | Should -Match 'connection unavailable'
            @(Get-ChildItem $script:cache -File -Recurse | Get-FileHash | Select-Object -ExpandProperty Hash) | Should -Be $before
            Should -Invoke Sync-OSDStageCache -Exactly 0
        }

        It 'accepts a cache-only package absent from the reachable catalog' {
            New-AvailabilityCache
            $script:catalog.Packages = @()
            $result = Test-OSDStageRepositoryAvailability -Name Fixture -ThrowOnFailure
            $result.Valid | Should -BeTrue
            $result.Packages[0].CatalogStatus | Should -Be PackageNotFound
            $result.Packages[0].Source | Should -Be Cache
        }

        It 'rejects corrupted cached archives' {
            New-AvailabilityCache
            Set-Content (Join-Path $script:cache 'Packages/Fixture/Package.zip') 'tampered'
            $result = Test-OSDStageRepositoryAvailability -Name Fixture -SkipCacheRefresh
            $result.Valid | Should -BeFalse
            $result.Packages[0].CacheDetail | Should -Match 'SHA-256'
            Should -Invoke Get-OSDStageManifest -Exactly 0 -ParameterFilter { $Uri }
        }

        It 'rejects incompatible cached architecture and accepts neutral architecture' {
            New-AvailabilityCache -Architecture arm64
            (Test-OSDStageRepositoryAvailability -Name Fixture -SkipCacheRefresh).Valid | Should -BeFalse
            New-AvailabilityCache -Architecture any
            (Test-OSDStageRepositoryAvailability -Name Fixture -SkipCacheRefresh).Valid | Should -BeTrue
        }

        It 'rejects an incompatible online variant without valid cache' {
            $script:catalog.Packages[0].Architectures[0].Architecture = 'arm64'
            $script:package.Architecture = 'arm64'
            $result = Test-OSDStageRepositoryAvailability -Name Fixture
            $result.Valid | Should -BeFalse
            $result.Packages[0].CatalogDetail | Should -Match 'No compatible package variant'
        }

        It 'rejects ambiguous aliases using the shared catalog identity rules' {
            $script:catalog.Packages += [pscustomobject]@{
                Id='Other';Aliases=@('OldFixture')
                Architectures=@([pscustomobject]@{Architecture='x64';Manifest='Other/manifest.json'})
            }
            $result = Test-OSDStageRepositoryAvailability -Name OldFixture
            $result.Valid | Should -BeFalse
            $result.Packages[0].CatalogDetail | Should -Match 'assigned to both'
        }

        It 'requires a complete cache fallback for a mixed batch' {
            New-AvailabilityCache
            $script:catalog.Packages[0].Id = 'OnlineOnly'
            $script:catalog.Packages[0].Aliases = @()
            $script:package.Id = 'OnlineOnly'
            $result = Test-OSDStageRepositoryAvailability -Name OnlineOnly,Fixture
            $result.Valid | Should -BeFalse
            ($result.Packages | Where-Object Name -eq Fixture).Available | Should -BeTrue
            ($result.Packages | Where-Object Name -eq OnlineOnly).Available | Should -BeFalse
        }

        It 'inspects an existing target-local cache when no USB volume is available' {
            $target = Join-Path $TestDrive 'local-target'
            $script:cache = Join-Path $target 'Windows/Temp/OSDStage/RepositoryCache'
            New-AvailabilityCache
            Mock Get-OSDStageCachePath { throw 'No USB volume' }
            $result = Test-OSDStageRepositoryAvailability -Name Fixture -WindowsPath $target -SkipCacheRefresh -ThrowOnFailure
            $result.Valid | Should -BeTrue
            $result.Packages[0].Source | Should -Be Cache
        }

        It 'rejects built-in IDs before reading the repository, matching Add-OSDStage' {
            { Test-OSDStageRepositoryAvailability -Name Microsoft365Apps } | Should -Throw '*Use Add-OSDStageMicrosoft365Apps*'
            Should -Invoke Get-OSDStageManifest -Exactly 0
        }

        It 'rejects unsafe IDs before reading sources' {
            { Test-OSDStageRepositoryAvailability -Name '../escape' } | Should -Throw '*Invalid repository app Id*'
            Should -Invoke Get-OSDStageManifest -Exactly 0
        }
    }
}
