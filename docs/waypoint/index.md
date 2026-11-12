# Wagonmaster Waypoint

Waypoint turns a Wagonmaster Manifest export into one HTML dashboard, for migrations to Azure or to Azure Local. The file needs no server, no internet access and no sign in: open it in any browser, email it, or put it on a file share.

Version 0.2.0. Last updated 2026-11-12.

## Live demos

Both demos are built from fictional data every time the site is published.

| Demo | What it shows |
| --- | --- |
| <a href="/wagonmaster/waypoint-demo/index.html" target="_blank" rel="noopener"><strong>Migrating to Azure</strong></a> | 240 servers on VMware, Hyper-V and physical hardware, with Azure VM, AVS and SQL assessments, a business case and migrations in flight |
| <a href="/wagonmaster/waypoint-demo-azure-local/index.html" target="_blank" rel="noopener"><strong>Migrating to Azure Local</strong></a> | 180 VMware VMs moving to an Azure Local instance, with readiness, a cluster sizing estimate and replication progress |

::: warning Preview, built on sample data
Waypoint was built against sample data that follows Microsoft's published API schemas. It has not yet been run on an export from a real Azure Migrate project. The Data quality tab shows how well it could read each field, so any mismatch with real data is visible and quick to fix.
:::

## What it shows

Waypoint includes every dataset in the export. Curated views sit on top, and the Data explorer shows every field of every record.

| Tab | Contents |
| --- | --- |
| Overview | Server, core, memory and disk totals, SQL and web app counts, Azure readiness, operating system support status, estimated monthly cost, migration state |
| Servers | Every discovered server joined to its assessment, SQL, web app and migration data. Select a row for everything known about that server. |
| Assessments | Per assessment: cost and its split, readiness, readiness issues, recommended VM sizes, CPU and memory utilization bands, every assessed server. AVS, SQL and web app assessments are listed too. |
| Azure Local | Readiness of every server for Azure Local, the conditions found, checks to do by hand, and an adjustable cluster sizing estimate |
| SQL Server | Instances by version, edition and support status, databases with sizes, recommended Azure SQL targets and cost |
| Web apps | IIS and Tomcat apps by server type and framework |
| Software | Most installed software and publishers, with the servers each is installed on. Needs an export made with `-IncludeSoftwareInventory`. |
| Migration | Replication and migration state, test migrations, items needing attention |
| Project | The project, its registered tools, discovery sites, vCenters, Hyper-V hosts and business cases |
| Data explorer | Any dataset, every field. Search, sort, open a full record, download the filtered view as CSV. |
| Data quality | Which datasets the export contained, which were missing or errored, and field coverage |

Every table can be searched, sorted, filtered and downloaded as CSV. The report follows your light or dark setting and can be printed.

## Migrations to Azure Local

Waypoint works for projects that migrate VMware or Hyper-V VMs to Azure Local with Azure Migrate. It detects the target from the replication items in the export and adjusts the overview and migration views to match.

Azure Migrate has no assessment type for Azure Local. Waypoint fills that gap from the discovery data, and labels the results as its own estimate:

- **Readiness.** Each server is checked against Microsoft's published requirements. Servers that are not on VMware or Hyper-V are marked not supported. Windows Server 2008 R2 is marked ready with conditions, because it needs SP1 and update KB3138612 first. Linux servers get a reminder to confirm Hyper-V drivers are in the boot image.
- **Checks to do by hand.** BitLocker, encrypted disks and shared disks block migration, and discovery data cannot show them. The tab lists them so they are not forgotten.
- **Cluster sizing estimate.** Node count from CPU, memory and storage demand. You can change the virtual CPU to core ratio, growth allowance, node size, storage resiliency and whether to add a spare node, and the estimate updates as you type. When the export has assessment performance data, sizing can use utilized instead of allocated resources.
- **Migration progress.** Replication items for Azure Local are read from the `Migration_DataReplication_ProtectedItems` dataset, with the target Azure Local instance and target VM.

The Azure Local tab is always present, so it also works as a what if for an estate currently planned for Azure.

The sizing estimate is for planning conversations. It does not replace a validated Azure Local design or the hardware vendor's sizing tool.

Sources for the rules: [VMware migration requirements](https://learn.microsoft.com/azure/azure-local/migrate/migrate-vmware-requirements), [VMware migration prerequisites](https://learn.microsoft.com/azure/azure-local/migrate/migrate-vmware-prerequisites), [Hyper-V migration requirements](https://learn.microsoft.com/azure/azure-local/migrate/migrate-hyperv-requirements) and the [migration FAQ](https://learn.microsoft.com/azure/azure-local/migrate/migrate-faq).

## Create a report

You need PowerShell 7 and a Manifest export. Waypoint never contacts Azure, so it needs no Azure access at all.

```powershell
cd wagonmaster/src/waypoint
./New-WagonmasterWaypoint.ps1 -ExportPath <path-to-export-folder> -Open
```

The export folder is the timestamped folder Manifest writes, the one that holds `_Manifest.json` and the `json` folder. The report is written into that folder as `Waypoint.html`.

To try it without an export, use the sample data in the repository:

```powershell
./New-WagonmasterWaypoint.ps1 -ExportPath ../../samples/manifest-export -OutputPath ./demo.html -Open
```

## Parameters

| Parameter | What it does | Environment variable |
| --- | --- | --- |
| `-ExportPath` | The Manifest export folder. If omitted, the newest export under `.\WagonmasterManifest` is used, then you are prompted. | `WAGONMASTER_EXPORT_PATH` |
| `-OutputPath` | The HTML file to write. Default: `Waypoint.html` in the export folder. | `WAGONMASTER_WAYPOINT_OUTPUT` |
| `-Title` | The title at the top of the report | |
| `-ExcludeDataset` | Dataset names to leave out. Wildcards are allowed. | |
| `-Open` | Opens the report in the default browser when done | |
| `-NonInteractive` | Never prompts. A missing value is an error. | |

## Large estates

The report embeds the data, so its size follows the export. Software inventory is the largest dataset by far. If the report is slow to open, leave it out:

```powershell
./New-WagonmasterWaypoint.ps1 -ExportPath <path> -ExcludeDataset Discovery_SoftwareInventory
```

## Handle the report as confidential

The report holds the same data as the export: server names, IP addresses, software, SQL Server details and cost estimates. Share it the way you would share the export. Values from the export are always shown as text and never run as code.

## How Waypoint reads the data

Waypoint reads fields through one mapping table at the top of the report script, never by a fixed path. Each logical field, such as a server's operating system, lists the paths to try in order. If a real export names a field differently, one line in that table fixes every view that uses it.

The **Data quality** tab reports, for every mapped field, how many records it matched and which path it used. After your first report on real data, check that tab. A field at 0% is a path to add.

## Sample data

The repository holds two fictional exports for Infinite Improbability Corp, generated by `tools/New-SampleExport.py` and the same every time. The tests and the live demos use them.

| Folder | Contents |
| --- | --- |
| `samples/manifest-export` | 240 servers across VMware, Hyper-V and physical sites, with SQL Server, web apps, assessments, a business case and migrations to Azure |
| `samples/manifest-export-azure-local` | 180 VMware VMs with SQL Server and web apps, no assessments, and replication to an Azure Local instance |

## Source

- Script: [`src/waypoint/New-WagonmasterWaypoint.ps1`](https://github.com/Hybrid-Solutions-Cloud/wagonmaster/blob/main/src/waypoint/New-WagonmasterWaypoint.ps1)
- Report template: [`src/waypoint/template/waypoint.html`](https://github.com/Hybrid-Solutions-Cloud/wagonmaster/blob/main/src/waypoint/template/waypoint.html)
