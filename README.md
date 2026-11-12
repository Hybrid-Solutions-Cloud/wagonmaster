<p align="center">
  <img src="docs/public/assets/images/wagonmaster-banner.svg" alt="Wagonmaster" width="360">
</p>

# Wagonmaster

Open source tools for planning and running Azure migrations. Wagonmaster works with any Azure Migrate project, whatever the source platform: VMware, Hyper-V, physical servers or other clouds.

**Documentation:** [labs.hybridsolutions.cloud/Wagonmaster](https://labs.hybridsolutions.cloud/Wagonmaster/)

## Tools

| Tool | What it does | Status |
| --- | --- | --- |
| [Manifest](src/manifest/) | Exports all the data in an Azure Migrate project to CSV and JSON | Available, early release |
| Waypoint | Dashboards built on Manifest exports | Planned |
| Muster | Move group and wave planning | Planned |

## Quick start: Manifest

You need PowerShell 7 and the Reader role on the resource group that holds your Azure Migrate project.

```powershell
git clone https://github.com/Hybrid-Solutions-Cloud/Wagonmaster.git
cd Wagonmaster/src/manifest
./Export-WagonmasterManifest.ps1 -DryRun
```

The script prompts for anything it needs. When the dry run looks right, run it again without `-DryRun`.

> **Early release.** Manifest has been code reviewed but has not yet been run against a live Azure Migrate project. Start with `-DryRun` and check `_Summary.csv` after the first full export.

- [How to use](docs/manifest/usage.md)
- [Security and access](docs/manifest/security.md): the RBAC needed for interactive, managed identity and service principal runs, and how to create each identity
- [API reference](docs/manifest/api-reference.md): every call the tool makes

## Repository layout

| Path | Contents |
| --- | --- |
| `src/<tool>/` | One folder per tool. `src/manifest/` holds Wagonmaster Manifest. |
| `tests/<tool>/` | Pester tests for that tool |
| `docs/` | VitePress documentation site. One folder per tool. |
| `tools/` | Helper scripts for maintaining the repo and docs |
| `.github/workflows/` | Docs build and deploy, and script validation |

## Adding a tool

1. Create `src/<tool>/` with the tool and a short `README.md`.
2. Create `tests/<tool>/` with its Pester tests.
3. Create `docs/<tool>/` with an `index.md`, then add a sidebar array and a Tools menu entry in `docs/.vitepress/config.mts`.
4. Add the tool to the tables in this README, `docs/start-here.md` and `docs/project/roadmap.md`.
5. Record the change in `CHANGELOG.md`.

## Working on the docs

```bash
cd docs
npm ci
npm run docs:dev
```

## License

[MIT](LICENSE). Azure and Azure Migrate are trademarks of the Microsoft group of companies. Wagonmaster is an independent project and is not affiliated with or endorsed by Microsoft.
