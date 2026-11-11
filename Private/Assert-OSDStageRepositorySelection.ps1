function Assert-OSDStageRepositorySelection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Name)

    foreach($app in $Name){
        if($app -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $app -match '\.\.'){
            throw "Invalid repository app Id '$app'."
        }
        if($app -ieq 'WindowsInboxCleanup'){throw "'WindowsInboxCleanup' is a built-in script. Use Add-OSDStageWindowsInboxCleanup instead."}
        if($app -ieq 'Microsoft365Apps'){throw "'Microsoft365Apps' is a built-in app. Use Add-OSDStageMicrosoft365Apps instead."}
        if($app -ieq 'MicrosoftTeams' -or $app -ieq 'Teams'){throw "'MicrosoftTeams' is a built-in app. Use Add-OSDStageMicrosoftTeams instead."}
        if($app -ieq 'AdobeAcrobatUnified'){throw "'AdobeAcrobatUnified' is a built-in app. Use Add-OSDStageAdobeAcrobatUnified instead."}
        if($app -ieq 'GoogleChromeEnterprise'){throw "'GoogleChromeEnterprise' is a built-in app. Use Add-OSDStageGoogleChromeEnterprise instead."}
        if($app -ieq 'MozillaFirefoxEnterprise'){throw "'MozillaFirefoxEnterprise' is a built-in app. Use Add-OSDStageMozillaFirefoxEnterprise instead."}
        if($app -ieq 'CiscoWebex'){throw "'CiscoWebex' is a built-in app. Use Add-OSDStageCiscoWebex instead."}
        if($app -in @('VisualCRedist','DotNetRuntime')){
            $command = if ($app -eq 'VisualCRedist') { 'Add-OSDStageVisualCRedist' } else { 'Add-OSDStageDotNetRuntime' }
            throw "'$app' is a built-in runtime. Use $command instead."
        }
        if($app -ieq 'VisualStudioCode'){throw "'VisualStudioCode' is a built-in app. Use Add-OSDStageVisualStudioCode instead."}
        if($app -ieq '7Zip'){throw "'7Zip' is a built-in app. Use Add-OSDStage7Zip instead."}
        if($app -ieq 'ZoomWorkplace'){throw "'ZoomWorkplace' is a built-in app. Use Add-OSDStageZoomWorkplace instead."}
    }
}
