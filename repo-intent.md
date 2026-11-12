# Repo intent: Wagonmaster

**Open source tools for planning and running Azure migrations.**

## What this repo is

Wagonmaster is a family of tools that work with any Azure Migrate project, whatever the source platform. It is not specific to Azure Local or to any one company. The first tool, Manifest, exports all Azure Migrate project data to CSV and JSON. Dashboards (Waypoint) and wave planning (Muster) are planned on top of that data.

## Shape

- `src/<tool>/`: one folder per tool
- `tests/<tool>/`: Pester tests per tool
- `docs/`: VitePress documentation, published at labs.hybridsolutions.cloud/wagonmaster/
- `tools/`: repo and docs maintenance helpers

## Status

Early release. Manifest is code reviewed but not yet validated against a live project.
