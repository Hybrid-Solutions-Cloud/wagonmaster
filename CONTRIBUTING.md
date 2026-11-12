# Contributing

Thanks for helping with Wagonmaster. Issues and pull requests are welcome.

## Ground rules

- **Read only tools stay read only.** Manifest must never send anything other than GET requests to Azure.
- **Least privilege.** If a change needs more access than the docs state, update the Security and access page in the same pull request.
- **Never commit exports or real config files.** They contain customer data. The `.gitignore` covers the default paths.
- **Docs change with code.** The API reference lists every call a tool makes. Keep it in step.
- **Waypoint reads fields through its mapping table.** Add or fix paths in `MAP` in `src/waypoint/template/waypoint.html`, never inside a view.
- **Export values are text, never markup.** Waypoint must only write values from an export as text nodes.

## PowerShell

- PowerShell 7 or later. Every script starts with `#Requires -Version 7.0`, `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`.
- Approved verbs only. Script files are named `Verb-Noun.ps1`.
- No hardcoded subscription IDs, tenant IDs or secrets.
- Use a `-DryRun` switch for anything with side effects.
- Bump the script version and its ChangeLog in the `.NOTES` block, and add an entry to `CHANGELOG.md`.

## Before you open a pull request

```powershell
Invoke-ScriptAnalyzer -Path src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path tests
```

```bash
cd tests/waypoint && npm ci && npm test
cd docs && npm ci && npm run docs:build
```

If you change the sample generator, regenerate both sample exports and commit them:

```bash
python3 tools/New-SampleExport.py samples/manifest-export azure
python3 tools/New-SampleExport.py samples/manifest-export-azure-local azure-local
```

If you change a Manifest doc page, regenerate the Word downloads with `bash tools/Build-WordDocs.sh`.

## Branches

`feature/<description>`, `fix/<description>`, `docs/<description>` or `chore/<description>`, merged to `main` by pull request.

## Docs style

Plain language, short sentences. Do not use dashes as sentence punctuation. Use commas, colons or separate sentences.
