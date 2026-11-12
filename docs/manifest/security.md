# Security and access

Script version 1.2.1. Last updated 2026-11-12. [Download this page as a Word document](/downloads/wagonmaster-manifest-security.docx){target="_self"}.

## Summary

Every identity that runs `Export-WagonmasterManifest.ps1` needs one thing: the Azure RBAC **Reader** role on the resource group that holds the Azure Migrate project. It needs no Microsoft Entra directory role, no Microsoft Graph permission and no admin consent. This is the same for an interactive user, a managed identity and a service principal.

The script only makes read (GET) calls to Azure Resource Manager and Azure Resource Graph. It does not touch any data plane: no Key Vault secrets, no storage blobs, no appliance credentials.

| Resource provider | What is read |
| --- | --- |
| `Microsoft.Migrate` | The project, its solutions, assessment projects, groups, assessments, business cases |
| `Microsoft.OffAzure` | Discovery sites, machines, SQL and web app inventory, software inventory |
| `Microsoft.RecoveryServices`, `Microsoft.DataReplication` | Replication and migration status in linked vaults |
| `Microsoft.Resources` | Subscription list, resource group contents (project picker and fallback) |
| `Microsoft.ResourceGraph` | The `MigrateResources` table, filtered to the resource group |

## Required Azure RBAC

Assign Reader at the resource group that holds the Azure Migrate project, never at the subscription. If a linked Recovery Services vault lives in another resource group, add Reader there too, or run with `-SkipMigrationStatus`.

| Role option | Use it when | Notes |
| --- | --- | --- |
| **Reader** (built in) | Default. Recommended. | Read only on everything in the resource group. Cannot read secrets, keys or blob contents. |
| **Custom role** (below) | Policy forbids broad Reader | Limits reads to Azure Migrate resource types. Not yet tested against a live project. |
| Azure Migrate Owner, Decide and Plan Expert, Execute Expert | Not for this script | These [built in roles](https://learn.microsoft.com/azure/migrate/prepare-azure-accounts?view=migrate) allow discovery, assessment creation or migration. That is more than an export needs. |

Optional custom role, scoped to the one resource group:

```json
{
  "Name": "Wagonmaster Manifest Reader",
  "Description": "Read only access to Azure Migrate project data for export.",
  "Actions": [
    "Microsoft.Migrate/migrateProjects/read",
    "Microsoft.Migrate/migrateProjects/solutions/read",
    "Microsoft.Migrate/assessmentProjects/read",
    "Microsoft.Migrate/assessmentProjects/*/read",
    "Microsoft.OffAzure/*/read",
    "Microsoft.RecoveryServices/vaults/read",
    "Microsoft.RecoveryServices/vaults/*/read",
    "Microsoft.DataReplication/replicationVaults/read",
    "Microsoft.DataReplication/replicationVaults/*/read",
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/subscriptions/resourceGroups/resources/read"
  ],
  "NotActions": [],
  "AssignableScopes": [
    "/subscriptions/<subscription-id>/resourceGroups/<azure-migrate-resource-group>"
  ]
}
```

```powershell
New-AzRoleDefinition -InputFile .\wagonmaster-manifest-reader.json
```

Validate a custom role with `-DryRun` and then one full run. Any dataset that the role blocks shows as Error in `_Summary.csv`. With the custom role, pass `-ResourceGroupName` and `-ProjectName` explicitly, because the project picker may not list anything.

## Access by sign in method

The Azure role is identical for all three methods. What differs is the credential and who can use it.

| | Interactive | Managed identity | Service principal |
| --- | --- | --- | --- |
| Who signs in | A named person | An Azure resource (VM, Automation account, Arc enabled server) | An app registration |
| Azure RBAC | Reader on the project resource group | Reader on the project resource group | Reader on the project resource group |
| Entra directory role | None | None | None |
| Graph or API permissions, admin consent | None | None | None. Leave API permissions empty. |
| Credential | The person's own sign in, with MFA | None to manage. Azure issues tokens to the host. | Certificate (preferred) or client secret |
| Conditional Access | Applies in full | Not applicable | Only with workload identity policies |
| Can it prompt | Yes | No | Only if a person runs it at a console |
| Best for | A PM or engineer running it on demand | Scheduled runs on Azure hosted or Arc enabled compute | Pipelines and hosts outside Azure |

Notes per method:

- **Interactive.** Sign in goes through Microsoft's own Azure PowerShell application, so no app registration is needed. Guest accounts work if they hold the Reader assignment. If Reader is granted through Privileged Identity Management, activate it before the run. `-UseDeviceCode` can be blocked by Conditional Access; use the browser sign in instead.
- **Managed identity.** Works only where the script runs on a resource that has the identity. Anyone who can run code on that host can use the identity, so control who can log on to the VM or edit the runbook.
- **Service principal.** Use only when a managed identity is not possible. The certificate or secret is the whole security boundary, so protect and rotate it.
- **Pipelines with a service connection.** When an Azure PowerShell task has already signed in, run with `-AuthMethod Interactive -NonInteractive`. The script reuses that session and never prompts. The service connection identity needs the same Reader assignment.

## Create the service principal

Create it with a certificate, no secret, no API permissions and one Reader assignment on one resource group. Run these steps in PowerShell 7 on the Windows machine that will run the export, signed in as the account that will run it. The commands have not been run in a test environment yet, so test them once in a non production subscription.

```powershell
$subscriptionId    = '<subscription-id>'
$resourceGroupName = '<azure-migrate-resource-group>'
$displayName       = 'sp-wagonmaster-manifest-prd'
$scope             = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName"

Connect-AzAccount -Subscription $subscriptionId

# 1. Certificate. The private key is created on this machine and cannot be exported.
$certificate = New-SelfSignedCertificate -Subject "CN=$displayName" `
    -CertStoreLocation 'Cert:\CurrentUser\My' -KeyExportPolicy NonExportable `
    -KeySpec Signature -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddMonths(6)
$certValue = [Convert]::ToBase64String($certificate.GetRawCertData())

# 2. App registration and service principal. No role and no secret are created.
$servicePrincipal = New-AzADServicePrincipal -DisplayName $displayName -CertValue $certValue `
    -StartDate $certificate.NotBefore -EndDate $certificate.NotAfter

# 3. Reader on the one resource group. Retry while the new identity replicates.
foreach ($attempt in 1..6) {
    try {
        New-AzRoleAssignment -ObjectId $servicePrincipal.Id -RoleDefinitionName 'Reader' `
            -Scope $scope -ErrorAction Stop | Out-Null
        break
    } catch {
        if ($attempt -eq 6) { throw }
        Start-Sleep -Seconds 10
    }
}

# 4. Values the export script needs. None of these is a secret.
[pscustomobject]@{
    TenantId              = (Get-AzContext).Tenant.Id
    ClientId              = $servicePrincipal.AppId
    CertificateThumbprint = $certificate.Thumbprint
}
```

Then run the export:

```powershell
.\Export-WagonmasterManifest.ps1 -AuthMethod ServicePrincipal -TenantId <tenant-id> `
    -ClientId <client-id> -CertificateThumbprint <thumbprint> `
    -SubscriptionId <subscription-id> -ResourceGroupName <resource-group> -ProjectName <project-name>
```

Rules for this identity:

- Per [Microsoft's guidance](https://learn.microsoft.com/powershell/azure/create-azure-service-principal-azureps), a certificate based service principal gets no default role. Confirm that Reader on the resource group is its only assignment.
- Do not add API permissions, redirect URIs or extra owners. Name two owners so it is not orphaned.
- One certificate per machine. For a second machine, create a certificate there and add it with `New-AzADSpCredential -ObjectId $servicePrincipal.Id -CertValue <value>`.
- If `New-SelfSignedCertificate` fails in PowerShell 7, run step 1 in Windows PowerShell 5.1, or use a certificate from your internal CA.
- If a client secret is unavoidable, create it with `New-AzADSpCredential -ObjectId $servicePrincipal.Id -EndDate (Get-Date).AddDays(90)`, store the value in Key Vault, and pass it only through `AZURE_CLIENT_SECRET` at run time.
- For Azure DevOps or GitHub pipelines, prefer a service connection with workload identity federation, which has no secret at all.

## Create the managed identity

Prefer a managed identity whenever the script runs on Azure compute or an Arc enabled server, because there is no credential to store or rotate. Use a user assigned identity when more than one host runs the export or the host may be rebuilt. Use a system assigned identity for a single dedicated host.

**User assigned** (requires the `Az.ManagedServiceIdentity` module):

```powershell
$scope = '/subscriptions/<subscription-id>/resourceGroups/<azure-migrate-resource-group>'

$identity = New-AzUserAssignedIdentity -ResourceGroupName '<identity-resource-group>' `
    -Name 'id-wagonmaster-manifest-prd-eus-01' -Location '<region>' `
    -Tag @{ Owner = '<owner-email>'; Project = 'wagonmaster'; Environment = 'prd'
            CostCenter = '<cost-center>'; ManagedBy = 'manual' }

# Reader on the one resource group. Retry for a minute if the identity is not found yet.
New-AzRoleAssignment -ObjectId $identity.PrincipalId -RoleDefinitionName 'Reader' -Scope $scope

# Attach to the host that runs the script. Pick one.
$vm = Get-AzVM -ResourceGroupName '<vm-resource-group>' -Name '<vm-name>'
Update-AzVM -ResourceGroupName '<vm-resource-group>' -VM $vm -IdentityType UserAssigned -IdentityId $identity.Id

Set-AzAutomationAccount -ResourceGroupName '<automation-resource-group>' -Name '<automation-account>' `
    -AssignUserIdentity $identity.Id
```

If the VM already has a system assigned identity, use `-IdentityType SystemAssignedUserAssigned` so it is not removed. Run the export with the identity's client ID:

```powershell
.\Export-WagonmasterManifest.ps1 -AuthMethod ManagedIdentity -ManagedIdentityClientId <client-id> `
    -SubscriptionId <subscription-id> -ResourceGroupName <resource-group> -ProjectName <project-name>
```

**System assigned:**

```powershell
$vm = Get-AzVM -ResourceGroupName '<vm-resource-group>' -Name '<vm-name>'
Update-AzVM -ResourceGroupName '<vm-resource-group>' -VM $vm -IdentityType SystemAssigned
$principalId = (Get-AzVM -ResourceGroupName '<vm-resource-group>' -Name '<vm-name>').Identity.PrincipalId
New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName 'Reader' -Scope $scope
```

Run the export with `-AuthMethod ManagedIdentity` and no client ID. A system assigned identity is deleted with its host, which also removes the access.

The identity name and tags are examples. Use your own naming and tagging standards.

## Rights needed for setup

The person who creates the identity needs more access than the identity itself. Grant these for the setup only.

| Setup task | Minimum right |
| --- | --- |
| Assign Reader to a user, managed identity or service principal | Role Based Access Control Administrator, User Access Administrator or Owner on the project resource group |
| Create the app registration and service principal | No directory role if users may register applications. Otherwise [Application Developer](https://learn.microsoft.com/powershell/azure/create-azure-service-principal-azureps). |
| Create a user assigned managed identity | Managed Identity Contributor on the identity's resource group |
| Attach a user assigned identity to a VM | Virtual Machine Contributor on the VM and Managed Identity Operator on the identity |
| Turn on a system assigned identity | Virtual Machine Contributor on the VM, or Automation Contributor on the Automation account |
| Create the optional custom role | Owner or User Access Administrator on the resource group |

None of these tasks needs Global Administrator or a subscription level Owner.

## Secrets, credentials and lifecycle

The script is built so that no secret has to be written to disk.

- **Client secrets never go in the config file.** The script ignores a `client_secret` key and warns. Use `-ClientSecret` (a SecureString), the `AZURE_CLIENT_SECRET` environment variable, or a certificate.
- **Rotate credentials.** Certificates every 6 months, secrets every 90 days or less. Remove the old credential after the new one works.
- **Sign in scope.** Managed identity and service principal sign in is limited to the current PowerShell process and does not replace the saved Azure context of the person running it. Interactive sign in behaves like a normal `Connect-AzAccount`.
- **Modules.** Missing modules install from the PowerShell Gallery for the current user. On controlled hosts, install approved versions in advance so nothing is downloaded at run time.
- **Tenant, subscription and client IDs are identifiers, not secrets.** Still keep them out of the script and out of the repo. Use the config file, environment variables or parameters.
- **Decommission.** When the migration project closes, remove the role assignment and delete the identity:

```powershell
Remove-AzRoleAssignment -ObjectId <principal-object-id> -RoleDefinitionName 'Reader' -Scope <scope>
Remove-AzADApplication -ApplicationId <client-id>           # service principal
Remove-AzUserAssignedIdentity -ResourceGroupName <rg> -Name <identity-name>   # managed identity
```

## Handling the exported data

The export is customer confidential. It holds server names, IP addresses, operating system versions, installed software, SQL Server instance and database names, and cost estimates.

- Write exports to an approved location with access limited to the project team. Do not leave them in a user profile or a shared temp folder.
- Never commit exports or the real config file to a repo. Add `WagonmasterManifest/` and `config/wagonmaster-manifest.yml` to `.gitignore`.
- The run log in the temp folder and `_Manifest.json` contain resource IDs and the signed in account name, but no credentials.
- CSV cells that could run as an Excel formula are neutralized. The JSON files are raw, so do not paste JSON values into spreadsheets unchecked.
- Review the `Project_Solutions` dataset once before sending an export outside the team. It lists every resource linked to the project, and its exact contents have not been checked against a live project.
- Delete local copies when the engagement ends, in line with the customer's data handling terms.

## Verification and audit

Confirm least privilege before the first real run, then review it every quarter.

1. List the identity's assignments. Expect exactly one: Reader on the project resource group.

    ```powershell
    Get-AzRoleAssignment -ObjectId <principal-object-id> | Select-Object RoleDefinitionName, Scope
    ```

2. Run the export with `-DryRun`. It proves sign in and read access without pulling data.
3. Run one full export and check `_Summary.csv` for datasets with an Error status.
4. For a service principal, confirm the app registration has no API permissions and no client secrets unless one was approved.

Where runs are recorded:

- **Microsoft Entra sign in logs** record each sign in, under user, service principal or managed identity sign ins.
- **`_Manifest.json`** in every export folder records the account, time, project and API versions.
- The Azure Activity Log does not record read operations, so it will not show exports.

## Sources

- [Prepare Azure accounts for Azure Migrate using built in roles](https://learn.microsoft.com/azure/migrate/prepare-azure-accounts?view=migrate)
- [Create an Azure service principal with Azure PowerShell](https://learn.microsoft.com/powershell/azure/create-azure-service-principal-azureps)
- [Use Azure PowerShell to create a service principal with a certificate](https://learn.microsoft.com/entra/identity-platform/howto-authenticate-service-principal-powershell)
- [What's new in Azure Migrate](https://learn.microsoft.com/azure/migrate/whats-new?view=migrate)
