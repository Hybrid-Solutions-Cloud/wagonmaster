# Start here

Wagonmaster is a family of open source tools for Azure migrations. The first tool, Wagonmaster Manifest, exports all the data in an Azure Migrate project to CSV and JSON.

::: warning Early release
Manifest has been code reviewed but has not yet been run against a live Azure Migrate project. Run it with `-DryRun` first and check `_Summary.csv` after your first full export.
:::

## Pick your path

| I want to | Go to |
| --- | --- |
| Export data from an Azure Migrate project today | [How to use Manifest](/manifest/usage) |
| Know what access to grant, and how to set up a managed identity or service principal | [Security and access](/manifest/security) |
| See every API call the tool makes | [API reference](/manifest/api-reference) |
| See what is planned next | [Roadmap](/project/roadmap) |

## Quick start

You need PowerShell 7 and the Reader role on the resource group that holds your Azure Migrate project.

```powershell
git clone https://github.com/Hybrid-Solutions-Cloud/Wagonmaster.git
cd Wagonmaster/src/manifest
./Export-WagonmasterManifest.ps1 -DryRun
```

The script prompts for anything it needs. When the dry run looks right, run it again without `-DryRun`.

## The tools

| Tool | What it does | Status |
| --- | --- | --- |
| [Manifest](/manifest/) | Exports Azure Migrate project data to CSV and JSON | Available, early release |
| Waypoint | Dashboards built on Manifest exports | Planned |
| Muster | Move group and wave planning | Planned |
