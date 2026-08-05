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
    touch: [], clickPoint: [], click: [], swipe: [], sleep: [], ocr: [], screenshot: [], findColorEx: [], findNotColor: [], media: [],
    execAsync: [],
    execOp: [],
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
        case 'imageSize': return { width: 390, height: 844, pixelWidth: 1170, pixelHeight: 2532, scale: 3 };
        case 'md5File': return 'd41d8cd98f00b204e9800998ecf8427e';
        case 'sha1File': return 'da39a3ee5e6b4b0d3255bfef95601890afd80709';
        case 'stat': return Object.prototype.hasOwnProperty.call(files, data.path)
          ? { name: data.path.split('/').pop(), path: data.path, isDirectory: false, isFile: true, size: String(files[data.path] ?? '').length, modifiedAtMs: 1700000000000 }
          : null;
        case 'mkdir': return true;
        case 'remove': delete files[data.path]; return true;
        case 'copy': files[data.destination] = files[data.path]; return true;
        case 'move': files[data.destination] = files[data.path]; delete files[data.path]; return true;
        case 'zip': files[data.destination] = 'zip:' + (data.sources || []).join(','); return data.destination;
        case 'unzip': return true;
        case 'readFileInZip': return 'hello from zip';
        case 'readExcelAllRow': return [{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }];
        case 'readExcelRow': return ['Alice', 30];
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
        case 'memory': return { totalBytes: 8000000000, freeBytes: 2000000000, appUsedBytes: 300000000 };
        case 'volumeUp': return true;
        case 'volumeDown': return true;
        case 'isScreenOn': return true;
        case 'deviceId': return 'ABCDEF12-3456-7890-ABCD-EF1234567890';
        case 'serialNo': return null;
        case 'appVersion': return '1.2.3';
        case 'packageName': return 'com.example.host';
        default: return null;
      }
    },
    invokeApp: (data) => {
      calls.app.push(data);
      if (data.operation === 'state') return 4;
      if (data.operation === 'current') return 'com.example.host';
      if (data.operation === 'appList') return [{ bundleId: 'com.example.host', name: 'Host' }];
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
    invokeScreenshotRegion: (data) => { calls.screenshot.push(data); return 'region-png'; },
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
    invokeMedia: (data) => { calls.media.push(data); return true; },
    invokeFindColorEx: (data) => { calls.findColorEx.push(data); return [{ x: 5, y: 6 }]; },
    invokeFindNotColor: (data) => { calls.findNotColor.push(data); return [{ x: 7, y: 8 }]; },
    invokeNative: (data) => {
      calls.native.push(data);
      if (data.name === 'md5') return 'md5-of-' + String(data.arguments[0]);
      if (data.name === 'sha1') return 'sha1-of-' + String(data.arguments[0]);
      if (data.name === 'playMp3') return true;
      if (data.name === 'stopMp3') return true;
      return true;
    },
    invokeExecAsync: (data) => {
      calls.execAsync.push(data);
      const id = 1000 + calls.execAsync.length;
      if (data.sync) return { result: 'sync-result-' + String(data.arguments[0]) };
      return { threadId: id };
    },
    invokeExecOp: (data) => {
      calls.execOp.push(data);
      if (data.operation === 'isFinished') return true;
      if (data.operation === 'cancel') return true;
      if (data.operation === 'stopAll') return true;
      return { threadId: data.threadId };
    },
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


test('device volume and screen-state operations forward through invokeDevice', () => {
  const { sandbox, calls } = boot();
  sandbox.device.volumeUp();
  assert.deepEqual(calls.device.at(-1), { operation: 'volumeUp' });
  sandbox.device.volumeDown();
  assert.deepEqual(calls.device.at(-1), { operation: 'volumeDown' });
  sandbox.device.isScreenOn();
  assert.deepEqual(calls.device.at(-1), { operation: 'isScreenOn' });
  assert.equal(sandbox.auto.device.volumeUp(), true);
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
  assert.equal(sandbox.device.getDeviceId(), 'ABCDEF12-3456-7890-ABCD-EF1234567890');
  assert.equal(sandbox.device.getDeviceAlias(), 'Test iPhone');
  assert.equal(sandbox.device.getSerialNo(), null);
  assert.equal(sandbox.device.getAppVersion(), '1.2.3');
  assert.equal(sandbox.device.getPackageName(), 'com.example.host');
  assert.equal(sandbox.auto.app.getAppVersion(), '1.2.3');
  assert.equal(sandbox.auto.app.getPackageName(), 'com.example.host');
  assert.equal(sandbox.getAppVersion(), '1.2.3');
  assert.equal(sandbox.getPackageName(), 'com.example.host');
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


test('file.stat and convenience accessors report size and type', () => {
  const { sandbox } = boot();
  sandbox.file.writeText('demo/a.txt', 'hello');
  const stat = sandbox.file.stat('demo/a.txt');
  assert.equal(stat.size, 5);
  assert.equal(stat.isFile, true);
  assert.equal(stat.isDirectory, false);
  assert.equal(stat.modifiedAtMs, 1700000000000);
  assert.equal(sandbox.file.getSize('demo/a.txt'), 5);
  assert.equal(sandbox.file.getModifiedTime('demo/a.txt'), 1700000000000);
  assert.equal(sandbox.file.isFile('demo/a.txt'), true);
  assert.equal(sandbox.file.isDir('demo/a.txt'), false);
  assert.equal(sandbox.file.stat('demo/missing.txt'), null);
});

test('app.current and currentApp return the foreground bundle id', () => {
  const { sandbox } = boot();
  assert.equal(sandbox.app.current(), 'com.example.host');
  assert.equal(sandbox.app.currentApp(), 'com.example.host');
  assert.equal(sandbox.currentApp(), 'com.example.host');
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

test('direction swipes compute screen-relative coordinates and seconds duration', () => {
  const { sandbox, calls } = boot();
  sandbox.auto.swipeUp();
  assert.deepEqual(calls.swipe.at(-1), { x1: 195, y1: 608, x2: 195, y2: 354, duration: 0.3 });
  sandbox.auto.swipeDown();
  assert.deepEqual(calls.swipe.at(-1), { x1: 195, y1: 236, x2: 195, y2: 490, duration: 0.3 });
  sandbox.auto.swipeLeft();
  assert.deepEqual(calls.swipe.at(-1), { x1: 281, y1: 422, x2: 164, y2: 422, duration: 0.3 });
  sandbox.auto.swipeRight();
  assert.deepEqual(calls.swipe.at(-1), { x1: 109, y1: 422, x2: 226, y2: 422, duration: 0.3 });
  sandbox.auto.swipeUp(0.8, 500);
  assert.deepEqual(calls.swipe.at(-1), { x1: 195, y1: 608, x2: 195, y2: 203, duration: 0.5 });
  assert.equal(typeof sandbox.swipeUp, 'function');
  assert.equal(typeof sandbox.swipeDown, 'function');
  assert.equal(typeof sandbox.swipeLeft, 'function');
  assert.equal(typeof sandbox.swipeRight, 'function');
  assert.equal(typeof sandbox.auto.swipeUp, 'function');
});

test('app.appList and installedApps route to invokeApp appList', () => {
  const { sandbox, calls } = boot();
  assert.deepEqual(sandbox.auto.app.appList(), [{ bundleId: 'com.example.host', name: 'Host' }]);
  assert.deepEqual(calls.app.at(-1), { operation: 'appList' });
  assert.deepEqual(sandbox.auto.app.installedApps(), [{ bundleId: 'com.example.host', name: 'Host' }]);
  assert.deepEqual(calls.app.at(-1), { operation: 'appList' });
});

test('launchAppByPrefix finds the first bundleId with the given prefix', () => {
  const { sandbox, calls } = boot();
  sandbox.auto.launchAppByPrefix('com.example');
  assert.deepEqual(calls.app.at(-1), { operation: 'launch', bundleId: 'com.example.host' });
  assert.equal(sandbox.auto.launchAppByPrefix('no.such.prefix'), false);
  assert.equal(sandbox.auto.launchAppByPrefix(''), false);
  assert.equal(typeof sandbox.launchAppByPrefix, 'function');
  assert.equal(typeof sandbox.auto.app.launchByPrefix, 'function');
});

test('screenshotRegion, childCount, randomString, drag and screen text helpers', () => {
  const { sandbox, calls } = boot();
  const region = sandbox.auto.screenshotRegion(10, 20, 100, 50);
  assert.equal(region, 'region-png');
  assert.deepEqual(calls.screenshot.at(-1), { x: 10, y: 20, width: 100, height: 50 });
  assert.equal(typeof sandbox.screenshotRegion, 'function');
  assert.equal(typeof sandbox.image.clipRegion, 'function');

  sandbox.auto.getChildren = () => [{ handle: 'a' }, { handle: 'b' }, { handle: 'c' }];
  assert.equal(sandbox.auto.childCount({ text: 'x' }), 3);
  sandbox.auto.getChildren = () => null;
  assert.equal(sandbox.auto.childCount({ text: 'x' }), 0);
  assert.equal(typeof sandbox.childCount, 'function');

  const s = sandbox.auto.randomString(12);
  assert.equal(s.length, 12);
  assert.match(s, /^[A-Za-z0-9]{12}$/);
  assert.equal(sandbox.auto.randomString(6, 'ab').replace(/[ab]/g, '').length, 0);
  assert.equal(sandbox.auto.randomCharNumber(5).length, 5);
  assert.equal(typeof sandbox.randomString, 'function');
  assert.equal(typeof sandbox.randomCharNumber, 'function');

  assert.equal(sandbox.auto.drag(10, 10, 200, 300, 700), true);
  const fingers = calls.touch.at(-1).fingers;
  assert.equal(fingers.length, 1);
  assert.equal(fingers[0][0].type, 'pointerMove');
  assert.equal(fingers[0][0].x, 10);
  assert.equal(fingers[0][1].type, 'pointerDown');
  assert.equal(fingers[0][2].type, 'pause');
  assert.equal(fingers[0][3].type, 'pointerMove');
  assert.equal(fingers[0][3].x, 200);
  assert.equal(fingers[0][3].duration, 700);
  assert.equal(fingers[0][4].type, 'pointerUp');
  assert.equal(typeof sandbox.drag, 'function');

  assert.equal(sandbox.auto.device.getScreenWidthHeightText(), '390x844');
  assert.equal(typeof sandbox.getScreenWidthHeightText, 'function');
});

test('md5/sha1 hashes and file imageSize helpers', () => {
  const { sandbox, calls } = boot();
  assert.equal(sandbox.auto.md5('hello'), 'md5-of-hello');
  assert.deepEqual(calls.native.at(-1), { name: 'md5', arguments: ['hello'] });
  assert.equal(sandbox.auto.sha1('world'), 'sha1-of-world');
  assert.equal(sandbox.md5('x'), 'md5-of-x');
  assert.equal(sandbox.sha1('y'), 'sha1-of-y');
  assert.equal(typeof sandbox.auto.md5, 'function');
  assert.equal(typeof sandbox.auto.sha1, 'function');

  assert.equal(sandbox.file.md5('demo.txt'), 'd41d8cd98f00b204e9800998ecf8427e');
  assert.equal(sandbox.auto.file.md5File('demo.txt'), 'd41d8cd98f00b204e9800998ecf8427e');
  assert.equal(sandbox.file.sha1('demo.txt'), 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
  assert.equal(sandbox.auto.file.sha1File('demo.txt'), 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
  assert.deepEqual(sandbox.file.imageSize('img.png'), { width: 390, height: 844, pixelWidth: 1170, pixelHeight: 2532, scale: 3 });
  assert.deepEqual(sandbox.image.getSize('img.png'), { width: 390, height: 844, pixelWidth: 1170, pixelHeight: 2532, scale: 3 });
});

test('findColorEx, playMp3/stopMp3 and photo authorization helpers', () => {
  const { sandbox, calls } = boot();
  const points = sandbox.auto.findColorEx('0xCDD7E9-0x101010,0xFF0000', 0.9, 10, 20, 100, 200, 5, 1);
  assert.deepEqual(points, [{ x: 5, y: 6 }]);
  assert.deepEqual(calls.findColorEx.at(-1), { colors: '0xCDD7E9-0x101010,0xFF0000', threshold: 0.9, x: 10, y: 20, ex: 100, ey: 200, limit: 5, direction: 1 });
  assert.equal(typeof sandbox.findColorEx, 'function');
  assert.equal(typeof sandbox.image.findColorEx, 'function');
  sandbox.auto.findColorEx('#00FF00', undefined, 0, 0, 0, 0, undefined, undefined);
  assert.deepEqual(calls.findColorEx.at(-1), { colors: '#00FF00', threshold: 0.9, x: 0, y: 0, ex: 0, ey: 0, limit: 10, direction: 1 });

  assert.equal(sandbox.auto.playMp3('sounds/a.mp3', 80, false, true), true);
  assert.deepEqual(calls.native.at(-1), { name: 'playMp3', arguments: ['sounds/a.mp3', 80, false, true] });
  assert.equal(sandbox.auto.playMp3('sounds/b.mp3'), true);
  assert.deepEqual(calls.native.at(-1), { name: 'playMp3', arguments: ['sounds/b.mp3', 100, false, false] });
  assert.equal(sandbox.auto.stopMp3(), true);
  assert.deepEqual(calls.native.at(-1), { name: 'stopMp3', arguments: [] });
  assert.equal(typeof sandbox.playMp3, 'function');
  assert.equal(typeof sandbox.stopMp3, 'function');

  assert.equal(sandbox.media.getPhotoAuthorizationStatus(), true);
  assert.deepEqual(calls.media.at(-1), { operation: 'photoAuthorizationStatus' });
  assert.equal(sandbox.media.requestPhotoAuthorization(), true);
  assert.deepEqual(calls.media.at(-1), { operation: 'photoAuthorizationRequest' });
  assert.equal(typeof sandbox.requestPhotoAuthorization, 'function');
  assert.equal(typeof sandbox.getPhotoAuthorizationStatus, 'function');
});
test('findNotColor and image processing pipeline', () => {
  const { sandbox, calls } = boot();
  const points = sandbox.auto.findNotColor('0x000000', 0.9, 0, 0, 0, 0, 5, 1);
  assert.deepEqual(points, [{ x: 7, y: 8 }]);
  assert.deepEqual(calls.findNotColor.at(-1), { colors: '0x000000', threshold: 0.9, x: 0, y: 0, ex: 0, ey: 0, limit: 5, direction: 1 });
  assert.equal(typeof sandbox.findNotColor, 'function');
  assert.equal(typeof sandbox.image.findNotColor, 'function');

  sandbox.image.clip('a.png', 10, 20, 100, 200, 'b.png');
  assert.deepEqual(calls.file.at(-1), { operation: 'imageProcess', path: 'a.png', sub: 'clip', destination: 'b.png', args: { x: 10, y: 20, ex: 100, ey: 200 } });
  sandbox.image.scale('a.png', 100, 200, 'c.png');
  assert.deepEqual(calls.file.at(-1), { operation: 'imageProcess', path: 'a.png', sub: 'scale', destination: 'c.png', args: { width: 100, height: 200 } });
  sandbox.image.gray('a.png', 'd.png');
  assert.deepEqual(calls.file.at(-1), { operation: 'imageProcess', path: 'a.png', sub: 'gray', destination: 'd.png' });
  sandbox.image.binaryzation('a.png', 'e.png', 150);
  assert.deepEqual(calls.file.at(-1), { operation: 'imageProcess', path: 'a.png', sub: 'binaryzation', destination: 'e.png', args: { threshold: 150 } });
  sandbox.image.rotate('a.png', 90, 'f.png');
  assert.deepEqual(calls.file.at(-1), { operation: 'imageProcess', path: 'a.png', sub: 'rotate', destination: 'f.png', args: { degrees: 90 } });
  sandbox.image.pixelAt('a.png', 5, 6);
  assert.deepEqual(calls.file.at(-1), { operation: 'imagePixelAt', path: 'a.png', args: { x: 5, y: 6 } });
  assert.deepEqual(sandbox.image.getWidth('a.png'), 390);
  assert.deepEqual(sandbox.image.getHeight('a.png'), 844);
});
test('zip / unzip / readFileInZip helpers', () => {
  const { sandbox, calls } = boot();
  const zipPath = sandbox.file.zip('backup/scripts.zip', ['data/1.txt', 'logs']);
  assert.equal(zipPath, 'backup/scripts.zip');
  assert.deepEqual(calls.file.at(-1), { operation: 'zip', destination: 'backup/scripts.zip', sources: ['data/1.txt', 'logs'], passwd: '' });
  assert.equal(sandbox.auto.file.zip('backup/a.zip', ['x.txt']), 'backup/a.zip');
  assert.equal(typeof sandbox.zip, 'function');

  assert.equal(sandbox.file.unzip('backup/scripts.zip', 'backup/out'), true);
  assert.deepEqual(calls.file.at(-1), { operation: 'unzip', path: 'backup/scripts.zip', destination: 'backup/out', passwd: '' });
  assert.equal(typeof sandbox.unzip, 'function');

  assert.equal(sandbox.file.readFileInZip('backup/scripts.zip', 'data/1.txt'), 'hello from zip');
  assert.deepEqual(calls.file.at(-1), { operation: 'readFileInZip', path: 'backup/scripts.zip', entry: 'data/1.txt', passwd: '' });
  assert.equal(typeof sandbox.readFileInZip, 'function');

  sandbox.file.zip('with-pass.zip', ['a.txt'], 'secret');
  assert.deepEqual(calls.file.at(-1), { operation: 'zip', destination: 'with-pass.zip', sources: ['a.txt'], passwd: 'secret' });
});

test('readExcelAllRow / readExcelRow helpers', () => {
  const { sandbox, calls } = boot();
  const all = sandbox.file.readExcelAllRow('data/books.xlsx');
  assert.deepEqual(all, [{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }]);
  assert.deepEqual(calls.file.at(-1), { operation: 'readExcelAllRow', path: 'data/books.xlsx', sheetIndex: 0 });

  const row = sandbox.file.readExcelRow('data/books.xlsx', 1, 2);
  assert.deepEqual(row, ['Alice', 30]);
  assert.deepEqual(calls.file.at(-1), { operation: 'readExcelRow', path: 'data/books.xlsx', sheetIndex: 1, row: 2 });

  assert.equal(sandbox.auto.file.readExcelAllRow('data/books.xlsx', 2).length, 2);
  assert.deepEqual(calls.file.at(-1), { operation: 'readExcelAllRow', path: 'data/books.xlsx', sheetIndex: 2 });
});

test('execAsync / execSync / thread handle and utils helpers', () => {
  const { sandbox, calls } = boot();
  const thread = sandbox.auto.execAsync(function () { return 42; }, 1, 'x');
  assert.ok(thread != null);
  assert.equal(thread.isFinished(), true);
  assert.deepEqual(calls.execOp.at(-1), { operation: 'isFinished', threadId: 1001 });
  thread.cancel();
  assert.deepEqual(calls.execOp.at(-1), { operation: 'cancel', threadId: 1001 });
  assert.deepEqual(thread.join(), { threadId: 1001 });
  assert.equal(typeof sandbox.execAsync, 'function');
  assert.equal(typeof sandbox.cancelThread, 'function');

  assert.equal(sandbox.execSync(function () { return 1; }, 'hello'), 'sync-result-hello');
  assert.deepEqual(calls.execAsync.at(-1), { source: 'function () { return 1; }', arguments: ['hello'], sync: true });

  sandbox.stopAllThreads();
  assert.deepEqual(calls.execOp.at(-1), { operation: 'stopAll' });
  assert.equal(sandbox.isCancelled(), false);

  assert.equal(sandbox.longClickPoint(100, 200, 500), true);
  assert.equal(calls.touch.at(-1).fingers[0][0].type, 'pointerMove');
  sandbox.getRangeInt(1, 10);
  const ratio = sandbox.getRatio(100);
  assert.equal(ratio, true);
  assert.deepEqual(sandbox.getOneNodeInfo({ text: 'x' }), { handle: 'h1' });
  assert.deepEqual(sandbox.getNodeInfo({ text: 'x' }), { handle: 'h1' });
  assert.equal(typeof sandbox.auto.getRangeInt, 'function');
  assert.equal(typeof sandbox.auto.getRatio, 'function');
  assert.equal(typeof sandbox.auto.getOneNodeInfo, 'function');
  assert.equal(typeof sandbox.auto.getNodeInfo, 'function');
});

test('toPinYin, stripUtf8Bom, fromUnicode, screenDraw, floatBall and node keep helpers', () => {
  const { sandbox, calls } = boot();
  assert.equal(sandbox.toPinYin('你好'), true);
  assert.deepEqual(calls.native.at(-1), { name: 'toPinYin', arguments: ['你好'] });
  assert.equal(sandbox.stripUtf8Bom('\uFEFFabc'), 'abc');
  assert.equal(sandbox.stripUtf8Bom('abc'), 'abc');
  assert.equal(sandbox.fromUnicode('\\u4f60\\u597d'), '你好');
  assert.equal(sandbox.strings.toPinYin('x'), true);
  assert.equal(typeof sandbox.strings.stripUtf8Bom, 'function');
  assert.equal(typeof sandbox.strings.fromUnicode, 'function');

  const token = 't1';
  assert.equal(sandbox.screenDraw.init(), true);
  assert.deepEqual(calls.native.at(-1), { name: 'screenDrawInit', arguments: [] });
  assert.equal(sandbox.screenDraw.setBorderWidth(token, 4), true);
  assert.deepEqual(calls.native.at(-1), { name: 'screenDrawSetBorderWidth', arguments: [token, 4] });
  assert.equal(sandbox.screenDraw.setBorderColor(token, '#FF0000'), true);
  assert.deepEqual(calls.native.at(-1), { name: 'screenDrawSetBorderColor', arguments: [token, '#FF0000'] });
  assert.equal(sandbox.screenDraw.setTitle(token, '目标'), true);
  assert.deepEqual(calls.native.at(-1), { name: 'screenDrawSetTitle', arguments: [token, '目标'] });
  assert.equal(sandbox.screenDraw.show(token, 1, 2, 3, 4), true);
  assert.deepEqual(calls.native.at(-1), { name: 'screenDrawShow', arguments: [token, 1, 2, 3, 4] });
  assert.equal(sandbox.screenDraw.move(token, 5, 6), true);
  assert.deepEqual(calls.native.at(-1), { name: 'screenDrawMove', arguments: [token, 5, 6] });
  assert.equal(sandbox.screenDraw.hide(token), true);
  assert.deepEqual(calls.native.at(-1), { name: 'screenDrawHide', arguments: [token] });

  assert.equal(sandbox.floatBall.show('任务', 10, 20), true);
  assert.deepEqual(calls.native.at(-1), { name: 'floatBallShow', arguments: ['任务', 10, 20] });
  assert.equal(sandbox.floatBall.move(30, 40), true);
  assert.deepEqual(calls.native.at(-1), { name: 'floatBallMove', arguments: [30, 40] });
  assert.equal(sandbox.floatBall.isShow(), true);
  assert.deepEqual(calls.native.at(-1), { name: 'floatBallIsShow', arguments: [] });
  assert.equal(sandbox.floatBall.hide(), true);
  assert.equal(sandbox.setFloatBallPoint(50, 60), true);
  assert.deepEqual(calls.native.at(-1), { name: 'floatBallShow', arguments: ['', 50, 60] });

  const node = { handle: 'h9', text: 'x' };
  assert.equal(sandbox.node.keep(node), node);
  assert.equal(sandbox.node.keptCount(), 1);
  assert.equal(sandbox.node.unkeep(node), node);
  assert.equal(sandbox.node.keptCount(), 0);
  assert.equal(sandbox.keepNode(node), node);
  assert.equal(sandbox.unkeepNode(node), node);
  const node2 = { id: 'i1' };
  assert.equal(sandbox.keepNode(node2), node2);
  assert.equal(sandbox.node.keptCount(), 1);
  assert.equal(sandbox.unkeepNode(node2), node2);
  assert.equal(sandbox.node.keptCount(), 0);
  assert.equal(typeof sandbox.node, 'object');
});

test('date formatting, sleepRandom, string helpers, isInstalled and memory aliases', () => {
  const { sandbox, calls } = boot();
  // dateFormat
  assert.equal(sandbox.formatDate(1700000000000, 'yyyy'), '2023');
  assert.equal(sandbox.dateFormat(1700000000000, 'MM/dd'), '11/15');
  assert.equal(sandbox.formatDate(0, 'HH:mm:ss'), '08:00:00');
  assert.equal(sandbox.strings.formatDate(1700000000000, 'yyyy-MM-dd E').length, '2023-11-15 三'.length);
  // sleepRandom
  const sleepMs = (() => { const before = calls.sleep.length; sandbox.sleepRandom(30, 40); return calls.sleep.at(-1); })();
  assert.ok(sleepMs >= 30 && sleepMs <= 40, 'sleepRandom must sleep within the inclusive range');
  // string helpers
  assert.equal(sandbox.startWith('hello world', 'hello'), true);
  assert.equal(sandbox.startWith('hello', 'x'), false);
  assert.equal(sandbox.endWith('hello world', 'world'), true);
  assert.equal(sandbox.contains('hello', 'ell'), true);
  assert.equal(sandbox.strings.indexOf('abab', 'b'), 1);
  assert.equal(sandbox.strings.lastIndexOf('abab', 'b'), 3);
  assert.equal(sandbox.strings.substring('hello', 1, 3), 'el');
  assert.equal(sandbox.strings.replaceAll('a-b-c', '-', '+'), 'a+b+c');
  assert.equal(sandbox.strings.toUpperCase('aB'), 'AB');
  assert.equal(sandbox.strings.toLowerCase('aB'), 'ab');
  assert.equal(sandbox.strings.join(['a', 'b'], '-'), 'a-b');
  assert.equal(sandbox.strings.repeat('ab', 3), 'ababab');
  assert.equal(sandbox.strings.length('中文abc'), 5);
  assert.equal(sandbox.padZero(7, 3), '007');
  assert.equal(sandbox.strings.padStart('7', 3, '0'), '007');
  assert.equal(sandbox.strings.padEnd('7', 3, 'x'), '7xx');
  assert.equal(sandbox.strings.format('id=%d name=%s', 1, 'tom'), 'id=1 name=tom');
  // app.isInstalled via appList
  assert.equal(sandbox.app.isInstalled('com.example.host'), true);
  assert.equal(sandbox.app.isInstalled('com.apple.safari'), false);
  assert.equal(typeof sandbox.isInstalled, 'function');
  // memory aliases
  assert.equal(sandbox.device.getTotalMemory(), 8000000000);
  assert.equal(sandbox.device.getAvailableMemory(), 2000000000);
  assert.equal(sandbox.device.getUsedMemory(), 300000000);
  assert.equal(typeof sandbox.file.getLineCount, 'function');
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