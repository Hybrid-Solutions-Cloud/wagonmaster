# API reference

Script version 1.2.1. Last updated 2026-11-12. [Download this page as a Word document](/downloads/wagonmaster-manifest-api-reference.docx){target="_self"}.

## How the script calls Azure

Every data call is an HTTP GET to Azure Resource Manager at `https://management.azure.com`, sent with `Invoke-AzRestMethod`. The one exception is Azure Resource Graph, which is queried with `Search-AzGraph`. The script sends no PUT, POST, PATCH or DELETE of its own.

| Behavior | How it works |
| --- | --- |
| Authentication | The Az module adds a bearer token for the signed in identity and refreshes it during long runs. The script never handles a token itself. |
| Request | `Invoke-AzRestMethod -Method GET` with a resource path and an `api-version` query string |
| Paging | List responses return a `value` array and an optional `nextLink`. The script follows `nextLink` until it is empty. |
| Single objects | A response with no `value` property is treated as one record. |
| Retries | HTTP 429, 500, 502, 503 and 504 are retried up to 5 times, waiting 4, 8, 16, 32 and 60 seconds. |
| Not available | HTTP 400 or 404 marks the dataset as NotAvailable. The run continues. |
| Other failures | Any other status, for example 401 or 403, marks the dataset as Error with the Azure error code and message. The run continues. |
| Fatal errors | Only sign in failures, a missing required value, or an unreadable project stop the run. |
| Logging | Every call is recorded in `_CallLog.csv` with its dataset, path, record count and status. |

Path shorthand used in this doc:

| Token | Expands to |
| --- | --- |
| `{rg}` | `/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}` |
| `{project}` | `{rg}/providers/Microsoft.Migrate/migrateProjects/{projectName}` |
| `{site}` | The full resource ID of a discovery site, read from the project |
| `{assessmentProject}` | The full resource ID of an assessment project, read from the project |
| `{vault}` | The full resource ID of a linked vault, read from the project |

## API versions

All versions are set in one place, the `$ApiVersions` block near the top of the script. Change them there if Microsoft retires a version.

| Key in `$ApiVersions` | Version | Resource provider | Used for |
| --- | --- | --- | --- |
| `MigrateProject` | `2018-09-01-preview` | `Microsoft.Migrate/migrateProjects` | Project and solutions |
| `OffAzure` | `2023-06-06` | `Microsoft.OffAzure` | All discovery data |
| `Assessment` | `2023-03-15` | `Microsoft.Migrate/assessmentProjects` | Groups, Azure VM, AVS and SQL assessments |
| `AssessmentPreview` | `2023-04-01-preview` | `Microsoft.Migrate/assessmentProjects` | Web app assessments and business cases |
| `RecoveryServices` | `2024-04-01` | `Microsoft.RecoveryServices/vaults` | Replication and migration items |
| `DataReplication` | `2021-02-16-preview` | `Microsoft.DataReplication/replicationVaults` | Replication items in the newer vault type |

Three of the six are preview versions. Preview versions carry the highest risk of change, so check them first when a dataset starts to fail.

## Call sequence

Calls run in a fixed order, and each stage uses resource IDs returned by the stage before it.

1. **Sign in and context.** `Connect-AzAccount`, then `Get-AzSubscription` and `Get-AzResource` only if the subscription or project has to be picked from a list.
2. **Project.** GET the project. If it returns nothing, the run stops.
3. **Solutions.** GET the project's solutions. The script scans the response for resource IDs of discovery sites, assessment projects and vaults.
4. **Fallback.** If the solutions hold no IDs, `Get-AzResource` lists every Azure Migrate resource in the resource group instead.
5. **Master sites.** GET each master site and add the VMware, Hyper-V and server sites it lists.
6. **Discovery.** For each site: the site, its hosts or vCenters, then its machines. For each master site: SQL sites and web app sites, then their servers, databases and apps.
7. **Software inventory.** Only with `-IncludeSoftwareInventory`: one GET per discovered machine.
8. **Assessments.** For each assessment project: the project, its machines and groups. For each group: each assessment type. For each assessment: its assessed items.
9. **Business cases.** For each assessment project: business cases, then their evaluated items.
10. **Migration status.** For each linked vault, unless `-SkipMigrationStatus` is set.
11. **Resource Graph.** One paged query, unless `-SkipResourceGraph` is set.

With `-DryRun`, the script stops after step 5 and prints the resource IDs it found.

Call volume: steps 2 to 5 are a handful of calls. Step 6 is a few calls per site, plus paging. Step 8 grows with the number of groups and assessments. Step 7 is the only stage that grows with the number of servers.

## Project and linked resources

These calls find out what belongs to the project. Everything later depends on them. They use the `MigrateProject` version unless noted.

| Dataset | GET path | Purpose |
| --- | --- | --- |
| `Project` | `{project}` | Confirms the project exists and is readable. The run stops if this fails. |
| `Project_Solutions` | `{project}/solutions` | Lists the tools registered to the project. The response holds the resource IDs of linked sites, assessment projects and vaults. |
| None | `{masterSite}` with the `OffAzure` version | Reads `properties.sites` to find the VMware, Hyper-V and server sites behind a master site. |

The script searches the solutions response for resource IDs of these types:

- `Microsoft.OffAzure/VMwareSites`, `HyperVSites`, `ServerSites`, `ImportSites`, `MasterSites`
- `Microsoft.Migrate/assessmentProjects`
- `Microsoft.RecoveryServices/vaults`
- `Microsoft.DataReplication/replicationVaults`

If none are found, the fallback lists resources of the same types in the resource group with `Get-AzResource`. That fallback cannot tell two projects apart when they share a resource group.

## Discovery calls

All discovery calls go to `Microsoft.OffAzure` with the `OffAzure` version, `2023-06-06`. This is the data the appliance collected.

| Dataset | GET path | Applies to |
| --- | --- | --- |
| `Discovery_Sites` | `{site}` | Every site type |
| `Discovery_VMware_vCenters` | `{site}/vCenters` | VMware sites |
| `Discovery_VMware_Machines` | `{site}/machines` | VMware sites |
| `Discovery_HyperV_Hosts` | `{site}/hosts` | Hyper-V sites |
| `Discovery_HyperV_Clusters` | `{site}/clusters` | Hyper-V sites |
| `Discovery_HyperV_Machines` | `{site}/machines` | Hyper-V sites |
| `Discovery_Physical_Machines` | `{site}/machines` | Server sites (physical and other clouds) |
| `Discovery_Imported_Machines` | `{site}/machines` | Import sites (CSV or RVTools import) |
| `Discovery_SqlSites` | `{masterSite}/sqlSites` | Master sites |
| `Discovery_Sql_Servers` | `{sqlSite}/sqlServers` | Each SQL site |
| `Discovery_Sql_Databases` | `{sqlSite}/sqlDatabases` | Each SQL site |
| `Discovery_Sql_AvailabilityGroups` | `{sqlSite}/sqlAvailabilityGroups` | Each SQL site |
| `Discovery_WebAppSites` | `{masterSite}/webAppSites` | Master sites |
| `Discovery_IIS_WebServers` | `{webAppSite}/iisWebServers` | Each web app site |
| `Discovery_IIS_WebApps` | `{webAppSite}/iisWebApplications` | Each web app site |
| `Discovery_Tomcat_WebServers` | `{webAppSite}/tomcatWebServers` | Each web app site |
| `Discovery_Tomcat_WebApps` | `{webAppSite}/tomcatWebApplications` | Each web app site |
| `Discovery_SoftwareInventory` | `{machine}/softwareInventories` | Each machine, only with `-IncludeSoftwareInventory` |

Notes:

- Machine records carry the configuration the appliance gathered, such as operating system, cores, memory, disks and network adapters. The exact fields depend on the site type.
- `{machine}` is the `id` of each machine returned by the machines call, so software inventory costs one call per server.
- Each record is tagged with `_Project` and `_Site` columns, plus `_SqlSite`, `_WebAppSite` or `_Machine` where relevant.

## Assessment and business case calls

These calls go to `Microsoft.Migrate/assessmentProjects`. They return results that Azure Migrate already calculated. The script never creates or recalculates an assessment.

| Dataset | GET path | Version key |
| --- | --- | --- |
| `Assessment_Projects` | `{assessmentProject}` | `Assessment` |
| `Assessment_ProjectMachines` | `{assessmentProject}/machines` | `Assessment` |
| `Assessment_Groups` | `{assessmentProject}/groups` | `Assessment` |
| `Assessment_AzureVM` | `{group}/assessments` | `Assessment` |
| `Assessment_AzureVM_AssessedMachines` | `{assessment}/assessedMachines` | `Assessment` |
| `Assessment_AVS` | `{group}/avsAssessments` | `Assessment` |
| `Assessment_AVS_AssessedMachines` | `{avsAssessment}/avsAssessedMachines` | `Assessment` |
| `Assessment_SQL` | `{group}/sqlAssessments` | `Assessment` |
| `Assessment_SQL_AssessedMachines` | `{sqlAssessment}/assessedSqlMachines` | `Assessment` |
| `Assessment_SQL_AssessedInstances` | `{sqlAssessment}/assessedSqlInstances` | `Assessment` |
| `Assessment_SQL_AssessedDatabases` | `{sqlAssessment}/assessedSqlDatabases` | `Assessment` |
| `Assessment_SQL_RecommendedEntities` | `{sqlAssessment}/recommendedAssessedEntities` | `Assessment` |
| `Assessment_SQL_Summaries` | `{sqlAssessment}/summaries` | `Assessment` |
| `Assessment_WebApp` | `{group}/webAppAssessments` | `AssessmentPreview` |
| `Assessment_WebApp_AssessedWebApps` | `{webAppAssessment}/assessedWebApps` | `AssessmentPreview` |
| `Assessment_WebApp_Summaries` | `{webAppAssessment}/summaries` | `AssessmentPreview` |
| `BusinessCase` | `{assessmentProject}/businessCases` | `AssessmentPreview` |
| `BusinessCase_EvaluatedMachines` | `{businessCase}/evaluatedMachines` | `AssessmentPreview` |
| `BusinessCase_EvaluatedAvsMachines` | `{businessCase}/evaluatedAvsMachines` | `AssessmentPreview` |
| `BusinessCase_EvaluatedSqlEntities` | `{businessCase}/evaluatedSqlEntities` | `AssessmentPreview` |
| `BusinessCase_EvaluatedWebApps` | `{businessCase}/evaluatedWebApps` | `AssessmentPreview` |

Notes:

- `{group}`, `{assessment}` and `{businessCase}` are the `id` values returned by the parent call.
- Assessments are point in time snapshots. The export returns the numbers as of the last calculation, so recalculate in the portal first when fresh sizing or cost is needed.
- Records carry `_AssessmentProject`, `_Group` and `_Assessment` or `_BusinessCase` columns for joining.

## Migration status calls

These calls read replication and migration progress from vaults linked to the project. Skip them with `-SkipMigrationStatus`.

| Dataset | GET path | Version key |
| --- | --- | --- |
| `Migration_ReplicationMigrationItems` | `{vault}/replicationMigrationItems` | `RecoveryServices` |
| `Migration_ReplicationProtectedItems` | `{vault}/replicationProtectedItems` | `RecoveryServices` |
| `Migration_ReplicationJobs` | `{vault}/replicationJobs` | `RecoveryServices` |
| `Migration_DataReplication_ProtectedItems` | `{replicationVault}/protectedItems` | `DataReplication` |
| `Migration_DataReplication_Jobs` | `{replicationVault}/jobs` | `DataReplication` |

Notes:

- The first three apply to Recovery Services vaults, which the classic Migration and modernization tool uses.
- The last two apply to `Microsoft.DataReplication` vaults. The `jobs` path is not confirmed for this API version and may return NotAvailable.
- A project that has only been used for discovery and assessment has no vault. These datasets are then simply absent.

## Resource Graph query

One Kusto query pulls every Azure Migrate record that Resource Graph indexes for the resource group. Skip it with `-SkipResourceGraph`.

```kusto
migrateresources
| where subscriptionId =~ '<subscription-id>' and resourceGroup =~ '<resource-group>'
```

| Behavior | How it works |
| --- | --- |
| Cmdlet | `Search-AzGraph -Query <query> -Subscription <subscription-id> -First 1000` |
| Paging | Repeats with the returned `SkipToken` until none is returned |
| Datasets | Rows are grouped by resource type. Each type becomes `ResourceGraph_<type>`, for example `ResourceGraph_vmwaresites_machines`. |
| Input safety | The subscription ID and resource group name are validated before they are placed in the query. |
| Failure | A failed query is recorded as an Error for `ResourceGraph`. The run continues. |

This data overlaps with the discovery calls. It is included because one query returns the whole estate quickly, and because it can surface resource types the direct calls do not cover. When the two disagree, treat the direct REST datasets as the reference, since Resource Graph can lag behind.

## Az PowerShell cmdlets used

The script uses seven Az cmdlets. All are read only except sign in and context selection, which change only the local session.

| Cmdlet | Module | Why it is called |
| --- | --- | --- |
| `Connect-AzAccount` | Az.Accounts | Sign in. Process scoped for managed identity and service principal. |
| `Get-AzContext` | Az.Accounts | Reuse an existing session and record who ran the export |
| `Get-AzSubscription` | Az.Accounts | Build the subscription picker when no subscription was given |
| `Set-AzContext` | Az.Accounts | Select the subscription for the session |
| `Get-AzResource` | Az.Resources | Build the project picker, and the fallback list of linked resources |
| `Invoke-AzRestMethod` | Az.Accounts | Every Azure Resource Manager GET in this doc |
| `Search-AzGraph` | Az.ResourceGraph | The Resource Graph query |

`Install-Module` and `Import-Module` are also called for any module that is missing. `ConvertFrom-Yaml` from `powershell-yaml` reads the config file when one is used.

## Verification status

None of these calls has been run against a live project yet. A small number were checked against Microsoft Learn reference pages while the script was written. The rest follow the published shape of the APIs and need a first real run to confirm.

| Status | Calls |
| --- | --- |
| Checked against Microsoft Learn reference | `Microsoft.OffAzure` VMware site machines at `2023-06-06`; machine `softwareInventories`; `assessmentProjects/machines` and `groups/sqlAssessments` at `2023-03-15`; the `MigrateResources` Resource Graph table |
| Not yet checked | All other paths in this doc |
| Most likely to need a change | Web app assessments, business cases, and the Data Replication `jobs` path |

How to confirm after the first run: open `_CallLog.csv`. Each row shows one path and its status. A path that returns NotAvailable on a project that clearly has that data is a path to correct.

What the script does not call:

- **Dependency data.** Not exported. Use the portal under Manage Dependencies, then Export dependencies.
- **Export or report generation actions.** These are POST operations and need more than Reader.
- **Anything that writes.** No create, update, recalculate or delete operation is used.

To test a single call by hand:

```powershell
$path = '/subscriptions/<subscription-id>/resourceGroups/<resource-group>' +
        '/providers/Microsoft.Migrate/migrateProjects/<project-name>/solutions' +
        '?api-version=2018-09-01-preview'
$response = Invoke-AzRestMethod -Path $path -Method GET
$response.StatusCode
$response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 20
```

## Sources

- [Azure Migrate REST API](https://learn.microsoft.com/rest/api/migrate/)
- [Microsoft.OffAzure vmwareSites/machines reference](https://learn.microsoft.com/azure/templates/microsoft.offazure/vmwaresites/machines)
- [Microsoft.OffAzure softwareInventories reference](https://learn.microsoft.com/azure/templates/microsoft.offazure/vmwaresites/machines/softwareinventories)
- [Microsoft.Migrate assessmentProjects/machines reference](https://learn.microsoft.com/azure/templates/microsoft.migrate/2023-03-15/assessmentprojects/machines)
- [Microsoft.Migrate sqlAssessments reference](https://learn.microsoft.com/azure/templates/microsoft.migrate/assessmentprojects/groups/sqlassessments)
- [Resource Graph tables](https://learn.microsoft.com/azure/governance/resource-graph/concepts/query-language#resource-graph-tables)
