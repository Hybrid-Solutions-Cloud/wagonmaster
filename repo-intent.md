# Repo intent: Wagonmaster

**Open source tools for planning and running Azure migrations.**

## What this repo is

Wagonmaster is a family of tools that work with any Azure Migrate project, whatever the source platform. It is not specific to Azure Local or to any one company. Manifest exports all Azure Migrate project data to CSV and JSON. Waypoint turns an export into a one file HTML dashboard, for migrations to Azure or to Azure Local. Wave planning (Muster) is planned on top of the same data.

## Shape

- `src/<tool>/`: one folder per tool
- `tests/<tool>/`: Pester tests per tool
- `docs/`: VitePress documentation, published at labs.hybridsolutions.cloud/wagonmaster/
- `samples/`: fictional sample exports used by tests and the live demos
- `tools/`: repo, docs and sample data helpers

## Status

Early release. Manifest passes static checks but is not yet validated against a live project. Waypoint is a preview built on sample data and has not yet read a real export.
