# Wagonmaster Waypoint

Builds one self contained HTML dashboard from a Wagonmaster Manifest export. Never contacts Azure.

```powershell
./New-WagonmasterWaypoint.ps1 -ExportPath ../../samples/manifest-export -OutputPath ./demo.html -Open
```

| File | Purpose |
| --- | --- |
| `New-WagonmasterWaypoint.ps1` | Reads the export and embeds its data in the template |
| `template/waypoint.html` | The report: styles, field mapping and views, in one file with no dependencies |

Documentation: [Waypoint](../../docs/waypoint/index.md).
