# How to use Wagonmaster Manifest

Script version 1.2.1. Last updated 2026-11-12. [Download this page as a Word document](/downloads/wagonmaster-manifest-usage.docx){target="_self"}.

## What it does

Wagonmaster Manifest is the script `Export-WagonmasterManifest.ps1`. It reads everything an Azure Migrate project exposes through Azure APIs and writes each dataset twice: a flattened CSV for Excel or Power BI, and a JSON file with the full structure. It is read only and never changes anything in Azure.

| Area | What you get |
| --- | --- |
| Discovery | Sites, vCenters, Hyper-V hosts and clusters, discovered machines, SQL Server instances, databases and availability groups, IIS and Tomcat web servers and apps |
| Software (optional) | Installed software per machine, with `-IncludeSoftwareInventory` |
| Assessments | Azure VM, AVS, SQL and web app assessments, with per machine results |
| Business case | Business cases and their evaluated machines and workloads |
| Migration | Replication and migration items from linked vaults |
| Resource Graph | Every project record in the `MigrateResources` table |

Not included: agentless dependency data. Export it from the portal under Manage Dependencies, then Export dependencies. Azure keeps that data for 30 days, so export it on a regular schedule.

## Before you start

You need PowerShell 7 and Reader access to the project's resource group. Everything else installs itself.

- **PowerShell 7 or later** (`pwsh`). Windows PowerShell 5.1 is refused with a clear error.
- **Modules:** `Az.Accounts`, `Az.Resources`, `Az.ResourceGraph`, and `powershell-yaml` when a config file is used. Missing modules are installed for the current user from the PowerShell Gallery.
- **Access:** the Reader role on the resource group that holds the Azure Migrate project. See [Security and access](./security) for details.
- **Files:** clone or download the [repository](https://github.com/Hybrid-Solutions-Cloud/Wagonmaster). The script and its `config` folder live in `src/manifest`. Keep them together.
- **If Windows blocks the script** because it was downloaded, run `Unblock-File .\Export-WagonmasterManifest.ps1` once.

Status: this script has been reviewed but not yet run against a live project. Run it with `-DryRun` first.

## Quick start

Run the script with no parameters and answer the prompts. No IDs are needed.

1. Open PowerShell 7 and change to the `src/manifest` folder.
2. Run a dry run first:

    ```powershell
    .\Export-WagonmasterManifest.ps1 -DryRun
    ```

3. Choose **Interactive** when asked how to sign in, then sign in through the browser.
4. Pick the subscription and the Azure Migrate project from the numbered lists.
5. Press Enter to accept the default output folder, or type another one.
6. Check the list of resources the dry run prints. Then run the same command without `-DryRun`.
7. Open `_Summary.csv` in the new output folder to see what was exported.

To skip the prompts next time, pass the values:

```powershell
.\Export-WagonmasterManifest.ps1 -AuthMethod Interactive -SubscriptionId <subscription-id> `
    -ResourceGroupName <resource-group> -ProjectName <project-name>
```

## How values are resolved

Each setting is taken from the first place that has a value:

1. A parameter on the command line
2. The config file, `config\wagonmaster-manifest.yml` by default, or the file named with `-ConfigPath`
3. An environment variable
4. A prompt, only when a person is at the keyboard

In pipelines, Azure Automation, scheduled tasks, or with `-NonInteractive`, step 4 is skipped. A missing value stops the run with an error that names the parameter, config key and environment variable to set.

| Parameter | Config key | Environment variable |
| --- | --- | --- |
| `-AuthMethod` | `auth_method` | `WAGONMASTER_AUTH_METHOD` |
| `-TenantId` | `tenant_id` | `AZURE_TENANT_ID` |
| `-SubscriptionId` | `subscription_id` | `AZURE_SUBSCRIPTION_ID` |
| `-ResourceGroupName` | `resource_group_name` | `WAGONMASTER_RESOURCE_GROUP` |
| `-ProjectName` | `project_name` | `WAGONMASTER_PROJECT_NAME` |
| `-OutputPath` | `output_path` | `WAGONMASTER_OUTPUT_PATH` |
| `-ClientId` | `client_id` | `AZURE_CLIENT_ID` |
| `-ClientSecret` | Not allowed | `AZURE_CLIENT_SECRET` |
| `-CertificateThumbprint` | `certificate_thumbprint` | `AZURE_CLIENT_CERTIFICATE_THUMBPRINT` |
| `-ManagedIdentityClientId` | `managed_identity_client_id` | `WAGONMASTER_MI_CLIENT_ID` |

To use a config file, copy `config\wagonmaster-manifest.example.yml` to `config\wagonmaster-manifest.yml` and fill in the values. Keep the real file out of source control.

## Switches

| Switch | What it does |
| --- | --- |
| `-DryRun` | Signs in, finds the project, lists what would be exported, then stops. Writes no files. |
| `-IncludeSoftwareInventory` | Adds installed software for every machine. One call per machine, so it is slow on large estates. |
| `-SkipResourceGraph` | Skips the Resource Graph `MigrateResources` query. |
| `-SkipMigrationStatus` | Skips replication and migration status from linked vaults. |
| `-UseDeviceCode` | Interactive sign in with a device code instead of a browser. |
| `-NonInteractive` | Never prompts. A missing value is an error. |
| `-ConfigPath <file>` | Uses a specific config file. If it does not exist, it is created from the example and the run stops. |

`-AuthMethod` accepts `Interactive`, `ManagedIdentity` or `ServicePrincipal`.

## Unattended runs

Unattended runs never prompt, so supply every value by parameter, config file or environment variable. Identity setup is in [Security and access](./security).

**Managed identity** (Azure VM, Automation account, Arc enabled server):

```powershell
.\Export-WagonmasterManifest.ps1 -AuthMethod ManagedIdentity -ConfigPath .\config\wagonmaster-manifest.yml
```

Add `-ManagedIdentityClientId <client-id>` for a user assigned identity.

**Service principal with a certificate:**

```powershell
.\Export-WagonmasterManifest.ps1 -AuthMethod ServicePrincipal -TenantId <tenant-id> `
    -ClientId <client-id> -CertificateThumbprint <thumbprint> `
    -SubscriptionId <subscription-id> -ResourceGroupName <resource-group> -ProjectName <project-name>
```

**Service principal with a secret:** set `AZURE_CLIENT_SECRET` from your secret store in the same session, then run the same command without `-CertificateThumbprint`. The secret is never read from the config file.

**Pipeline that has already signed in** (Azure PowerShell task with a service connection):

```powershell
.\Export-WagonmasterManifest.ps1 -AuthMethod Interactive -NonInteractive `
    -SubscriptionId <subscription-id> -ResourceGroupName <resource-group> -ProjectName <project-name>
```

This reuses the existing Azure session. If there is none, the run stops with an error.

## Understanding the output

Each run creates a new timestamped folder, so earlier exports are never overwritten.

```text
WagonmasterManifest\
  <project>-<yyyyMMdd-HHmmss>\
    _Summary.csv      one row per dataset: record count and status
    _CallLog.csv      one row per API call
    _Manifest.json    who ran it, when, against what, API versions
    export.log        full run log
    csv\              one flattened CSV per dataset
    json\             one JSON file per dataset, full structure
```

Start with `_Summary.csv`. The Status column means:

| Status | Meaning |
| --- | --- |
| OK | Data was returned |
| NotAvailable | The project does not use that feature, or the API does not offer it |
| Error | The call failed. The Errors column says why. |
| Partial | Some calls for that dataset worked and some failed |

Reading the CSV files:

- Columns that start with an underscore, such as `_Project`, `_Site` and `_Assessment`, say where the row came from. Use them to join files.
- Nested values become dotted column names. Lists of simple values are joined with a semicolon. Lists of objects stay as JSON in one cell.
- Cells longer than 32,000 characters are cut off with a note. The JSON file has the full value.
- Text that starts with `=`, `+`, `-` or `@` gets a leading apostrophe so Excel cannot run it as a formula. The JSON file keeps the raw value.
- Files are UTF-8 with a byte order mark, so Excel opens them correctly.

## Known limits and troubleshooting

A failed dataset never stops the run. Check `_Summary.csv` first, then `export.log`.

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| "Cannot read Azure Migrate project" | Wrong project or resource group name, or no Reader access | Check the names. Confirm the Reader assignment on the resource group. |
| "Missing required value" | An unattended run has no value for that setting | Set the parameter, config key or environment variable the error names. |
| "No existing Azure session to reuse" | Interactive was chosen where no one can sign in | Sign in first, or use ManagedIdentity or ServicePrincipal. |
| Web app assessment or business case shows Error | Those use preview API versions that Microsoft can change | Update the version in the `$ApiVersions` block at the top of the script. |
| SQL or web app datasets are empty | Not discovered, or the appliance lacks credentials | Fix discovery in the Azure Migrate portal, then export again. |
| Assessment numbers look old | Assessments are point in time snapshots | Recalculate the assessment in the portal, then export again. |
| Device code sign in is refused | Conditional Access blocks device code flow | Run without `-UseDeviceCode`. |
| More data than expected | Several projects share one resource group and the fallback collected all of them | Filter on the `_Site` column, or keep one project per resource group. |
| Module install fails | The PowerShell Gallery is blocked | Install the Az modules from your internal repository first. |

Other limits:

- Dependency data is not exported. Use the portal.
- Software inventory makes one call per machine. Expect a long run on estates with thousands of servers.
- The replication job dataset for the newer replication vault type uses an unverified API path. It may show NotAvailable.
- Exports contain server names, IP addresses and software lists. Treat the output folder as confidential. See [Security and access](./security).
