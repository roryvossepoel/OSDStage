function Read-OSDStageDeploymentProfile {
    [CmdletBinding(DefaultParameterSetName='Path')]
    param(
        [Parameter(Mandatory, ParameterSetName='Path')]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName='InputObject')]
        [psobject]$InputObject
    )

    if ($PSCmdlet.ParameterSetName -eq 'InputObject') {
        return $InputObject
    }

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    try {
        return (Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        throw "Deployment profile '$resolved' is not valid JSON: $($_.Exception.Message)"
    }
}

function Get-OSDStageDeploymentProfileCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Package)

    $source = [string]$Package.Source
    $id = [string]$Package.Id

    if ($source -eq 'Repository') {
        return (Get-Command -Name 'Add-OSDStage' -Module OSDStage -ErrorAction Stop)
    }

    $commandName = "Add-OSDStage$id"
    $command = Get-Command -Name $commandName -Module OSDStage -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Built-in package '$id' does not map to an exported OSDStage staging command."
    }
    $command
}

function ConvertTo-OSDStagePowerShellLiteral {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return '$null' }

    if ($Value -is [bool]) {
        if ($Value) { return '$true' }
        return '$false'
    }

    if ($Value -is [string]) {
        return "'" + $Value.Replace("'","''") + "'"
    }

    if ($Value -is [char]) {
        return "'" + ([string]$Value).Replace("'","''") + "'"
    }

    if ($Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or
        $Value -is [decimal]) {
        return [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture)
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @($Value | ForEach-Object { ConvertTo-OSDStagePowerShellLiteral -Value $_ })
        return '@(' + ($items -join ', ') + ')'
    }

    throw "Unsupported deployment profile value type '$($Value.GetType().FullName)'. Use strings, booleans, numbers or arrays."
}

function Test-OSDStageDeploymentProfileInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Profile)

    $errors = [System.Collections.Generic.List[string]]::new()

    $schemaVersion = $null
    if ($Profile.PSObject.Properties.Name -contains 'SchemaVersion') {
        $schemaVersion = $Profile.SchemaVersion
    }
    if ([string]$schemaVersion -ne '1') {
        $errors.Add('SchemaVersion must be 1.')
    }

    if ([string]::IsNullOrWhiteSpace([string]$Profile.Name)) {
        $errors.Add('Name is required.')
    }

    $packages = @($Profile.Packages)
    if ($packages.Count -eq 0) {
        $errors.Add('Packages must contain at least one package.')
    }

    $seen = @{}
    for ($index = 0; $index -lt $packages.Count; $index++) {
        $package = $packages[$index]
        $prefix = "Packages[$index]"

        $id = [string]$package.Id
        $source = [string]$package.Source
        if ([string]::IsNullOrWhiteSpace($id) -or $id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $id -match '\.\.') {
            $errors.Add("$prefix.Id is invalid.")
            continue
        }
        if ($source -notin @('BuiltIn','Repository')) {
            $errors.Add("$prefix.Source must be BuiltIn or Repository.")
            continue
        }

        $identity = "${source}:$id"
        if ($seen.ContainsKey($identity)) {
            $errors.Add("$prefix duplicates package '$identity'.")
            continue
        }
        $seen[$identity] = $true

        try {
            $command = Get-OSDStageDeploymentProfileCommand -Package $package
        }
        catch {
            $errors.Add("${prefix}: $($_.Exception.Message)")
            continue
        }

        $reserved = @('Name','Id','WindowsPath','WhatIf','Confirm','Verbose','Debug','ErrorAction','WarningAction','InformationAction','ProgressAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable')
        if ($source -eq 'BuiltIn') { $reserved = @($reserved | Where-Object { $_ -notin @('Name','Id') }) }

        if ($package.PSObject.Properties.Name -contains 'Parameters' -and $null -ne $package.Parameters) {
            foreach ($property in @($package.Parameters.PSObject.Properties)) {
                $parameterName = [string]$property.Name
                $value = $property.Value

                if ($parameterName -in $reserved) {
                    $errors.Add("$prefix.Parameters.$parameterName is controlled by the generator and cannot be set in a profile.")
                    continue
                }

                if (-not $command.Parameters.ContainsKey($parameterName)) {
                    $errors.Add("$prefix.Parameters.$parameterName is not a parameter of $($command.Name).")
                    continue
                }

                $metadata = $command.Parameters[$parameterName]
                $validateSet = @($metadata.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | Select-Object -First 1)
                if ($validateSet.Count -gt 0 -and $null -ne $value) {
                    foreach ($candidate in @($value)) {
                        if ([string]$candidate -notin @($validateSet[0].ValidValues)) {
                            $errors.Add("$prefix.Parameters.$parameterName value '$candidate' is not allowed. Valid values: $(@($validateSet[0].ValidValues) -join ', ').")
                        }
                    }
                }

                try {
                    if ($metadata.ParameterType -eq [System.Management.Automation.SwitchParameter]) {
                        if ($value -isnot [bool]) { throw 'Switch values must be true or false.' }
                    }
                    elseif ($null -ne $value) {
                        [void][System.Management.Automation.LanguagePrimitives]::ConvertTo($value, $metadata.ParameterType, [Globalization.CultureInfo]::InvariantCulture)
                    }
                    [void](ConvertTo-OSDStagePowerShellLiteral -Value $value)
                }
                catch {
                    $errors.Add("$prefix.Parameters.$parameterName is invalid: $($_.Exception.Message)")
                }
            }
        }
    }

    [pscustomobject]@{
        PSTypeName = 'OSDStage.DeploymentProfileValidation'
        Valid      = ($errors.Count -eq 0)
        Errors     = @($errors)
        Profile    = $Profile
    }
}
