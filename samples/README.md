# Sample data

`manifest-export` is a fictional Wagonmaster Manifest export for Infinite Improbability Corp. Nothing in it is real. Record shapes follow Microsoft's published Azure Migrate API schemas, in the folder layout Manifest writes.

It is used by the Waypoint tests and the live demo on the docs site.

Regenerate it with:

```bash
python3 tools/New-SampleExport.py samples/manifest-export
```

The generator is deterministic, so the output only changes when the generator does.
