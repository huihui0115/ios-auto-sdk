const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const test = require('node:test');
const { terminateOwnedProcess } = require('../process-lifecycle');

function child(pid = 1234) {
  return {
    pid,
    exitCode: null,
    killed: false,
    killCalls: 0,
    kill() { this.killed = true; this.killCalls += 1; return true; }
  };
}

test('Windows termination targets only the owned process tree without a shell', () => {
  const calls = [];
  const killer = new EventEmitter();
  const target = child(4321);
  const result = terminateOwnedProcess(target, {
    platform: 'win32',
    spawn(command, args, options) {
      calls.push({ command, args, options });
      return killer;
    }
  });

  assert.equal(result, true);
  assert.deepEqual(calls[0].args, ['/PID', '4321', '/T', '/F']);
  assert.equal(calls[0].command, 'taskkill');
  assert.equal(calls[0].options.shell, false);
  assert.equal(target.killCalls, 0);
  assert.equal(terminateOwnedProcess(target, { platform: 'win32', spawn: () => killer }), false);
  assert.equal(calls.length, 1);
});

test('a failed Windows tree terminator falls back to the direct owned child', () => {
  const killer = new EventEmitter();
  const target = child(4321);
  terminateOwnedProcess(target, { platform: 'win32', spawn: () => killer });
  killer.emit('close', 1);

  assert.equal(target.killCalls, 1);
});

test('a failed direct termination can be retried', () => {
  const target = child();
  target.kill = function kill() {
    this.killCalls += 1;
    return this.killCalls > 1;
  };

  assert.equal(terminateOwnedProcess(target, { platform: 'linux' }), false);
  assert.equal(terminateOwnedProcess(target, { platform: 'linux' }), true);
  assert.equal(target.killCalls, 2);
});

test('a synchronous taskkill launch failure returns the direct-kill result', () => {
  const target = child(4321);
  target.kill = function kill() { this.killCalls += 1; return false; };

  assert.equal(terminateOwnedProcess(target, {
    platform: 'win32',
    spawn() { throw new Error('taskkill unavailable'); }
  }), false);
  assert.equal(target.killCalls, 1);
});

test('non-Windows and missing-PID termination never invokes taskkill', () => {
  let spawnCalls = 0;
  const spawnProcess = () => { spawnCalls += 1; };
  const linuxChild = child(111);
  const missingPidChild = child();
  missingPidChild.pid = undefined;

  assert.equal(terminateOwnedProcess(linuxChild, { platform: 'linux', spawn: spawnProcess }), true);
  assert.equal(terminateOwnedProcess(missingPidChild, { platform: 'win32', spawn: spawnProcess }), true);
  assert.equal(spawnCalls, 0);
});
