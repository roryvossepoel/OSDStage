Describe 'Launcher repository availability regression #156' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        $engine = (Get-Process -Id $PID).Path
        $fixture = Join-Path $PSScriptRoot 'Fixtures/Invoke-LauncherAvailabilityFixture.ps1'
        $modulePath = Join-Path $root 'OSDStage.psd1'
        $runner = Join-Path $root 'Examples/Stage-OSDStage.ps1'
    }

    It 'runs the real preflight before five built-ins for <Scenario>' -TestCases @(
        @{ Scenario = 'Missing'; ExpectedExit = 1 }
        @{ Scenario = 'MissingExisting'; ExpectedExit = 1 }
        @{ Scenario = 'Online'; ExpectedExit = 0 }
        @{ Scenario = 'Offline'; ExpectedExit = 0 }
        @{ Scenario = 'Corrupt'; ExpectedExit = 1 }
        @{ Scenario = 'SkipCache'; ExpectedExit = 0 }
    ) {
        param($Scenario, $ExpectedExit)
        $caseRoot = Join-Path $TestDrive $Scenario
        $target = Join-Path $caseRoot 'target'
        $cache = Join-Path $caseRoot 'cache'
        $trace = Join-Path $caseRoot 'staging.trace'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $target 'sentinel.txt') -Value 'unchanged Windows target'
        if ($Scenario -eq 'MissingExisting') {
            $setup = Join-Path $target 'Windows/Setup/Scripts'
            $stage = Join-Path $target 'Windows/Temp/OSDStage'
            New-Item -ItemType Directory -Path $setup, $stage -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $setup 'SetupComplete.cmd') -Value 'existing external SetupComplete'
            Set-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Value 'existing deployment sentinel'
        }
        $before = @(Get-ChildItem -LiteralPath $target -File -Recurse | Sort-Object FullName | ForEach-Object {
            '{0}:{1}' -f $_.FullName, (Get-FileHash -LiteralPath $_.FullName).Hash
        })

        $child = [System.Diagnostics.Process]::new()
        $child.StartInfo.FileName = $engine
        $child.StartInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -ModulePath "{1}" -RunnerPath "{2}" -Scenario "{3}" -Target "{4}" -Cache "{5}" -Trace "{6}"' -f $fixture, $modulePath, $runner, $Scenario, $target, $cache, $trace
        $child.StartInfo.UseShellExecute = $false
        $child.StartInfo.CreateNoWindow = $true
        $child.StartInfo.RedirectStandardOutput = $true
        $child.StartInfo.RedirectStandardError = $true
        $started = $false
        try {
            $started = $child.Start()
            if (-not $started) { throw 'Could not start launcher integration test.' }
            $outputTask = $child.StandardOutput.ReadToEndAsync()
            $errorTask = $child.StandardError.ReadToEndAsync()
            if (-not $child.WaitForExit(30000)) { throw 'Launcher integration test exceeded its time limit.' }
            $output = $outputTask.GetAwaiter().GetResult()
            $errors = $errorTask.GetAwaiter().GetResult()
            $child.ExitCode | Should -Be $ExpectedExit -Because $errors

            if ($ExpectedExit -eq 1) {
                Test-Path -LiteralPath $trace | Should -BeFalse
                $after = @(Get-ChildItem -LiteralPath $target -File -Recurse | Sort-Object FullName | ForEach-Object {
                    '{0}:{1}' -f $_.FullName, (Get-FileHash -LiteralPath $_.FullName).Hash
                })
                ($after -join '|') | Should -Be ($before -join '|')
                $errors | Should -Match 'Do not reboot'
                $output | Should -Not -Match 'OSDStage staging passed'
                if ($Scenario -like 'Missing*') {
                    $errors | Should -Match 'MissingFirst'
                    $errors | Should -Match 'NotepadPlusPlus'
                    $errors | Should -Match 'PackageNotFound'
                    Test-Path -LiteralPath $cache | Should -BeFalse
                }
                else { $errors | Should -Match 'SHA-256' }
            }
            else {
                ((Get-Content -LiteralPath $trace) -join ',') |
                    Should -Be 'Office,Teams,Adobe,Chrome,7Zip,Repository,WindowsUpdate,DeploymentCheck'
                $output | Should -Match 'OSDStage staging passed'
                if ($Scenario -eq 'Online') { Test-Path -LiteralPath $cache | Should -BeFalse }
            }
        }
        finally {
            if ($started -and -not $child.HasExited) { $child.Kill() }
            $child.Dispose()
        }
    }
}
