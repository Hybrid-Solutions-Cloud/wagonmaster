# Handoff

Last updated: 2026-11-12

## Where things stand

- Wagonmaster Manifest 1.2.1 was written and reviewed in a chat session. It parses and passes the static Pester tests in CI. It has never been run against Azure.
- The docs site builds cleanly with VitePress.
- The repo was created the same day. GitHub Pages may still need to be enabled (Settings, Pages, Source: GitHub Actions).

## Open work, in order

1. Static validation is in CI (`validate` workflow: Pester static tests, then PSScriptAnalyzer). Still to do: confirm `Get-Help -Full` renders, and review the analyzer warnings excluded in `PSScriptAnalyzerSettings.psd1`.
2. Pester 5 tests under `tests/manifest/` for the pure helpers, with Az cmdlets mocked: `Resolve-HCSSetting` precedence, `ConvertTo-HCSFlatRecord`, `Export-HCSDataset` (prefix collision, truncation, formula guard, byte order mark), `Get-HCSArmCollection` paging, `Invoke-HCSArmRequest` retry and NotAvailable handling, `Get-HCSLinkedResourceIds`, `Test-HCSInteractiveHost`. The script runs its main block when invoked, so make the functions testable without running main while keeping the single file entry point.
3. Verify unconfirmed API paths against Microsoft Learn: web app assessments and business cases at `2023-04-01-preview`, Data Replication `jobs` at `2021-02-16-preview` (may be `workflows`), `migrateProjects/solutions` at `2018-09-01-preview`, SQL and web app child paths under `MasterSites`. Check whether a documented API now exists for agentless dependency export. Update the script and `docs/manifest/api-reference.md` together.
4. Live test, only after the owner names a subscription, resource group and project: `-DryRun`, then a full run. Review `_Summary.csv` and `_CallLog.csv`.
5. Test the optional custom role in `docs/manifest/security.md` against a real run.
6. Regenerate Word downloads after any doc change: `bash tools/Build-WordDocs.sh`.

## Decisions already made

- Name: Wagonmaster. Tools: Manifest (now), Waypoint (dashboards, planned), Muster (wave planning, planned).
- Public repo under Hybrid-Solutions-Cloud, docs on labs.hybridsolutions.cloud via GitHub Pages, VitePress to match hybrid-health-monitoring.
- Not specific to Azure Local or to any employer. Keep examples generic.
