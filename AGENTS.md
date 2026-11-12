# Wagonmaster: agent instructions

Open source tools for Azure migrations. See `repo-intent.md` for scope and `README.md` for layout.

## Session start

If the HCS Governance MCP server is available (`.mcp.json`), call `bootstrap` for this repo once, then `get_standard` for any standard you need in full.

## Hard rules

- Tools that report must stay read only: GET requests only.
- Never add access requirements without updating `docs/manifest/security.md`.
- Never commit exports, real config files, secrets, subscription IDs or tenant IDs.
- PowerShell 7 only, `Verb-Noun.ps1` names, approved verbs, `-DryRun` instead of ShouldProcess.
- Keep `docs/manifest/api-reference.md` in step with every API call in the code.
- Docs prose: no dashes as sentence punctuation.
- The repo is designed to grow: a new tool gets `src/<tool>/`, `tests/<tool>/` and `docs/<tool>/`. Do not add tool code at the repo root.

## Current state

Manifest (`src/manifest/Export-WagonmasterManifest.ps1`) parses and passes static tests in CI, but has never been run against Azure. The open work list is in `.ai/state/HANDOFF.md`.

Waypoint (`src/waypoint/`) is a preview built on the two sample exports in `samples/` (Azure and Azure Local targets). It has never read an export from a real project. All field access in the report goes through the `MAP` table in `template/waypoint.html`: fix paths there, never in a view. Values from the export must only ever be written with text nodes, never as HTML.

## Commands

- Docs: `cd docs && npm ci && npm run docs:build`
- Lint: `Invoke-ScriptAnalyzer -Path src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`
- Tests: `Invoke-Pester -Path tests`
- Waypoint template tests: `cd tests/waypoint && npm ci && npm test`
- Sample data: `python3 tools/New-SampleExport.py samples/manifest-export azure` and `python3 tools/New-SampleExport.py samples/manifest-export-azure-local azure-local`
- Word downloads: `bash tools/Build-WordDocs.sh`

## Confirm with the owner before

- Anything that signs in to or calls Azure
- Changing repo visibility, Pages settings or releases
