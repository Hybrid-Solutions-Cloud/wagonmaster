# Sample data

Two fictional Wagonmaster Manifest exports for Infinite Improbability Corp. Nothing in them is real.

- `manifest-export`: a mixed estate being assessed for and migrated to Azure
- `manifest-export-azure-local`: a VMware estate being migrated to Azure Local
 Record shapes follow Microsoft's published Azure Migrate API schemas, in the folder layout Manifest writes.

They are used by the Waypoint tests and the live demos on the docs site.

Regenerate them with:

```bash
python3 tools/New-SampleExport.py samples/manifest-export azure
python3 tools/New-SampleExport.py samples/manifest-export-azure-local azure-local
```

The generator is deterministic, so the output only changes when the generator does.
