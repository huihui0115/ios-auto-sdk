import test from 'node:test';
import assert from 'node:assert/strict';
import { createValidator, MAX_SCRIPT_LENGTH } from '../validator.mjs';

async function check(code, language) {
  const validator = createValidator();
  try { return await validator.validate(code, language); } finally { validator.close(); }
}
test('valid JavaScript with actual API and ES2017 library passes', async () => {
  const result = await check('function main() { const info = device.getDeviceInfo(); logd(JSON.stringify(info)); device.setAssistiveTouchEnabled(false); sleep(100); } main();');
  assert.equal(result.valid, true, JSON.stringify(result));
  assert.equal(result.executed, false);
});
test('unknown function, wrong parameter, unknown module member and syntax fail', async () => {
  for (const code of ['device.nonexistentMethod();', 'device.setAssistiveTouchEnabled("yes");', 'clickPoint("x", 1);', 'totallyFakeAPI();', 'const x = ;']) {
    const result = await check(code);
    assert.equal(result.valid, false, code);
    assert.ok(result.diagnostics.some(d => d.severity === 'error' && d.line >= 1));
  }
});
test('valid TS is checked but explicitly requires transpilation', async () => {
  const result = await check('const enabled: boolean = false; device.setAssistiveTouchEnabled(enabled);', 'typescript');
  assert.equal(result.valid, true, JSON.stringify(result));
  assert.equal(result.requiresTranspilation, true);
  assert.equal((await check('const x: number = "wrong";', 'typescript')).valid, false);
});
test('no Node, DOM, imports, references or compiler-suppression escapes', async () => {
  for (const code of ['require("node:fs").readFileSync(".env");', 'document.title;', 'process.env;',
    'import x from "./secret.js";', 'import("https://example.com/evil.js");', 'export const x = 1;',
    '/// <reference path="../../secret.d.ts" />\nlogd("hi");',
    '/// <reference lib="dom" />\ndocument.title;', '// @ts-nocheck\ndevice.notReal();', '// @ts-ignore\ndevice.notReal();']) {
    assert.equal((await check(code)).valid, false, code);
  }
});
test('never executes submitted code and makes unchecked calls visible', async () => {
  const result = await check('while (true) {}\nthrow new Error("must not run");');
  assert.equal(result.valid, true);
  assert.equal(result.executed, false);
  const warning = await check('const x: any = device; x.fake();', 'typescript');
  assert.equal(warning.status, 'warnings');
  assert.ok(warning.diagnostics.some(d => d.code === 'UNCHECKED_CALL'));
});
test('oversize, cancellation, busy rejection and recovery are bounded', async () => {
  const validator = createValidator();
  await assert.rejects(validator.validate('x'.repeat(MAX_SCRIPT_LENGTH + 1)), /65,536/);
  await assert.rejects(validator.validate(' '));
  const controller = new AbortController();
  const pending = validator.validate('logd("ok");', 'javascript', controller.signal);
  const cancelled = assert.rejects(pending, /cancelled/);
  await assert.rejects(validator.validate('logd("busy");'), /另一份/);
  controller.abort(); await cancelled;
  assert.equal((await validator.validate('logd("recovered");')).valid, true);
  validator.close(); await assert.rejects(validator.validate('logd("no");'), /closed/);
});
test('timeout reports no conclusion rather than a clean script', async () => {
  const validator = createValidator({ timeoutMs: 1 });
  try { await assert.rejects(validator.validate('logd("timeout");'), /超时/); } finally { validator.close(); }
});
test('diagnostics are bounded and prioritize real errors over many warnings', async () => {
  const result = await check(Array.from({ length: 70 }, (_, i) => `const x${i}: any = device; x${i}.fake();`).join('\n') + '\ndevice.notReal();', 'typescript');
  assert.equal(result.valid, false);
  assert.equal(result.truncated, true);
  assert.equal(result.diagnostics.length, 50);
  assert.equal(result.diagnostics[0].severity, 'error');
});
