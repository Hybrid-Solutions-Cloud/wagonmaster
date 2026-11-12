// Test helper: builds a Waypoint report from an export folder the same way
// New-WagonmasterWaypoint.ps1 does, so the template can be tested without PowerShell.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

export function buildReport(exportFolder, templatePath) {
  const jsonFolder = join(exportFolder, 'json');
  const parts = [];
  for (const file of readdirSync(jsonFolder).filter((f) => f.endsWith('.json')).sort()) {
    const text = readFileSync(join(jsonFolder, file), 'utf8').trim().replace(/^﻿/, '');
    if (text.startsWith('[')) parts.push(JSON.stringify(file.replace(/\.json$/, '')) + ':' + text);
  }
  const manifestPath = join(exportFolder, '_Manifest.json');
  const manifest = existsSync(manifestPath) ? readFileSync(manifestPath, 'utf8').trim() : '{}';
  const summaryPath = join(exportFolder, '_Summary.csv');
  let summary = [];
  if (existsSync(summaryPath)) {
    const lines = readFileSync(summaryPath, 'utf8').replace(/^﻿/, '').trim().split(/\r?\n/);
    const head = lines.shift().split(',');
    summary = lines.map((l) => Object.fromEntries(l.split(',').map((v, i) => [head[i], v])));
  }
  const meta = { title: '', waypointVersion: 'test', generatedAtUtc: '2026-11-12T00:00:00Z', datasetCount: parts.length };
  const data = ('{"meta":' + JSON.stringify(meta) + ',"manifest":' + manifest + ',"summary":' + JSON.stringify(summary) + ',"datasets":{' + parts.join(',') + '}}')
    .replaceAll('</', '<\\/');
  return readFileSync(templatePath, 'utf8').replace('__WAGONMASTER_DATA__', () => data);
}
