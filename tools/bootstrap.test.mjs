#!/usr/bin/env node
/**
 * Regression tests for the JavaScript bootstrap embedded in
 * AutoBootstrapScript.m. Runs the exact bootstrap source in a Node vm with a
 * mock bridge so API behavior can be verified on any platform (CI included).
 */
import test from 'node:test';
import assert from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import vm from 'node:vm';

const root = resolve(import.meta.dirname, '..');

function loadBootstrap() {
  const source = readFileSync(resolve(root, 'Sources/AutoSDK/AutoBootstrapScript.m'), 'utf8');
  const chunks = [];
  const re = /"((?:[^"\\]|\\.)*)"/g;
  re.lastIndex = source.indexOf('return @');
  let match;
  while ((match = re.exec(source))) chunks.push(match[1]);
  const raw = chunks.join('');
  return raw.replace(/\\(.)/g, (_, ch) => {
    if (ch === 'n') return '\n';
    if (ch === 't') return '\t';
    if (ch === 'r') return '\r';
    return ch;
  });
}

function createSandbox() {
  const files = {};
  const store = {};
  const calls = {
    native: [], file: [], storage: [], http: [], device: [], app: [],
    touch: [], clickPoint: [], click: [], swipe: [], sleep: [], ocr: [], screenshot: [],
  };
  const logs = [];
  let virtualNow = 0;
  let sleepRejected = false;
  const bridge = {
    invokeIsStopped: () => false,
    invokeSleep: (ms) => {
      calls.sleep.push(ms);
      if (sleepRejected) return false;
      virtualNow += Math.max(0, Number(ms) || 0);
      return true;
    },
    invokeFile: (data) => {
      calls.file.push(data);
      switch (data.operation) {
        case 'sandboxDir': return '/sandbox';
        case 'resolvePath': return '/sandbox/' + String(data.path || '').replace(/^\/+/, '');
        case 'exists': return Object.prototype.hasOwnProperty.call(files, data.path);
        case 'readText': return Object.prototype.hasOwnProperty.call(files, data.path) ? files[data.path] : null;
        case 'readBase64': return Buffer.from(files[data.path] ?? '', 'utf8').toString('base64');
        case 'readLines': return String(files[data.path] ?? '').split('\n').filter((line, i, all) => i < all.length - 1 || line !== '');
        case 'writeText': files[data.path] = String(data.text ?? ''); return true;
        case 'writeBase64': files[data.path] = Buffer.from(String(data.text ?? ''), 'base64').toString('utf8'); return true;
        case 'appendText': files[data.path] = (files[data.path] ?? '') + String(data.text ?? ''); return true;
        case 'list': return [{ name: 'a.txt', type: 'file', path: data.path + '/a.txt' }];
        case 'mkdir': return true;
        case 'remove': delete files[data.path]; return true;
        case 'copy': files[data.destination] = files[data.path]; return true;
        case 'move': files[data.destination] = files[data.path]; delete files[data.path]; return true;
        default: return { error: 'unhandled file operation ' + data.operation };
      }
    },
    invokeStorage: (data) => {
      calls.storage.push(data);
      const name = String(data.name ?? '');
      const table = store[name] ?? (store[name] = {});
      switch (data.operation) {
        case 'keys': return Object.keys(table);
        case 'all': return Object.assign({}, table);
        case 'put': table[String(data.key)] = data.value; return true;
        case 'get': return Object.prototype.hasOwnProperty.call(table, String(data.key)) ? table[String(data.key)] : data.defaultValue;
        case 'remove': delete table[String(data.key)]; return true;
        case 'contains': return Object.prototype.hasOwnProperty.call(table, String(data.key));
        case 'clear': for (const key of Object.keys(table)) delete table[key]; return true;
        default: return null;
      }
    },
    invokeHTTP: (data) => {
      calls.http.push(data);
      return { ok: true, status: 200, json: { url: data.url, method: data.method, parseJson: !!data.parseJson }, text: 'ok' };
    },
    invokeDevice: (data) => {
      calls.device.push(data);
      switch (data.operation) {
        case 'info': return { width: 390, height: 844, scale: 3, model: 'iPhone', osVersion: '17.4', name: 'Test iPhone', battery: 80, charging: true, orientation: 'portrait' };
        case 'screenWidth': return 390;
        case 'screenHeight': return 844;
        case 'scale': return 3;
        case 'model': return 'iPhone';
        case 'osVersion': return '17.4';
        case 'name': return 'Test iPhone';
        case 'battery': return 80;
        case 'isCharging': return true;
        case 'orientation': return 'portrait';
        case 'clipboardGet': return 'clipboard-value';
        case 'clipboardSet': return true;
        case 'brightnessGet': return 0.6;
        case 'brightnessSet': return true;
        case 'volumeGet': return 0.4;
        case 'vibrate': return true;
        case 'memory': return { free: 100, total: 1000 };
        default: return null;
      }
    },
    invokeApp: (data) => {
      calls.app.push(data);
      if (data.operation === 'state') return 4;
      return true;
    },
    invokeTouch: (data) => { calls.touch.push(data); return true; },
    invokeClickPoint: (data) => { calls.clickPoint.push(data); return true; },
    invokeClick: (selector) => { calls.click.push(selector); return true; },
    invokeDoubleClickPoint: () => true,
    invokeLongClick: () => true,
    invokeSwipe: (data) => { calls.swipe.push(data); return true; },
    invokeInput: () => true,
    invokeGetText: () => 'sample text',
    invokeScreenshot: () => { calls.screenshot.push(1); return 'png-data'; },
    invokeFindImage: () => ({ match: true, x: 11, y: 22, width: 5, height: 5 }),
    invokeFindColor: () => ({ match: true, x: 11, y: 22 }),
    invokePixelColor: () => ({ red: 1, green: 2, blue: 3 }),
    invokeCompareColors: () => true,
    invokeFindMultiColor: () => ({ match: true, x: 11, y: 22 }),
    invokeOCR: (region) => { calls.ocr.push(region); return [{ text: 'hello', confidence: 0.9 }]; },
    invokeExists: () => true,
    invokeFindElement: () => ({ handle: 'h1' }),
    invokeFindElements: () => [{ handle: 'h1' }],
    invokeWaitFor: () => true,
    invokeGetAttribute: () => 'attribute-value',
    invokeGetBounds: () => ({ x: 10, y: 20, width: 100, height: 50, centerX: 60, centerY: 45 }),
    invokeGetChildren: () => [{ handle: 'h2' }],
    invokeGetParent: () => ({ handle: 'h0' }),
    invokeScrollIntoView: () => true,
    invokeCapabilities: () => ({ click: true }),
    invokeMedia: () => true,
    invokeNative: (data) => { calls.native.push(data); return true; },
  };
  const consoleBridge = {
    log: (value) => logs.push(['log', value]),
    warn: (value) => logs.push(['warn', value]),
    error: (value) => logs.push(['error', value]),
  };
  return {
    bridge, consoleBridge, calls, logs, files, store,
    clock: { now: () => virtualNow },
    setSleepRejected: (value) => { sleepRejected = value; },
  };
}

function boot() {
  const state = createSandbox();
  const virtualDate = class extends Date {
    static now() { return state.clock.now(); }
  };
  const sandbox = { __bridge: state.bridge, __console: state.consoleBridge, Date: virtualDate };
  vm.createContext(sandbox);
  const drainTimers = vm.runInContext(loadBootstrap(), sandbox);
  return { sandbox, ...state, drainTimers };
}

test('bootstrap installs global facades', () => {
  const { sandbox } = boot();
  for (const key of ['auto', 'console', 'file', 'storages', 'device', 'http', 'image', 'media', 'app', 'metrics', 'base64']) {
    assert.ok(sandbox[key] != null, `expected global ${key}`);
  }
  assert.equal(typeof sandbox.setTimeout, 'function');
  assert.equal(typeof sandbox.clearTimeout, 'function');
  assert.equal(typeof sandbox.setInterval, 'function');
  assert.equal(typeof sandbox.setScreenMetrics, 'function');
  assert.equal(typeof sandbox.getScreenMetrics, 'function');
});

test('base64 encode/decode handles padding, url-safe, Chinese and emoji', () => {
  const { sandbox } = boot();
  assert.equal(sandbox.base64.encode('hello'), 'aGVsbG8=');
  assert.equal(sandbox.base64.decode('aGVsbG8='), 'hello');
  assert.equal(sandbox.base64.decode('aGVsbG8'), 'hello'); // no padding
  assert.equal(sandbox.base64.decode('5L2g5aW9'), '你好'); // Chinese
  assert.equal(sandbox.base64.decode('aGVsbG8_Pw=='), 'hello??'); // url-safe _ -> /
  const emoji = '😀🎉';
  assert.equal(sandbox.base64.decode(sandbox.base64.encode(emoji)), emoji);
  assert.equal(sandbox.base64.decode('aGVsbG8!!!'), 'hello'); // illegal chars stripped
});

test('randomInt: single-argument, equal bounds, reversed bounds', () => {
  const { sandbox } = boot();
  assert.equal(sandbox.randomInt(0, 0), 0);
  assert.equal(sandbox.randomInt(3, 3), 3);
  assert.equal(sandbox.random(5) >= 0 && sandbox.random(5) <= 5, true); // random(5) => 0..5 (closed)
  for (let i = 0; i < 50; i += 1) {
    const value = sandbox.randomInt(10, 1); // reversed -> 1..10
    assert.ok(value >= 1 && value <= 10, `expected 1..10 got ${value}`);
  }
});

test('uuid produces version-4 format', () => {
  const { sandbox } = boot();
  const uuid = sandbox.uuid();
  assert.match(uuid, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.equal(sandbox.uniqueId().length, 36);
});

test('screen metrics set/get/point scaling', () => {
  const { sandbox } = boot();
  assert.equal(sandbox.setScreenMetrics(0, 0), false);
  assert.equal(sandbox.setScreenMetrics(375, 812), true);
  const metrics = sandbox.getScreenMetrics();
  assert.equal(metrics.width, 375);
  assert.equal(metrics.height, 812);
  assert.equal(metrics.screenWidth, 390);
  const point = sandbox.metrics.point(187.5, 406);
  assert.equal(point.x, 195);
  assert.equal(point.y, 422);
  assert.equal(sandbox.metrics.x(375), 390);
  assert.equal(sandbox.metrics.y(812), 844);
});
test('metrics transforms reuse the cached screen size after setScreenMetrics', () => {
  const { sandbox, calls } = boot();
  sandbox.setScreenMetrics(375, 812);
  const before = calls.device.length;
  sandbox.metrics.point(187.5, 406);
  sandbox.metrics.x(375);
  sandbox.metrics.y(812);
  assert.equal(calls.device.length, before);
  const metrics = sandbox.getScreenMetrics();
  assert.equal(metrics.screenWidth, 390);
  assert.equal(metrics.screenHeight, 844);
  assert.equal(metrics.scaleX, 390 / 375);
  assert.equal(metrics.scaleY, 844 / 812);
});
test('metrics transforms are pure math before setScreenMetrics', () => {
  const { sandbox, calls } = boot();
  const before = calls.device.length;
  assert.equal(sandbox.metrics.x(5), 5);
  assert.equal(sandbox.metrics.y(7), 7);
  assert.deepEqual(sandbox.metrics.point(10, 20), { x: 10, y: 20 });
  assert.equal(calls.device.length, before);
});

test('device info and convenience accessors', () => {
  const { sandbox } = boot();
  assert.equal(sandbox.device.width(), 390);
  assert.equal(sandbox.device.height(), 844);
  assert.equal(sandbox.device.scale(), 3);
  assert.equal(sandbox.device.getModel(), 'iPhone');
  assert.equal(sandbox.device.getBattery(), 80);
  const info = sandbox.device.info();
  assert.equal(info.osVersion, '17.4');
});

test('http.getJSON and http.get pass options to the bridge', () => {
  const { sandbox, calls } = boot();
  sandbox.http.getJSON('https://example.com/api');
  assert.equal(calls.http.at(-1).method, 'GET');
  assert.equal(calls.http.at(-1).parseJson, true);
  assert.equal(calls.http.at(-1).url, 'https://example.com/api');
  sandbox.http.get('https://example.com/plain');
  assert.equal(calls.http.at(-1).method, 'GET');
  assert.equal(calls.http.at(-1).parseJson, undefined);
  sandbox.http.post('https://example.com/post', { body: 'x' });
  assert.equal(calls.http.at(-1).method, 'POST');
});

test('storage put/get/remove/contains/clear/keys', () => {
  const { sandbox } = boot();
  const store = sandbox.storages.create('cfg');
  assert.equal(store.put('name', 'autosdk'), true);
  assert.equal(store.getString('name'), 'autosdk');
  assert.equal(store.putInt('count', 7), true);
  assert.equal(store.getInt('count'), 7);
  assert.equal(store.getFloat('ratio', 0.5), 0.5);
  assert.equal(store.contains('name'), true);
  assert.deepEqual(store.keys().sort(), ['count', 'name']);
  assert.equal(store.remove('name'), true);
  assert.equal(store.contains('name'), false);
  store.clear();
  assert.deepEqual(store.keys(), []);
});

test('file read/write/exists/list/move/remove', () => {
  const { sandbox } = boot();
  const path = sandbox.file.resolvePath('notes.txt');
  assert.equal(sandbox.file.exists(path), false);
  assert.equal(sandbox.file.writeText(path, 'line1\nline2'), true);
  assert.equal(sandbox.file.readText(path), 'line1\nline2');
  assert.equal(sandbox.file.exists(path), true);
  assert.deepEqual(sandbox.file.readLines(path), ['line1', 'line2']);
  assert.equal(sandbox.file.readLine(path, 1), 'line2');
  const moved = sandbox.file.resolvePath('moved.txt');
  assert.equal(sandbox.file.move(path, moved, true), true);
  assert.equal(sandbox.file.exists(moved), true);
  assert.equal(sandbox.file.remove(moved), true);
  assert.equal(sandbox.file.exists(moved), false);
  assert.equal(sandbox.file.listDir(sandbox.file.sandboxDir()).length, 1);
});

test('timers fire via drainTimers and can be cancelled', () => {
  const { sandbox, drainTimers } = boot();
  sandbox.fired = false;
  const id = sandbox.setTimeout(() => { sandbox.fired = true; }, 5);
  assert.equal(typeof id, 'number');
  drainTimers();
  assert.equal(sandbox.fired, true);

  sandbox.fired = false;
  const cancelled = sandbox.setTimeout(() => { sandbox.fired = true; }, 1);
  sandbox.clearTimeout(cancelled);
  drainTimers();
  assert.equal(sandbox.fired, false);
});

test('setInterval repeats until cleared', () => {
  const { sandbox, drainTimers } = boot();
  sandbox.intervalFires = 0;
  let intervalId = null;
  intervalId = sandbox.setInterval(() => {
    sandbox.intervalFires += 1;
    if (sandbox.intervalFires >= 2) sandbox.clearInterval(intervalId);
  }, 1);
  drainTimers();
  assert.equal(sandbox.intervalFires, 2);
});
test('timers wait via one-shot native sleep (no 50ms JS slicing)', () => {
  const { sandbox, drainTimers, calls } = boot();
  sandbox.fired = 0;
  sandbox.setTimeout(() => { sandbox.fired += 1; }, 120);
  drainTimers();
  assert.equal(sandbox.fired, 1);
  assert.deepEqual(calls.sleep, [120]);
});

test('timers fire when the virtual clock passes their deadline', () => {
  const { sandbox, drainTimers, calls } = boot();
  sandbox.fired = 0;
  sandbox.setTimeout(() => { sandbox.fired += 1; }, 10);
  sandbox.auto.sleep(30);
  drainTimers();
  assert.equal(sandbox.fired, 1);
  assert.deepEqual(calls.sleep, [30]);
});

test('setInterval keeps interval cadence over virtual time', () => {
  const { sandbox, drainTimers } = boot();
  sandbox.ticks = 0;
  let intervalId = null;
  intervalId = sandbox.setInterval(() => {
    sandbox.ticks += 1;
    if (sandbox.ticks >= 10) sandbox.clearInterval(intervalId);
  }, 10);
  sandbox.auto.sleep(100);
  drainTimers();
  assert.equal(sandbox.ticks, 10);
});

test('drainTimers aborts the wait when the native sleep is rejected', () => {
  const { sandbox, drainTimers, setSleepRejected } = boot();
  sandbox.fired = 0;
  sandbox.setTimeout(() => { sandbox.fired += 1; }, 10);
  setSleepRejected(true);
  drainTimers();
  assert.equal(sandbox.fired, 0);
});

test('console methods are captured', () => {
  const { sandbox, logs } = boot();
  sandbox.console.log('a', { b: 1 });
  sandbox.console.warn('w');
  sandbox.console.error('e');
  assert.equal(logs[0][0], 'log');
  assert.ok(logs[0][1].includes('a'));
  assert.equal(logs[1][0], 'warn');
  assert.equal(logs[2][0], 'error');
});

test('click helpers: clickPoint, clickCenter, clickRandom, swipe', () => {
  const { sandbox, calls } = boot();
  assert.equal(sandbox.auto.clickPoint(10, 20), true);
  assert.deepEqual(calls.clickPoint.at(-1), { x: 10, y: 20 });
  assert.equal(sandbox.auto.clickCenter({ handle: 'h1' }), true);
  assert.deepEqual(calls.clickPoint.at(-1), { x: 60, y: 45 });
  assert.equal(sandbox.auto.clickRandom({ handle: 'h1' }), true);
  const randomPoint = calls.clickPoint.at(-1);
  assert.ok(randomPoint.x >= 10 && randomPoint.x <= 110 && randomPoint.y >= 20 && randomPoint.y <= 70);
  sandbox.auto.swipe(1, 2, 3, 4, 500);
  assert.deepEqual(calls.swipe.at(-1), { x1: 1, y1: 2, x2: 3, y2: 4, duration: 500 });
});

test('tree helpers: getChild, getSiblings, getPreviousSiblings', () => {
  const { sandbox } = boot();
  assert.equal(sandbox.auto.getChild({ handle: 'p' }, 0).handle, 'h2');
  assert.deepEqual(sandbox.auto.getSiblings({ handle: 'h1' }).map((n) => n.handle), ['h2']);
  const node = { handle: 'h1' };
  const children = [{ handle: 'h1' }, { handle: 'h3' }];
  sandbox.auto.getChildren = () => children;
  sandbox.auto.getParent = () => ({ handle: 'root' });
  assert.deepEqual(sandbox.auto.getSiblings(node).map((n) => n.handle), ['h3']);
});

test('gesture: single finger normalizes W3C pointer actions', () => {
  const { sandbox, calls } = boot();
  const ok = sandbox.auto.gesture([
    { type: 'down', x: 10, y: 20 },
    { type: 'move', x: 30, y: 40, duration: 100 },
    { type: 'up' },
  ]);
  assert.equal(ok, true);
  assert.equal(calls.touch.length, 1);
  assert.deepEqual(calls.touch[0].fingers, [[
    { type: 'pointerMove', duration: 0, x: 10, y: 20 },
    { type: 'pointerDown', button: 0 },
    { type: 'pointerMove', duration: 100, x: 30, y: 40 },
    { type: 'pointerUp', button: 0 },
  ]]);
});

test('gesture: multiGesture runs several fingers, pinch produces two tracks', () => {
  const { sandbox, calls } = boot();
  assert.equal(sandbox.auto.multiGesture([
    [{ type: 'down', x: 0, y: 0 }, { type: 'up' }],
    [{ type: 'down', x: 100, y: 100 }, { type: 'up' }],
  ]), true);
  assert.equal(calls.touch.at(-1).fingers.length, 2);
  assert.equal(sandbox.auto.pinch(100, 100, 2, 300), true);
  const fingers = calls.touch.at(-1).fingers;
  assert.equal(fingers.length, 2);
  assert.equal(fingers[0][1].type, 'pointerDown');
  assert.equal(fingers[0][2].duration, 300);
  assert.ok(fingers[0][2].x < 100 && fingers[1][2].x > 100);
  assert.throws(() => sandbox.auto.gesture([]), /at least one/);
});

test('app helpers and clipboard/brightness/volume/vibrate route to bridge', () => {
  const { sandbox, calls } = boot();
  sandbox.auto.launchApp('com.example.app');
  assert.deepEqual(calls.app.at(-1), { operation: 'launch', bundleId: 'com.example.app' });
  sandbox.auto.openURL('https://example.com');
  assert.deepEqual(calls.app.at(-1), { operation: 'openURL', url: 'https://example.com' });
  assert.equal(sandbox.auto.getClipboard(), 'clipboard-value');
  sandbox.auto.setClipboard('new');
  assert.deepEqual(calls.device.at(-1), { operation: 'clipboardSet', text: 'new' });
  assert.equal(sandbox.auto.getBrightness(), 0.6);
  sandbox.auto.setBrightness(0.8);
  assert.equal(sandbox.auto.getVolume(), 0.4);
  sandbox.auto.vibrate(300);
  assert.deepEqual(calls.device.at(-1), { operation: 'vibrate', duration: 300 });
});

test('unknown auto.* methods fall back to invokeNative', () => {
  const { sandbox, calls } = boot();
  sandbox.auto.someNativeThing('a', 2);
  assert.deepEqual(calls.native.at(-1), { name: 'someNativeThing', arguments: ['a', 2] });
});

test('bootstrap stays small and parses quickly', () => {
  const source = loadBootstrap();
  // Guards the embedded runtime against unbounded growth: 23 KB today.
  assert.ok(source.length <= 64 * 1024, `bootstrap grew to ${source.length} bytes`);
  const started = process.hrtime.bigint();
  const sandbox = { __bridge: { invokeIsStopped: () => false, invokeSleep: () => true } };
  vm.runInNewContext(source, sandbox, { timeout: 5000 });
  const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6;
  // Generous ceiling: catches accidental O(n^2) bootstrap growth.
  assert.ok(elapsedMs < 1000, `bootstrap took ${elapsedMs.toFixed(1)} ms to parse+run`);
});
test('stopped scripts throw Script cancelled', () => {
  const { sandbox, bridge } = boot();
  bridge.invokeIsStopped = () => true;
  assert.throws(() => sandbox.auto.sleep(1), /Script cancelled/);
  assert.throws(() => sandbox.file.readText('/x'), /Script cancelled/);
});