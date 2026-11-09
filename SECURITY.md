# Security Policy

OSDStage stages software and device configuration before OOBE and executes the resulting deployment during Windows SetupComplete. Because that work can include downloading installers, applying machine-wide configuration and running repository scripts as SYSTEM, security issues are treated as high priority.

## Supported versions

Security fixes are provided for the current supported OSDStage release line.

| Version | Supported |
| --- | --- |
| Current 1.0 release candidate / 1.x release line | Yes |
| Older preview or development releases | No |
| Unreleased commits on `main` | Best effort; not a published support boundary |

When a security fix is released, users should update to the fixed version rather than relying on an older package.

## Reporting a vulnerability

Please do **not** open a public GitHub issue containing exploit details, credentials, private deployment data, or other information that could help reproduce an active vulnerability.

Use GitHub's private vulnerability reporting for this repository when available:

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Include enough information to reproduce and assess the issue.

A useful report includes:

- affected OSDStage version or commit;
- execution environment, such as WinPE, SetupComplete, or a preparation machine;
- exact commands or configuration involved;
- expected and observed behavior;
- security impact;
- reproduction steps or a minimal proof of concept;
- relevant logs with credentials, tenant details, serial numbers, repository tokens and other sensitive data removed.

If private vulnerability reporting is not available, open a minimal public issue stating that a security concern needs a private reporting channel, without publishing technical exploit details.

## What should be reported here

Examples of OSDStage security issues include:

- bypassing repository package SHA-256 validation;
- bypassing a supported installer publisher or trust check;
- executing content different from the content selected or validated during staging;
- command, argument, path or manifest injection that can result in unintended code execution;
- unsafe handling of repository URLs, package metadata or downloaded content;
- privilege-boundary problems caused by OSDStage's SYSTEM execution context;
- exposure of credentials, secrets or sensitive deployment data through logs, reports or generated files;
- unsafe cache replacement, cache poisoning or integrity failures;
- a vulnerability in the standalone runtime copied to the Windows target;
- security-sensitive failures where OSDStage reports a successful validation or deployment despite a failed trust or integrity requirement.

General bugs without a security impact should be reported through the normal issue tracker.

## Security boundaries

### Repository packages

Repository packages are administrator-controlled content. OSDStage verifies package payloads against the SHA-256 values published in the repository manifest, but a trusted repository can intentionally publish executable scripts or apps.

Repository `App` and `Script` packages can execute as **SYSTEM**. Only use repositories and package sources that are under appropriate administrative control. Do not place untrusted or user-writable content in a repository or cache location used for deployment.

### Built-in apps

OSDStage does not redistribute built-in app installers. Supported built-ins acquire content from vendor-controlled sources and use product-specific validation appropriate to that integration.

The exact validation method can differ by product. Depending on the integration, OSDStage may use publisher or Authenticode checks, vendor-provided hashes, Microsoft-native package validation, or other documented controls.

A compromised vendor download service, a vendor signing-key incident, or a vulnerability inside a third-party installer is primarily a vendor security issue. Report it to OSDStage as well when OSDStage's acquisition or validation behavior could materially increase the risk.

### PowerShell Gallery and module installation

Installing OSDStage from PowerShell Gallery establishes trust in the published OSDStage package and the PowerShell package-management path used to retrieve it.

`-SkipPublisherCheck` is a PowerShellGet option. It does **not** disable OSDStage's own installer validation or package integrity checks.

### WinPE and SetupComplete

WinPE and Windows SetupComplete are privileged deployment environments. SetupComplete runs before normal user-facing provisioning and OSDStage processes its deployment in machine context.

Anyone able to modify the staged OSDStage runtime, device manifest, repository content, cache content or deployment media may already have a significant deployment trust position. Deployment media and writable cache locations should therefore be protected accordingly.

## Sensitive information

Do not include the following in public security reports, issues, screenshots or shared Delivery Reports unless they have been sanitized:

- passwords, tokens, secrets or credentials;
- private repository URLs containing credentials or signed query strings;
- internal hostnames or infrastructure details that are not required for the report;
- tenant or customer-specific identifiers;
- device serial numbers or other identifying inventory information;
- user names or user-specific paths;
- proprietary scripts or packages that are not necessary to reproduce the issue.

OSDStage itself does not provide a hosted telemetry or deployment backend. Runtime logs and Delivery Reports are stored locally on the deployed device unless an administrator copies or processes them elsewhere.

## Disclosure and fixes

After a report is received, the goal is to:

1. reproduce and assess the issue;
2. determine the affected versions and security impact;
3. prepare and validate a fix;
4. publish an updated release when required;
5. document any necessary mitigation or upgrade guidance.

Public disclosure should wait until a reasonable fix or mitigation is available, unless immediate disclosure is required to protect users from an actively exploited issue.

## Third-party vulnerabilities

OSDStage integrates with Windows, PowerShell, PowerShell Gallery and third-party app vendors.

Use the appropriate upstream security channel for vulnerabilities that exist entirely in those products. If the issue affects how OSDStage acquires, validates, stages or executes that content, include OSDStage in the report so the integration can be reviewed.
