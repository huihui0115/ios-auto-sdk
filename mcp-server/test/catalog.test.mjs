import test from 'node:test';
import assert from 'node:assert/strict';
import { catalog, getApi, searchApi } from '../catalog.mjs';

test('real declarations, aliases, overloads and Chinese search are available', () => {
  assert.ok(searchApi('小白点', 20).results.some(r => r.name === 'device.setAssistiveTouchEnabled'));
  assert.ok(searchApi('VPN').results.length);
  assert.ok(searchApi('device.setAssistiveTouchEnabled').results[0].name === 'device.setAssistiveTouchEnabled');
  const api = getApi('device.setAssistiveTouchEnabled');
  assert.match(api.signatures[0].signature, /enabled: boolean/);
  assert.match(JSON.stringify(api.documents), /allowSystemControl/);
  assert.ok(getApi('action.sleep').found);
  assert.ok(getApi('auto.sleep').found);
  assert.ok(getApi('AutoSelectorBuilder.findOne').found);
  assert.equal(getApi('AutoSelectorBuilder.findOne').kind, 'instance');
  assert.match(getApi('AutoNodeObject').type.declaration, /click\(/);
  assert.ok(getApi('click').signatures.length >= 1);
});

test('all generated names are resolvable without inventing undocumented examples', () => {
  for (const entry of catalog.callables) assert.equal(getApi(entry.name).found, true, entry.name);
  for (const type of catalog.types) assert.equal(getApi(type.name).found, true, type.name);
  for (const doc of catalog.documents) assert.equal(getApi(doc.id).documents[0].sig, doc.sig);
  for (const name of ['device.turnOnEverything', '__proto__', 'constructor', '../../.env']) assert.equal(getApi(name).found, false);
  assert.equal(searchApi('not_a_real_autosdk_api').total, 0);
  assert.equal(searchApi('   ').total, 0);
});

test('search pagination is stable and combines terms', () => {
  const first = searchApi('device', 3), next = searchApi('device', 3, first.nextOffset);
  assert.equal(first.results.length, 3);
  assert.equal(next.results.length, 3);
  assert.ok(!first.results.some(a => next.results.some(b => b.name === a.name)));
  assert.ok(searchApi('device 小白点').results.length);
  assert.equal(searchApi('device zzz_not_found').results.length, 0);
});
