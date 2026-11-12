import assert from 'node:assert/strict';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { JSDOM } from 'jsdom';
import { buildReport } from './build-report.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const template = root + 'src/waypoint/template/waypoint.html';
const sample = root + 'samples/manifest-export';

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
