function Test-OSDStageDeploymentProfile {
    <#
    .SYNOPSIS
    Validates an OSDStage deployment profile without staging anything.
    #>
    [CmdletBinding(DefaultParameterSetName='Path')]
    param(
        [Parameter(Mandatory, Position=0, ParameterSetName='Path')]
        [string]$Path,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName='InputObject')]
        [psobject]$InputObject,

        [switch]$Detailed
    )

    process {
        $profileParameters = @{}
        if ($PSCmdlet.ParameterSetName -eq 'Path') { $profileParameters.Path = $Path }
        else { $profileParameters.InputObject = $InputObject }

        $profile = Read-OSDStageDeploymentProfile @profileParameters
        $result = Test-OSDStageDeploymentProfileInternal -Profile $profile

        if ($Detailed) { return $result }
        [bool]$result.Valid
    }
}
