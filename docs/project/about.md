# About Wagonmaster

Wagonmaster is a family of open source tools for Azure migrations, published by Hybrid Solutions Cloud. A wagonmaster plans the route, loads the wagons and leads the train to its new home. These tools do the same for workloads moving to Azure.

## Principles

- **Any source.** The tools work with any Azure Migrate project: VMware, Hyper-V, physical servers and other clouds.
- **Read only first.** Tools that only report never change anything in Azure.
- **Least privilege.** Every tool documents the exact access it needs and how to grant it.
- **Usable by project managers.** A tool should run with no parameters and ask for what it needs.
- **One name per tool.** Each tool has its own name, folder, docs section and version.

## Repository layout

| Path | Contents |
| --- | --- |
| `src/<tool>/` | One folder per tool. `src/manifest/` holds Wagonmaster Manifest. |
| `tests/<tool>/` | Pester tests for that tool |
| `docs/` | This site, built with VitePress. One folder per tool. |
| `tools/` | Helper scripts for maintaining the repo and docs |

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](https://github.com/Hybrid-Solutions-Cloud/wagonmaster/blob/main/CONTRIBUTING.md).
