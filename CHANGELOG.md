# Changelog

All notable changes to this repository are recorded here. Each tool is versioned on its own.

## Wagonmaster Waypoint

### 0.1.0 (2026-11-12)

- Initial preview: `New-WagonmasterWaypoint.ps1` builds one self contained HTML dashboard from a Manifest export.
- Views: overview, servers, assessments, SQL Server, web apps, software, migration, project, data explorer, data quality.
- Field mapping layer with a coverage report, so differences in real exports are visible and quick to fix.
- Fictional sample export under `samples/` with its generator, used by tests and the live demo.

## Wagonmaster Manifest

### 1.2.1 (2026-11-12)

- First CI run: the script parses and the static Pester tests pass.
- Documented PSScriptAnalyzer suppression for reading the service principal secret from `AZURE_CLIENT_SECRET`.
- Added `PSScriptAnalyzerSettings.psd1`.

### 1.2.0 (2026-11-12)

- Renamed to Wagonmaster Manifest. The script is now `Export-WagonmasterManifest.ps1`.
- Config file, environment variables (`WAGONMASTER_*`) and default output folder renamed to match.

### 1.1.0 (2026-11-12)

- Stop with a clear error when the project cannot be read.
- Prompt for service principal tenant and client ID in interactive runs.
- Process scoped sign in for managed identity and service principal.
- CSV: formula guard, UTF-8 byte order mark, column name collision fix.
- Validate subscription, resource group and project values.

### 1.0.0 (2026-11-12)

- Initial implementation.

## Repository

### 2026-11-12

- Repository created with the VitePress documentation site, logo and icons.
