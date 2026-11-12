# Wagonmaster Manifest

Exports all the data in an Azure Migrate project to CSV and JSON. Read only. Needs the Reader role on the project's resource group.

```powershell
./Export-WagonmasterManifest.ps1 -DryRun
```

| File | Purpose |
| --- | --- |
| `Export-WagonmasterManifest.ps1` | The tool |
| `config/wagonmaster-manifest.example.yml` | Example config. Copy to `config/wagonmaster-manifest.yml`, which is gitignored. |

Next step: build a dashboard from the export with [Waypoint](../waypoint/).

Documentation: [How to use](../../docs/manifest/usage.md), [Security and access](../../docs/manifest/security.md), [API reference](../../docs/manifest/api-reference.md).
