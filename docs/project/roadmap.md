# Roadmap

Wagonmaster starts with one tool and grows from the data it produces.

| Tool | Purpose | Status |
| --- | --- | --- |
| [Manifest](/manifest/) | Export all Azure Migrate project data to CSV and JSON | Available, early release |
| [Waypoint](/waypoint/) | One file HTML dashboard for discovery, readiness, cost, Azure Local sizing and migration progress, built from a Manifest export | Preview, built on sample data |
| Muster | Move group and wave planning from inventory and dependency data | Planned |

## Next for Manifest

- Run against live projects and confirm every API path
- Pester tests for the helper functions, with Azure calls mocked
- Validate the optional custom role
- Add dependency data if Microsoft publishes a supported API for it
- Publish to the PowerShell Gallery

## Next for Waypoint

- Confirm field coverage against an export from a real project, for both Azure and Azure Local targets
- Owner supplied defaults for the Azure Local sizing estimate
- Dependency views, once dependency data can be exported
- Wave and move group views, to pair with Muster
- Compare two exports to show progress over time

Have an idea for a tool? [Open an issue](https://github.com/Hybrid-Solutions-Cloud/wagonmaster/issues).
