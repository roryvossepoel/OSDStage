$script:OSDStageUICacheUpdateAsync = ${function:Invoke-OSDStageUICacheUpdate}

function Invoke-OSDStageUICacheUpdateLegacy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    if (-not $State.Snapshot -or -not $State.Snapshot.CachePath) {
        throw 'No OSDStage USB cache is currently connected.'
    }

    $entries = @($State.Snapshot.CacheEntries)
    $updated = [System.Collections.Generic.List[string]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()

    if (@($entries | Where-Object Source -eq 'Repository').Count -gt 0) {
        try {
            $catalogUri = (Get-OSDStageConfiguration).CatalogUri
            if ($catalogUri) {
                Sync-OSDStageRepository -Confirm:$false | Out-Null
                $updated.Add('Repository')
            }
            else {
                $skipped.Add('Repository: no CatalogUri configured')
            }
        }
        catch {
            $failed.Add("Repository: $($_.Exception.Message)")
        }
    }

    $builtInEntries = @(
        $entries |
            Where-Object Source -eq 'BuiltIn' |
            Sort-Object Id,Architecture,Channel,RuntimeType,CachePath -Unique
    )

    foreach ($entry in $builtInEntries) {
        $commandName = "Sync-OSDStage$($entry.Id)"
        $command = Get-Command -Name $commandName -Module OSDStage -ErrorAction SilentlyContinue
        if (-not $command) {
            $skipped.Add("$($entry.Id): no sync command")
            continue
        }

        $parameters = @{}
        if ($command.Parameters.ContainsKey('Architecture') -and $entry.Architecture) {
            $parameters.Architecture = [string]$entry.Architecture
        }
        if ($command.Parameters.ContainsKey('Channel') -and $entry.Channel) {
            $parameters.Channel = [string]$entry.Channel
        }
        if ($command.Parameters.ContainsKey('RuntimeType') -and $entry.RuntimeType) {
            $parameters.RuntimeType = [string]$entry.RuntimeType
        }

        if ([string]$entry.Id -eq 'Microsoft365Apps') {
            $configurationXml = Join-Path ([string]$entry.CachePath) 'configuration.xml'
            if (-not (Test-Path -LiteralPath $configurationXml -PathType Leaf)) {
                $skipped.Add('Microsoft365Apps: cached configuration.xml not found')
                continue
            }
            $parameters.ConfigurationXml = $configurationXml
        }

        $missingMandatory = @(
            foreach ($parameter in $command.Parameters.Values) {
                if (-not $parameter.Attributes) { continue }
                $mandatory = @($parameter.Attributes | Where-Object {
                    $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
                }).Count -gt 0
                if ($mandatory -and -not $parameters.ContainsKey($parameter.Name)) {
                    $parameter.Name
                }
            }
        )
        if ($missingMandatory.Count -gt 0) {
            $skipped.Add("$($entry.Id): missing $($missingMandatory -join ', ')")
            continue
        }

        try {
            if ($command.Parameters.ContainsKey('Confirm')) { $parameters.Confirm = $false }
            & $commandName @parameters | Out-Null
            $label = [string]$entry.Id
            if ($entry.Architecture) { $label += " ($($entry.Architecture))" }
            $updated.Add($label)
        }
        catch {
            $failed.Add("$($entry.Id): $($_.Exception.Message)")
        }
    }

    [pscustomobject]@{
        Updated = @($updated)
        Current = @()
        Skipped = @($skipped)
        Failed  = @($failed)
    }
}

function Invoke-OSDStageUICacheUpdate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)

    # Pester model tests call the helper without real WinForms controls. Keep
    # that non-UI contract while production Inspector sessions use the
    # responsive, update-available-only implementation.
    if (-not $State.ContainsKey('Form') -or -not $State.Form -or
        -not $State.ContainsKey('Status') -or -not $State.Status) {
        return Invoke-OSDStageUICacheUpdateLegacy -State $State
    }

    & $script:OSDStageUICacheUpdateAsync -State $State
}
