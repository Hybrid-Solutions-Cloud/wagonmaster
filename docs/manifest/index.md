# Wagonmaster Manifest

Manifest exports everything an Azure Migrate project exposes through Azure APIs. Each dataset is written twice: a flattened CSV for Excel or Power BI, and a JSON file with the full structure. A wagon train's manifest lists everything loaded on the wagons, and this is the same list for a migration.

::: warning Early release
Manifest has been code reviewed but has not yet been run against a live Azure Migrate project. Run it with `-DryRun` first.
:::

## What you get

| Area | Data |
| --- | --- |
| Discovery | Sites, vCenters, Hyper-V hosts and clusters, machines, SQL Server instances and databases, IIS and Tomcat web apps |
| Software (optional) | Installed software per machine |
| Assessments | Azure VM, AVS, SQL and web app assessments, with per machine results |
| Business case | Business cases and their evaluated workloads |
| Migration | Replication and migration status from linked vaults |
| Resource Graph | Every project record in the `MigrateResources` table |

Agentless dependency data is not included. Export it from the Azure portal.

## How it behaves

- **Read only.** It makes GET calls only and never changes anything in Azure.
- **Least privilege.** It needs the Reader role on the project's resource group and nothing else.
- **Three ways to sign in.** Interactive, managed identity or service principal.
- **Friendly to non engineers.** Run it with no parameters and it prompts for what it needs. Subscriptions and projects are picked from a list.
- **Safe to automate.** In pipelines and scheduled runs it never prompts. A missing value stops the run with a clear error.

## Documentation

| Page | Read it when |
| --- | --- |
| [How to use](./usage) | You want to run an export |
| [Security and access](./security) | You need to grant access or create an identity |
| [API reference](./api-reference) | You want to know exactly which calls are made |

## Source

The script lives at [`src/manifest/Export-WagonmasterManifest.ps1`](https://github.com/Hybrid-Solutions-Cloud/Wagonmaster/blob/main/src/manifest/Export-WagonmasterManifest.ps1).
