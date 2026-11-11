function Get-OSDStageTestWindowsPath {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
        throw 'TEMP is unavailable.'
    }
    # Preserve the existing isolated CLI test target for Remove-OSDStageStaging.
    [System.IO.Path]::GetFullPath((Join-Path $env:TEMP 'OSDStage-GUI-Staging-Test'))
}
