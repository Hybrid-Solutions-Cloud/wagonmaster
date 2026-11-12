import assert from 'node:assert/strict';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { JSDOM } from 'jsdom';
import { buildReport } from './build-report.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const template = root + 'src/waypoint/template/waypoint.html';
const sample = root + 'samples/manifest-export';
const sampleAzl = root + 'samples/manifest-export-azure-local';

async function load(html) {
  const errors = [];
  const dom = new JSDOM(html, { runScripts: 'dangerously', pretendToBeVisual: true, url: 'https://example.invalid/waypoint.html' });
  dom.window.addEventListener('error', (e) => errors.push(e.message));
  if (dom.window.document.readyState !== 'complete') {
    await new Promise((resolve) => dom.window.addEventListener('load', resolve));
  }
  return { dom, win: dom.window, doc: dom.window.document, errors };
}
function tileValue(doc, label) {
  const tile = [...doc.querySelectorAll('.tile')].find((t) => t.querySelector('.label').textContent === label);
  return tile ? tile.querySelector('.value').textContent : null;
}

test('renders the overview from the sample export', async () => {
  const { win, doc, errors } = await load(buildReport(sample, template));
  assert.deepEqual(errors, []);
  assert.ok(win.WagonmasterWaypoint, 'report script ran');
  assert.equal(win.WagonmasterWaypoint.machines, 240);
  assert.equal(tileValue(doc, 'Servers discovered'), '240');
  assert.match(doc.title, /iic-migrate/);
  assert.match(doc.querySelector('.banner').textContent, /Sample data/);
  assert.match(tileValue(doc, 'Estimated monthly cost'), /^\$[\d,]+$/);
  assert.ok(doc.querySelectorAll('.stack .seg').length >= 4, 'readiness and support bars drawn');
});

test('every tab draws without error and shows content', async () => {
  const { win, doc, errors } = await load(buildReport(sample, template));
  for (const id of win.WagonmasterWaypoint.tabs) {
    win.WagonmasterWaypoint.show(id);
    const main = doc.querySelector('main');
    assert.ok(main.textContent.length > 40, `tab ${id} has content`);
    assert.doesNotMatch(main.textContent, /could not be drawn/, `tab ${id} drew`);
  }
  assert.deepEqual(errors, []);
});

test('servers table joins assessment data, filters and opens detail', async () => {
  const { win, doc } = await load(buildReport(sample, template));
  win.WagonmasterWaypoint.show('servers');
  const info = () => doc.querySelector('main .info').textContent;
  assert.match(info(), /240 of 240 rows/);
  const search = doc.querySelector('main input[type=search]');
  search.value = 'iic-sql';
  search.dispatchEvent(new win.Event('input'));
  assert.match(info(), /^\d+ of 240 rows$/);
  assert.notEqual(info(), '240 of 240 rows');
  const firstRow = doc.querySelector('main tbody tr');
  assert.match(firstRow.textContent, /iic-sql-/);
  assert.match(firstRow.textContent, /Ready|Not ready|Unknown/);
  firstRow.click();
  const drawer = doc.querySelector('.drawer');
  assert.ok(drawer, 'detail drawer opened');
  assert.match(drawer.textContent, /Full discovery record/);
});

test('data explorer lists every dataset with all fields', async () => {
  const { win, doc } = await load(buildReport(sample, template));
  win.WagonmasterWaypoint.show('explorer');
  const options = [...doc.querySelectorAll('main select[aria-label=Dataset] option')].map((o) => o.value);
  assert.equal(options.length, 30);
  assert.ok(options.includes('Discovery_VMware_Machines'));
  const headers = [...doc.querySelectorAll('main th')].map((th) => th.textContent);
  assert.ok(headers.length > 5);
});

test('field coverage is complete for the core fields on sample data', async () => {
  const { win } = await load(buildReport(sample, template));
  win.WagonmasterWaypoint.show('quality');
  const cov = win.WagonmasterWaypoint.coverage;
  for (const key of ['machine.name', 'machine.osName', 'machine.cores', 'machine.memoryMb', 'assessed.suitability', 'assessed.machineId', 'sqlServer.version', 'migration.state']) {
    assert.ok(cov[key], `${key} was read`);
    assert.equal(cov[key].hit, cov[key].seen, `${key} matched every record`);
  }
});

test('does not execute markup found in data', async () => {
  const html = buildReport(sample, template).replace('"displayName": "iic-', '"displayName": "<img src=x onerror=window.__pwned=1><\\/script><script>window.__pwned=1<\\/script>iic-');
  const { win, doc } = await load(html);
  win.WagonmasterWaypoint.show('servers');
  assert.equal(win.__pwned, undefined);
  assert.equal(doc.querySelectorAll('main img').length, 0);
});

test('an empty export still renders', async () => {
  const html = buildReport(sample, template).replace(/"datasets":\{[\s\S]*\}\}(?=<\/script>)/, '"datasets":{}}');
  const { win, doc, errors } = await load(html);
  assert.deepEqual(errors, []);
  assert.equal(win.WagonmasterWaypoint.machines, 0);
  for (const id of win.WagonmasterWaypoint.tabs) win.WagonmasterWaypoint.show(id);
  assert.doesNotMatch(doc.querySelector('main').textContent, /could not be drawn/);
});

test('Azure sample: Azure Local tab works as a what-if and offers utilization sizing', async () => {
  const { win, doc } = await load(buildReport(sample, template));
  assert.equal(win.WagonmasterWaypoint.azureLocal.target, false);
  win.WagonmasterWaypoint.show('azurelocal');
  const main = doc.querySelector('main');
  assert.match(main.textContent, /Cluster sizing estimate/);
  assert.ok(doc.querySelector('main select[aria-label="Size from"]'), 'utilization basis offered when assessment data exists');
  assert.match(main.textContent, /Not supported/, 'physical servers are flagged');
  const size = win.WagonmasterWaypoint.azureLocal.size(win.WagonmasterWaypoint.azureLocal.defaults);
  assert.equal(size.servers, 220, 'physical servers are left out of sizing');
  assert.ok(size.nodes >= 4);
});

test('Azure Local sample: target detected, migration tracked, estimate recalculates', async () => {
  const { win, doc, errors } = await load(buildReport(sampleAzl, template));
  assert.deepEqual(errors, []);
  const wm = win.WagonmasterWaypoint;
  assert.equal(wm.machines, 180);
  assert.equal(wm.azureLocal.target, true);
  assert.equal(wm.model.migrations, 64);
  assert.match(doc.querySelector('header .meta').textContent, /target Azure Local/);
  assert.match(tileValue(doc, 'Azure Local nodes'), /^\d+$/);
  assert.equal(tileValue(doc, 'Estimated monthly cost'), null, 'no Azure cost tile without an assessment');
  for (const id of wm.tabs) {
    wm.show(id);
    assert.doesNotMatch(doc.querySelector('main').textContent, /could not be drawn/, `tab ${id} drew`);
  }
  wm.show('migration');
  assert.match(doc.querySelector('main').textContent, /iic-azl-clus01/);
  assert.match(doc.querySelector('main').textContent, /Migration completed/);
  wm.show('azurelocal');
  assert.equal(doc.querySelector('main select[aria-label="Size from"]'), null, 'no utilization basis without assessment data');
  const before = tileValue(doc, 'Nodes needed');
  const ratio = doc.querySelector('main input[aria-label="Virtual CPUs per physical core"]');
  ratio.value = '1';
  ratio.dispatchEvent(new win.Event('input'));
  const after = tileValue(doc, 'Nodes needed');
  assert.ok(Number(after) > Number(before), `nodes rise when the CPU ratio drops (${before} -> ${after})`);
  const base = wm.azureLocal.size(wm.azureLocal.defaults);
  const two = wm.azureLocal.size({ ...wm.azureLocal.defaults, resiliency: 'two' });
  assert.ok(two.needRawTb < base.needRawTb, 'two way mirror needs less raw storage');
  for (const key of ['migration.name', 'migration.state', 'migration.targetCluster', 'migration.instanceType']) {
    assert.equal(wm.coverage[key].hit, wm.coverage[key].seen, `${key} matched every record`);
  }
});
