const assert = require('node:assert/strict');
const test = require('node:test');
const { CoalescingRunner } = require('../coalescing-runner');

test('requests made while a task is running are coalesced into one follow-up run', async () => {
  const releases = [];
  let calls = 0;
  const runner = new CoalescingRunner(async () => {
    calls += 1;
    await new Promise(resolve => releases.push(resolve));
  });

  const first = runner.request();
  runner.request();
  runner.request();
  assert.equal(calls, 1);
  releases.shift()();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls, 2);
  releases.shift()();
  assert.equal(await first, true);
  assert.equal(calls, 2);
});

test('dispose drops queued work and rejects no callers', async () => {
  let release;
  let calls = 0;
  const runner = new CoalescingRunner(async () => {
    calls += 1;
    await new Promise(resolve => { release = resolve; });
  });

  const running = runner.request();
  runner.request();
  runner.dispose();
  release();
  assert.equal(await running, true);
  assert.equal(await runner.request(), false);
  assert.equal(calls, 1);
});

test('cancelPending keeps the runner reusable after dropping a queued refresh', async () => {
  const releases = [];
  let calls = 0;
  const runner = new CoalescingRunner(async () => {
    calls += 1;
    await new Promise(resolve => releases.push(resolve));
  });

  const first = runner.request();
  runner.request();
  runner.cancelPending();
  releases.shift()();
  await first;
  assert.equal(calls, 1);

  const next = runner.request();
  assert.equal(calls, 2);
  releases.shift()();
  await next;
  assert.equal(calls, 2);
});
