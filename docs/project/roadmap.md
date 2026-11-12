# Roadmap

Wagonmaster starts with one tool and grows from the data it produces.

| Tool | Purpose | Status |
| --- | --- | --- |
| [Manifest](/manifest/) | Export all Azure Migrate project data to CSV and JSON | Available, early release |
| Waypoint | Dashboards for discovery, readiness, cost and migration progress, built on Manifest exports | Planned |
| Muster | Move group and wave planning from inventory and dependency data | Planned |

## Next for Manifest

- Run against live projects and confirm every API path
- Pester tests for the helper functions, with Azure calls mocked
- Validate the optional custom role
- Add dependency data if Microsoft publishes a supported API for it
- Publish to the PowerShell Gallery

Have an idea for a tool? [Open an issue](https://github.com/Hybrid-Solutions-Cloud/Wagonmaster/issues).
