# Contributing

Thanks for helping with Wagonmaster. Issues and pull requests are welcome.

## Ground rules

- **Read only tools stay read only.** Manifest must never send anything other than GET requests to Azure.
- **Least privilege.** If a change needs more access than the docs state, update the Security and access page in the same pull request.
- **Never commit exports or real config files.** They contain customer data. The `.gitignore` covers the default paths.
- **Docs change with code.** The API reference lists every call a tool makes. Keep it in step.

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
cd docs && npm ci && npm run docs:build
```

## Branches

`feature/<description>`, `fix/<description>`, `docs/<description>` or `chore/<description>`, merged to `main` by pull request.

## Docs style

Plain language, short sentences. Do not use dashes as sentence punctuation. Use commas, colons or separate sentences.
