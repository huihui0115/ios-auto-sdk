const assert = require('node:assert/strict');
const test = require('node:test');
const { buildDeviceHealth, readDeviceHealth, healthReportText } = require('../device-health');
const info = { systemVersion: '15.8.5', sdkVersion: '1.41.0', runtimeHealth: { schemaVersion: 1,
  lowMemoryProfile: true, decodedImageBudgetMiB: 16, thermalState: 'nominal', lowPowerMode: false,
  appState: 'active', running: false, backgroundPolicy: 'finite', backgroundLeaseActive: false } };
const caps = { interruptibleScripts: false, cooperativeCancellation: true,
  automation: { screenshot: true, nodes: true, click: true, crossApp: true } };
const text = (value = info, capabilities = caps) => healthReportText(buildDeviceHealth(value, capabilities, 0));

test('health report shows low-memory protection and distinguishes claims from real-device acceptance', () => {
  const report = buildDeviceHealth(info, caps, 0);
  assert.equal(report.warnings.length, 0);
  assert.match(text(), /低内存机型保护已启用/); assert.match(text(), /16 MiB/);
  assert.match(text(), /声明支持，未实机验证/); assert.match(text(), /协作式停止/);
  assert.match(text(), /非实机验收/); assert.match(text(), /1970-01-01/);
});
test('legacy and future schemas report unknown, never successful protection', () => {
  for (const value of [null, [], {}, { runtimeHealth: { schemaVersion: 2, lowMemoryProfile: true } }]) {
    assert.match(text(value), /未提供可识别/); assert.doesNotMatch(text(value), /低内存机型保护已启用/);
  }
});
test('memory, thermal and background exits explain how to recover without replaying actions', () => {
  for (const [reason, pattern] of [['memoryPressure', /缩小截图/], ['thermalPressure', /冷却手机/], ['backgroundExpired', /避免重复操作/]]) {
    assert.match(text({ ...info, runtimeHealth: { ...info.runtimeHealth, lastRun: { reasonCode: reason } } }), pattern);
  }
});
test('hot background device without a lease produces actionable warnings', () => {
  const value = { ...info, runtimeHealth: { ...info.runtimeHealth, appState: 'background', thermalState: 'serious', running: true } };
  assert.match(text(value), /返回 App/); assert.match(text(value), /冷却/); assert.match(text(value), /运行中/);
});
test('unknown booleans and inherited property names never become verified capabilities', () => {
  const value = { runtimeHealth: { schemaVersion: 1, lowMemoryProfile: 'false', thermalState: 'constructor', lastRun: { reasonCode: '__proto__' } } };
  const result = text(value, { automation: { nodes: 'true', click: false } });
  assert.doesNotMatch(result, /function|Object|低内存机型保护已启用|声明支持/);
  assert.match(result, /点击当前不可用/); assert.match(result, /节点能力：未提供/);
});
test('copied diagnostics exclude arbitrary phone, error, script, URL and credential data', () => {
  const raw = JSON.parse(JSON.stringify(info));
  raw.token = raw.name = raw.deviceId = raw.url = 'SECRET'; raw.systemVersion = '<img>SECRET';
  raw.runtimeHealth.lastRun = { reasonCode: 'SECRET', error: 'SECRET', script: 'SECRET' };
  assert.doesNotMatch(text(raw, { ...caps, token: 'SECRET' }), /SECRET|<img>/);
  assert.match(healthReportText(buildDeviceHealth(info, caps, Infinity)), /1970-01-01/);
  assert.match(healthReportText(buildDeviceHealth(info, caps, 1e20)), /1970-01-01/);
});
test('one manual check uses only two read-only requests and forwards cancellation', async () => {
  const calls = [], controller = new AbortController();
  const report = await readDeviceHealth(async (payload, options) => {
    calls.push(payload.type); assert.equal(options.signal, controller.signal);
    return { ok: true, [payload.type]: payload.type === 'deviceInfo' ? info : caps };
  }, { signal: controller.signal });
  assert.deepEqual(calls, ['deviceInfo', 'capabilities']); assert.equal(report.warnings.length, 0);
});
test('cancelled checks do not start another request or accept late data', async () => {
  const controller = new AbortController(), calls = [];
  await assert.rejects(readDeviceHealth(async payload => {
    calls.push(payload.type); controller.abort(); return { ok: true, deviceInfo: info };
  }, { signal: controller.signal }), /cancelled/);
  assert.deepEqual(calls, ['deviceInfo']);
  await assert.rejects(readDeviceHealth(() => assert.fail('must not request'), { signal: controller.signal }), /cancelled/);
});
test('malformed diagnostics and device errors are not copied to the user', async () => {
  for (const response of [null, { ok: true, deviceInfo: [] }, { ok: false, error: 'SECRET' }]) {
    await assert.rejects(readDeviceHealth(async () => response), error => !error.message.includes('SECRET'));
  }
});
