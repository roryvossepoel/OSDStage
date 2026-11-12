[CmdletBinding()]
param([Parameter(Mandatory)][string]$RequestPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'OSDStageFinalAction.ps1')
. (Join-Path $PSScriptRoot 'OSDStageDeliveryReport.ps1')
Invoke-OSDStageFinalAction -RequestPath $RequestPath
