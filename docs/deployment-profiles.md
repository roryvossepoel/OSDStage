# Deployment profiles

Deployment profiles are a declarative description of **deployment intent**. They do not replace the OSDStage CLI and they do not execute anything by themselves.

The initial schema deliberately covers only built-in and repository packages. Device settings such as registry, files, services and other staging actions can be added in a later schema revision without changing the package model.

## Schema v1

A profile contains:

- `SchemaVersion`: currently `1`;
- `Name`: a human-readable profile name;
- `Packages`: ordered built-in or repository packages;
- optional `Parameters` for each package.

Built-in package parameters are validated against the loaded `Add-OSDStage<Id>` command. Repository entries map to `Add-OSDStage -Name <Id>`.

Target-specific values such as `WindowsPath`, common PowerShell parameters and the repository package `Name` argument are controlled by the generator and cannot be injected through the profile.

## Validate a profile

```powershell
Test-OSDStageDeploymentProfile -Path '.\Examples\DeploymentProfile.StandardWorkplace.json'

Test-OSDStageDeploymentProfile -Path '.\Examples\DeploymentProfile.StandardWorkplace.json' -Detailed
```

## Generate PowerShell

```powershell
$script = ConvertTo-OSDStageDeploymentScript -Path '.\Examples\DeploymentProfile.StandardWorkplace.json'
$script
```

The generator returns PowerShell **text only**. It does not call `Invoke-Expression`, stage packages or modify a device. Review the generated code and execute it through the normal OSDStage CLI workflow.

## Future builder and AI flow

```text
Website builder / AI prompt
            |
            v
   Deployment profile
            |
            v
       Validation
            |
            v
Deterministic PowerShell
            |
            v
       OSDStage CLI
```

AI should produce or modify the structured profile, not directly execute generated PowerShell. The same validator and deterministic generator can therefore be used by the website builder, local tooling and AI-assisted workflows.
