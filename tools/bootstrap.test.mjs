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
    touch: [], clickPoint: [], click: [], swipe: [], sleep: [], ocr: [], screenshot: [], findColorEx: [], findNotColor: [], media: [], pixel: [],
    execAsync: [],
    execOp: [],
    nodeSnapshot: [],
    findImage: [],
    findColor: [],
    findMultiColor: [],
    compareColors: [],
  };
  const logs = [];
  let virtualNow = 0;
  let sleepRejected = false;
  let nodeSnapshotData = [];
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
        case 'exists': {
          const prefix = String(data.path || '').replace(/\/+$/, '') + '/';
          return Object.prototype.hasOwnProperty.call(files, data.path) || Object.keys(files).some((key) => key.startsWith(prefix));
        }
        case 'readText': return Object.prototype.hasOwnProperty.call(files, data.path) ? files[data.path] : null;
        case 'readBase64': return Buffer.from(files[data.path] ?? '', 'utf8').toString('base64');
        case 'readLines': return String(files[data.path] ?? '').split('\n').filter((line, i, all) => i < all.length - 1 || line !== '');
        case 'writeText': files[data.path] = String(data.text ?? ''); return true;
        case 'writeBase64': files[data.path] = Buffer.from(String(data.text ?? ''), 'base64').toString('utf8'); return true;
        case 'appendText': files[data.path] = (files[data.path] ?? '') + String(data.text ?? ''); return true;
        case 'list': {
          const prefix = String(data.path || '').replace(/\/+$/, '') + '/';
          const entries = [];
          const seenDirs = new Set();
          for (const key of Object.keys(files)) {
            if (!key.startsWith(prefix)) continue;
            const rest = key.slice(prefix.length);
            const slash = rest.indexOf('/');
            if (slash < 0) {
              entries.push({ name: rest, path: key, isDirectory: false, isFile: true, size: String(files[key] ?? '').length, modifiedAtMs: 1700000000000 });
            } else if (!seenDirs.has(rest.slice(0, slash))) {
              seenDirs.add(rest.slice(0, slash));
              entries.push({ name: rest.slice(0, slash), path: prefix + rest.slice(0, slash), isDirectory: true, isFile: false });
            }
          }
          return entries;
        }
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
        case 'vpnStatus': return 'connected';
        case 'vpnSet': return true;
        case 'openSystemSettings': return true;
        case 'lowPowerMode': return true;
        case 'locationServices': return true;
        case 'locationAuthorization': return 'authorizedWhenInUse';
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
    invokeFindImage: (data) => { calls.findImage.push(data); return { match: true, x: 11, y: 22, width: 5, height: 5 }; },
    invokeFindColor: (data) => { calls.findColor.push(data); return { match: true, x: 11, y: 22 }; },
    invokePixelColor: (data) => { calls.pixel.push(data); return { r: 1, g: 2, b: 3, a: 255, hex: '#010203' }; },
    invokeCompareColors: (data) => { calls.compareColors.push(data); return true; },
    invokeFindMultiColor: (data) => { calls.findMultiColor.push(data); return { match: true, x: 11, y: 22 }; },
    invokeOCR: (region) => { calls.ocr.push(region); return [{ text: 'hello', confidence: 0.9 }]; },
    invokeLastError: () => ({ code: 42, message: 'mock native error', domain: 'AutoSDK' }),
    invokeExists: () => true,
    invokeFindElement: () => ({ handle: 'h1' }),
    invokeFindElements: () => [{ handle: 'h1' }],
    invokeNodeSnapshot: (data) => { calls.nodeSnapshot.push(data); return nodeSnapshotData; },
    invokeWaitFor: () => true,
    invokeGetAttribute: () => 'attribute-value',
    invokeGetBounds: () => ({ x: 10, y: 20, width: 100, height: 50, centerX: 60, centerY: 45 }),
    invokeGetChildren: (data) => {
      if (data && data.handle === 'h2') return [{ handle: 'h3' }];
      if (data && data.handle === 'h3') return [];
      return [{ handle: 'h2' }];
    },
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
      if (data.sync) return data.arguments[0] === 'object' ? { a: 1, list: [1, 2] } : 'sync-result-' + String(data.arguments[0]);
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
    setNodeSnapshot: (nodes) => { nodeSnapshotData = Array.isArray(nodes) ? nodes : []; },
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
  sandbox.http.put('https://example.com/put', { body: 'y' });
  assert.equal(calls.http.at(-1).method, 'PUT');
  assert.deepEqual(calls.http.at(-1).body, { body: 'y' });
  sandbox.http.delete('https://example.com/del', { timeout: 1000 });
  assert.equal(calls.http.at(-1).method, 'DELETE');
  assert.equal(calls.http.at(-1).timeout, 1000);
  sandbox.http.head('https://example.com/head');
  assert.equal(calls.http.at(-1).method, 'HEAD');
  sandbox.http.patch('https://example.com/patch', { v: 2 });
  assert.equal(calls.http.at(-1).method, 'PATCH');
  assert.deepEqual(calls.http.at(-1).body, { v: 2 });
  assert.equal(sandbox.http.requestEx, sandbox.http);
});

test('http params merge into query strings and cookies/files/formData forward', () => {
  const { sandbox, calls } = boot();
  sandbox.http.get('https://example.com/api', { params: { a: 1, b: 'x' } });
  assert.equal(calls.http.at(-1).url, 'https://example.com/api?a=1&b=x');
  sandbox.http.get('https://example.com/api?existing=1', { params: { b: 2 } });
  assert.equal(calls.http.at(-1).url, 'https://example.com/api?existing=1&b=2');
  sandbox.http.get('https://example.com/api', { query: { q: 'hi' } });
  assert.equal(calls.http.at(-1).url, 'https://example.com/api?q=hi');
  sandbox.http.get('https://example.com/api', { params: { a: null, b: 0 } });
  assert.equal(calls.http.at(-1).url, 'https://example.com/api?b=0');
  sandbox.http.request('https://example.com/up', { method: 'POST', files: { file: 'a.png' }, formData: { note: 'hi' }, cookies: { sid: 'abc' } });
  const last = calls.http.at(-1);
  assert.deepEqual(last.files, { file: 'a.png' });
  assert.deepEqual(last.formData, { note: 'hi' });
  assert.deepEqual(last.cookies, { sid: 'abc' });
  assert.equal(last.method, 'POST');
  sandbox.http.post('https://example.com/up2', { files: { file: 'b.png' }, formData: { note: 'post-options' } });
  assert.deepEqual(calls.http.at(-1).files, { file: 'b.png' });
  assert.deepEqual(calls.http.at(-1).formData, { note: 'post-options' });
});

test('ocr.newOcr builds instances merging defaults over invokeOCR', () => {
  const { sandbox, calls } = boot();
  assert.equal(typeof sandbox.ocr.newOcr, 'function');
  const engine = sandbox.ocr.newOcr({ mode: 'fast', height: 100 });
  const items = engine.ocrImage('/sandbox/shot.png');
  assert.deepEqual(calls.ocr.at(-1), { mode: 'fast', height: 100, screenshotPath: '/sandbox/shot.png' });
  assert.equal(items[0].text, 'hello');
  engine.ocrBitmap({ path: '/sandbox/handle.png' }, { mode: 'accurate' });
  assert.deepEqual(calls.ocr.at(-1), { mode: 'accurate', height: 100, screenshotPath: '/sandbox/handle.png' });
  engine.ocr('/sandbox/direct.png');
  assert.equal(calls.ocr.at(-1).screenshotPath, '/sandbox/direct.png');
  sandbox.ocr.newOcr().ocrImage(null);
  assert.equal(calls.ocr.at(-1).screenshotPath, undefined);
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
  sandbox.file.writeText(sandbox.file.resolvePath('left.txt'), 'stay');
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

test('a throwing timer callback does not abort the drain loop', () => {
  const { sandbox, drainTimers } = boot();
  sandbox.order = [];
  sandbox.setTimeout(() => { throw new Error('boom'); }, 1);
  sandbox.setTimeout(() => { sandbox.order.push('second'); }, 2);
  drainTimers();
  assert.deepEqual(sandbox.order, ['second']);
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

test('touch primitives: staged fingers replay via multiGesture, touchUp flushes all', () => {
  const { sandbox, calls } = boot();
  assert.equal(sandbox.auto.touchDown(10, 20), true);
  assert.equal(sandbox.auto.touchMove(30, 40), true);
  assert.equal(sandbox.auto.touchUp(), true);
  assert.deepEqual(calls.touch.at(-1).fingers, [[
    { type: 'pointerMove', duration: 0, x: 10, y: 20 },
    { type: 'pointerDown', button: 0 },
    { type: 'pointerMove', duration: 0, x: 30, y: 40 },
    { type: 'pointerUp', button: 0 },
  ]]);
  const before = calls.touch.length;
  // two staged fingers flush together with one touchUp()
  sandbox.auto.touchDown(100, 300, 0);
  sandbox.auto.touchDown(300, 300, 1);
  sandbox.auto.touchMove(100, 100, 0);
  sandbox.auto.touchMove(300, 100, 1);
  assert.equal(sandbox.auto.touchUp(), true);
  assert.equal(calls.touch.length, before + 1);
  assert.equal(calls.touch.at(-1).fingers.length, 2);
  assert.equal(calls.touch.at(-1).fingers[0].at(-1).type, 'pointerUp');
  // touchUp with nothing staged is a no-op that returns true
  const noopBefore = calls.touch.length;
  assert.equal(sandbox.auto.touchUp(), true);
  assert.equal(calls.touch.length, noopBefore);
});
test('parity globals waitFor/currentPackage/setClip/getClip; pad guards; color prefix fix', () => {
  const { sandbox, calls } = boot();
  assert.equal(sandbox.waitFor({ text: 'ok' }, 100), true);
  assert.equal(sandbox.currentPackage(), 'com.example.host');
  sandbox.setClip('clip-value');
  assert.deepEqual(calls.device.at(-1), { operation: 'clipboardSet', text: 'clip-value' });
  assert.equal(sandbox.getClip(), 'clipboard-value');
  // empty pad string must not loop forever
  assert.equal(sandbox.strings.padStart('7', 5, ''), '7');
  assert.equal(sandbox.strings.padEnd('7', 5, ''), '7');
  // parseColor strips only leading # / 0x prefixes
  assert.equal(sandbox.parseColor('0xff0000'), 0xff0000);
  assert.equal(sandbox.parseColor('#00ff00'), 0x00ff00);
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
  sandbox.device.vibrateLong();
  assert.deepEqual(calls.device.at(-1), { operation: 'vibrate', duration: 500 });
  sandbox.vibrateShort();
  assert.deepEqual(calls.device.at(-1), { operation: 'vibrate', duration: 50 });
});

test('deleteAllFile recursively removes directory contents and returns the count', () => {
  const { sandbox, calls } = boot();
  sandbox.file.mkdirs('/sandbox/dir/sub');
  sandbox.file.writeText('/sandbox/dir/a.txt', 'alpha');
  sandbox.file.writeText('/sandbox/dir/sub/b.txt', 'beta');
  sandbox.file.writeText('/sandbox/dir/c.txt', 'gamma');
  const listed = sandbox.file.list('/sandbox/dir');
  assert.equal(listed.length, 3);
  const dirEntry = listed.find((entry) => entry.isDirectory);
  assert.equal(dirEntry?.name, 'sub');
  assert.equal(dirEntry?.path, '/sandbox/dir/sub');
  const removed = sandbox.file.deleteAllFile('/sandbox/dir');
  assert.equal(removed, 4);
  assert.equal(sandbox.file.exists('/sandbox/dir/a.txt'), false);
  assert.equal(sandbox.file.exists('/sandbox/dir/sub/b.txt'), false);
  assert.equal(sandbox.file.exists('/sandbox/dir/c.txt'), false);
  const removeCalls = calls.file.filter((call) => call.operation === 'remove').map((call) => call.path);
  assert.deepEqual(removeCalls.sort(), ['/sandbox/dir/a.txt', '/sandbox/dir/c.txt', '/sandbox/dir/sub', '/sandbox/dir/sub/b.txt']);
  assert.equal(sandbox.file.deleteAllFile('/sandbox/dir/missing'), 0);
  sandbox.file.writeText('/sandbox/single.txt', 'one');
  assert.equal(sandbox.file.deleteAllFile('/sandbox/single.txt'), 1);
  assert.equal(sandbox.file.exists('/sandbox/single.txt'), false);
  assert.equal(typeof sandbox.file.deleteAllFile, 'function');
});

test('EasyClick selector match aliases populate regex query fields', () => {
  const { sandbox } = boot();
  const sel = sandbox.selector().idMatch('cell-1').typeMatch('Button').nameMatch('Save').labelMatch('OK').valueMatch('v1').textMatch('^Go$');
  assert.deepEqual(sel._q, { idMatch: 'cell-1', typeMatch: 'Button', nameMatch: 'Save', labelMatch: 'OK', valueMatch: 'v1', textMatch: '^Go$' });
  assert.equal(sandbox.selector().textContains('a.b')._q.textMatch, '.*a' + String.fromCharCode(92) + '.b.*');
  assert.equal(sandbox.selector().textStartsWith('x(')._q.textMatch, '^x' + String.fromCharCode(92) + '(');
  assert.equal(sandbox.selector().descContains('d.e')._q.nameMatch, '.*d' + String.fromCharCode(92) + '.e.*');
  assert.equal(typeof sandbox.Selector().textMatch, 'function');
});

test('node relation methods wrap children/parent/siblings like EasyClick', () => {
  const { sandbox } = boot();
  const node = sandbox.findNode({ id: 'x' });
  const kids = node.children();
  assert.equal(kids.length, 1);
  assert.equal(kids[0].handle, 'h2');
  assert.equal(typeof kids[0].click, 'function');
  const parent = node.parent();
  assert.equal(parent.handle, 'h0');
  assert.equal(typeof parent.click, 'function');
  assert.deepEqual(node.siblings().map((n) => n.handle), ['h2']);
  assert.deepEqual(node.nextSiblings(), []);
  assert.deepEqual(node.previousSiblings(), []);
  assert.equal(node.set_text, node.setText);
  assert.equal(node.clear_text, node.clearText);
  const descendants = node.allChildren();
  assert.deepEqual(descendants.map((n) => n.handle), ['h2', 'h3']);
  assert.equal(typeof descendants[0].click, 'function');
});

test('boundsInfo refreshes rect/center on bounds-less nodes without throwing', () => {
  const { sandbox } = boot();
  const node = sandbox.findNode({ id: 'x' });
  assert.equal(node.rect, null);
  const bounds = node.boundsInfo();
  assert.equal(bounds.width, 100);
  assert.equal(node.rect.width, 100);
  assert.equal(node.center.x, 60);
  assert.equal(node.center.y, 45);
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
test('findColorCount and image.toBase64 (AScript benchmark round 15)', () => {
  const { sandbox, calls } = boot();
  // findColorCount wraps findColorEx with a large default limit
  assert.equal(sandbox.findColorCount('0xCDD7E9-0x101010'), 1);
  assert.deepEqual(calls.findColorEx.at(-1), { colors: '0xCDD7E9-0x101010', threshold: 0.9, x: 0, y: 0, ex: 0, ey: 0, limit: 100000, direction: 1 });
  assert.equal(sandbox.findColorCount('#00FF00', 0.8, 10, 20, 100, 200, 50), 1);
  assert.deepEqual(calls.findColorEx.at(-1), { colors: '#00FF00', threshold: 0.8, x: 10, y: 20, ex: 100, ey: 200, limit: 50, direction: 1 });
  assert.equal(typeof sandbox.screen.findColorCount, 'function');
  assert.equal(typeof sandbox.image.findColorCount, 'function');
  // image.toBase64 reads a sandbox file as base64
  sandbox.file.writeText('demo/img.txt', 'hello');
  assert.equal(sandbox.image.toBase64('demo/img.txt'), Buffer.from('hello', 'utf8').toString('base64'));
  assert.equal(typeof sandbox.image.toBase64, 'function');
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
  assert.deepEqual(sandbox.execSync(function () { return {}; }, 'object'), { a: 1, list: [1, 2] });

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
  assert.equal(sandbox.screenDraw.release(token), true);
  assert.deepEqual(calls.native.at(-1), { name: 'screenDrawRelease', arguments: [token] });
  assert.equal(sandbox.screenDraw.clearAll(), true);
  assert.deepEqual(calls.native.at(-1), { name: 'screenDrawClearAll', arguments: [] });

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
  // dateFormat (assertions derive expected values from local time so they pass in any timezone)
  const dNov = new Date(1700000000000);
  const p2 = (v) => String(v).padStart(2, '0');
  assert.equal(sandbox.formatDate(1700000000000, 'yyyy'), String(dNov.getFullYear()));
  assert.equal(sandbox.dateFormat(1700000000000, 'MM/dd'), p2(dNov.getMonth() + 1) + '/' + p2(dNov.getDate()));
  const dEpoch = new Date(0);
  assert.equal(sandbox.formatDate(0, 'HH:mm:ss'), p2(dEpoch.getHours()) + ':' + p2(dEpoch.getMinutes()) + ':' + p2(dEpoch.getSeconds()));
  const weekNames = ['日', '一', '二', '三', '四', '五', '六'];
  assert.equal(sandbox.strings.formatDate(1700000000000, 'yyyy-MM-dd E'),
    dNov.getFullYear() + '-' + p2(dNov.getMonth() + 1) + '-' + p2(dNov.getDate()) + ' ' + weekNames[dNov.getDay()]);
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

test('screen module: getColor/getColorRGB/getColorHex and EasyClick vision entries', () => {
  const { sandbox, calls } = boot();
  // direct pixel color
  assert.deepEqual(sandbox.screen.getColor(10, 20), { r: 1, g: 2, b: 3, a: 255, hex: '#010203' });
  assert.deepEqual(sandbox.screen.getColorRGB(10, 20), { r: 1, g: 2, b: 3 });
  assert.equal(sandbox.screen.getColorHex(10, 20), '#010203');
  assert.deepEqual(calls.pixel.at(-1), { x: 10, y: 20 });
  // global string alias points at stringsApi
  assert.equal(typeof sandbox.string.trim, 'function');
  assert.equal(sandbox.string.trim('  hi  '), 'hi');
  // vision forwarding: findImage / findColor / findMultiColor / compare aliases
  assert.deepEqual(sandbox.screen.findImage('a.png', { threshold: 0.9 }), { match: true, x: 11, y: 22, width: 5, height: 5 });
  assert.deepEqual(sandbox.screen.findColor('#ff0000', { x: 0, y: 0 }), { match: true, x: 11, y: 22 });
  assert.deepEqual(sandbox.screen.findMultiColor('#000000', [{ dx: 1, dy: 1, color: '#fff' }]), { match: true, x: 11, y: 22 });
  assert.equal(sandbox.screen.findColors([{ x: 1, y: 1, color: '#fff' }]), true);
  assert.equal(sandbox.screen.isColors([{ x: 1, y: 1, color: '#fff' }]), true);
  assert.equal(sandbox.screen.cmpColor([{ x: 1, y: 1, color: '#fff' }]), true);
  assert.equal(typeof sandbox.screen.findColorEx, 'function');
  assert.equal(typeof sandbox.screen.findNotColor, 'function');
  // ocr + screenshot forwarding
  assert.deepEqual(sandbox.screen.ocr({ mode: 'fast' }), [{ text: 'hello', confidence: 0.9 }]);
  assert.equal(sandbox.screen.screenshot(), 'png-data');
});

test('app.getAppName and app.isRunning resolve from appList and state', () => {
  const { sandbox, calls } = boot();
  assert.equal(sandbox.app.getAppName('com.example.host'), 'Host');
  assert.equal(sandbox.app.getAppName('com.apple.safari'), null);
  assert.deepEqual(calls.app.filter((c) => c.operation === 'appList').at(-1), { operation: 'appList' });
  // state mock returns 4 (foreground) -> isRunning true
  assert.equal(sandbox.app.isRunning('com.example.host'), true);
  assert.deepEqual(calls.app.filter((c) => c.operation === 'state').at(-1), { operation: 'state', bundleId: 'com.example.host' });
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

test('node module: at() hit-testing, rect helpers and method forwarding', () => {
  const { sandbox, calls, setNodeSnapshot } = boot();
  setNodeSnapshot([
    { handle: 'root', type: 'XCUIElementTypeOther', bounds: { x: 0, y: 0, width: 390, height: 844 }, visible: true },
    { handle: 'btn', id: 'ok', label: '确定', type: 'XCUIElementTypeButton', enabled: true, selected: false,
      bounds: { x: 100, y: 200, width: 100, height: 50, centerX: 150, centerY: 225 } },
    { handle: 'inner', label: '内层', bounds: { x: 110, y: 210, width: 40, height: 20 }, visible: true },
  ]);
  // at() picks the smallest containing element
  const hit = sandbox.node.at(115, 215);
  assert.equal(hit.handle, 'inner');
  assert.equal(hit.label, '内层');
  const hit2 = sandbox.node.at(160, 240);
  assert.equal(hit2.handle, 'btn');
  assert.equal(sandbox.node.at(999, 999), null);
  assert.equal(sandbox.auto.node.at(115, 215).handle, 'inner');
  assert.equal(sandbox.auto.screen, sandbox.screen);
  assert.equal(sandbox.auto.floatLog, sandbox.floatLog);
  assert.deepEqual(calls.nodeSnapshot.at(-1), { maxResults: 2000 });
  // rect helpers
  assert.equal(hit.rect.center.x, 130);
  assert.equal(hit.rect.right, 150);
  assert.equal(hit.rect.bottom, 230);
  assert.equal(hit2.center.y, 225);
  assert.equal(hit2.info.id, 'ok');
  // methods forward
  assert.equal(hit2.click(), true);
  assert.equal(hit2.selected(), false);
  assert.equal(hit2.exists(), true);
  assert.equal(hit2.tap(), true);
  assert.equal(hit2.tap_hold(500), true);
  assert.equal(hit2.scroll(), true);
  assert.equal(hit2.setText('x'), true);
  assert.equal(hit2.attr('type'), 'attribute-value');
  // node.find / node.findAll wrap raw element results
  const single = sandbox.node.find({ id: 'ok' });
  assert.equal(single.handle, 'h1');
  assert.equal(typeof single.click, 'function');
  const many = sandbox.node.findAll({ type: 'Button' });
  assert.equal(many.length, 1);
  assert.equal(many[0].handle, 'h1');
  // global aliases
  assert.equal(sandbox.findNode({ id: 'x' }).handle, 'h1');
  assert.equal(sandbox.findNodes({ id: 'x' }).length, 1);
  assert.equal(sandbox.nodeAt(10, 10).handle, 'root');
  const snap = sandbox.node.snapshot(10);
  assert.equal(snap.length, 3);
  assert.deepEqual(calls.nodeSnapshot.at(-1), { maxResults: 10 });
  assert.equal(typeof sandbox.nodeSnapshot, 'function');
  assert.equal(sandbox.auto.click.length, 1);
});

test('screen.cache / isCache reuse screenshots and pass screenshotPath', () => {
  const { sandbox, calls } = boot();
  assert.equal(sandbox.screen.isCache(), false);
  assert.equal(sandbox.screen.cache(true), true);
  assert.equal(sandbox.screen.isCache(), true);
  assert.equal(calls.screenshot.length, 1); // captured once on enable
  // screenshot() reuses cached data without a native call
  assert.equal(sandbox.screen.screenshot(), 'png-data');
  assert.equal(calls.screenshot.length, 1);
  const cached = '/sandbox/_autosdk_screen_cache.png';
  sandbox.screen.findImage('a.png', { threshold: 0.9 });
  assert.equal(calls.findImage.at(-1).options.screenshotPath, cached);
  sandbox.screen.findColor('#ff0000', { x: 0, y: 0 }, { tolerance: 8 });
  assert.equal(calls.findColor.at(-1).options.screenshotPath, cached);
  sandbox.screen.findMultiColor('#000000', [{ dx: 1, dy: 1, color: '#fff' }], { x: 0, y: 0 });
  assert.equal(calls.findMultiColor.at(-1).options.screenshotPath, cached);
  sandbox.screen.findColors([{ x: 1, y: 1, color: '#fff' }]);
  assert.equal(calls.compareColors.at(-1).options.screenshotPath, cached);
  sandbox.screen.ocr({ mode: 'fast' });
  assert.equal(calls.ocr.at(-1).screenshotPath, cached);
  // findColorEx / findNotColor also ride the cache (flat payload)
  sandbox.findColorEx('#ff0000', 0.9, 0, 0, 100, 100, 5, 1);
  assert.equal(calls.findColorEx.at(-1).screenshotPath, cached);
  sandbox.findNotColor('#00ff00', 0.9, 0, 0, 100, 100, 5, 1);
  assert.equal(calls.findNotColor.at(-1).screenshotPath, cached);
  assert.equal(sandbox.screen.clearCache(), true);
  assert.equal(sandbox.screen.isCache(), false);
  const before = calls.screenshot.length;
  sandbox.screen.screenshot();
  assert.equal(calls.screenshot.length, before + 1);
  sandbox.screen.findImage('a.png');
  assert.equal(calls.findImage.at(-1).options.screenshotPath, undefined);
  sandbox.findColorEx('#ff0000');
  assert.equal(calls.findColorEx.at(-1).screenshotPath, undefined);
});

test('floatLog overlay API forwards native calls', () => {
  const { sandbox, calls } = boot();
  assert.equal(sandbox.floatLog.show(10, 20, 300, 200), true);
  assert.deepEqual(calls.native.at(-1), { name: 'floatLogShow', arguments: [10, 20, 300, 200] });
  assert.equal(sandbox.floatLog.log('hello world'), true);
  assert.deepEqual(calls.native.at(-1), { name: 'floatLogLog', arguments: ['hello world'] });
  assert.equal(sandbox.floatLog.clear(), true);
  assert.deepEqual(calls.native.at(-1), { name: 'floatLogClear', arguments: [] });
  assert.equal(sandbox.floatLog.isShow(), true);
  assert.deepEqual(calls.native.at(-1), { name: 'floatLogIsShow', arguments: [] });
  assert.equal(sandbox.floatLog.hide(), true);
  assert.deepEqual(calls.native.at(-1), { name: 'floatLogHide', arguments: [] });
  assert.equal(sandbox.floatLog.destroy(), true);
  assert.deepEqual(calls.native.at(-1), { name: 'floatLogDestroy', arguments: [] });
});

test('Selector chainable class mirrors AScript selector API', () => {
  const { sandbox, calls } = boot();
  const sel = sandbox.Selector().text('确定').type('Button').clickable(true);
  assert.deepEqual(sel._q, { text: '确定', type: 'Button', accessible: true });
  assert.equal(typeof sandbox.Selector().descContains('账').findOne, 'function');
  const one = sandbox.Selector().textContains('确').findOne();
  assert.equal(one.handle, 'h1');
  assert.equal(typeof one.click, 'function');
  assert.equal(sandbox.Selector().textMatches('^确').find().length, 1);
  const all = sandbox.selector({ id: 'ok' }).findAll();
  assert.equal(all.length, 1);
  assert.equal(all[0].handle, 'h1');
  assert.equal(sandbox.selector({ label: 'x' }).exists(), true);
  assert.equal(sandbox.Selector().descContains('账').waitFor(3000), true);
  assert.equal(sandbox.Selector().text('a').click(), true);
  assert.equal(calls.click.length, 1);
  assert.equal(sandbox.Selector().text('a').tap(), true);
  assert.equal(sandbox.Selector().text('a').longClick(800), true);
  const contains = sandbox.Selector().textContains('a.b')._q;
  assert.equal(contains.textMatch, '.*a\\.b.*');
  const starts = sandbox.Selector().textStartsWith('ab')._q;
  assert.equal(starts.textMatch, '^ab');
  const ends = sandbox.Selector().textEndsWith('xy')._q;
  assert.equal(ends.textMatch, 'xy$');
  const bounds = sandbox.Selector().bounds(1, 2, 3, 4)._q.bounds;
  assert.deepEqual(bounds, { x: 1, y: 2, width: 3, height: 4 });
  assert.equal(sandbox.Selector().xpath('//XCUIElementTypeButton[1]')._q.xpath, '//XCUIElementTypeButton[1]');
});

test('click coordinates with jitter, element selectors, random region clicks and slidePath', () => {
  const { sandbox, calls } = boot();
  assert.equal(sandbox.click(100, 200), true);
  assert.deepEqual(calls.clickPoint.at(-1), { x: 100, y: 200 });
  sandbox.click(100, 200, true);
  const j = calls.clickPoint.at(-1);
  assert.ok(Math.abs(j.x - 100) <= 6 && Math.abs(j.y - 200) <= 6, 'jitter stays within default radius');
  sandbox.click(100, 200, 2);
  const j2 = calls.clickPoint.at(-1);
  assert.ok(Math.abs(j2.x - 100) <= 2 && Math.abs(j2.y - 200) <= 2, 'numeric jitter radius respected');
  assert.equal(sandbox.click({ id: 'ok' }), true);
  assert.equal(calls.click.length, 1);
  sandbox.clickRandomPoint(10, 20, 50, 60);
  const rp = calls.clickPoint.at(-1);
  assert.ok(rp.x >= 10 && rp.x <= 50 && rp.y >= 20 && rp.y <= 60);
  sandbox.clickRandom(10, 20, 50, 60);
  const rp2 = calls.clickPoint.at(-1);
  assert.ok(rp2.x >= 10 && rp2.x <= 50 && rp2.y >= 20 && rp2.y <= 60);
  assert.equal(sandbox.slidePath([[0, 0], [50, 100]], 500), true);
  const track = calls.touch.at(-1).fingers[0];
  assert.equal(track[0].type, 'pointerMove');
  assert.equal(track[1].type, 'pointerDown');
  assert.equal(track[2].type, 'pointerMove');
  assert.equal(track[2].x, 50);
  assert.equal(track[2].y, 100);
  assert.ok(track[2].duration > 400 && track[2].duration <= 510);
  assert.equal(track[3].type, 'pointerUp');
  assert.equal(sandbox.slide_path([[0, 0], [1, 1]], 200), true);
  assert.equal(sandbox.touchAndSlide(0, 0, 50, 100, 300), true);
  assert.equal(calls.swipe.length, 1);
  assert.equal(sandbox.slidePath([[0, 0]], 200), false);
});

test('audioPlay/audioStop manage players by id via native bridge', () => {
  const { sandbox, calls } = boot();
  assert.equal(sandbox.media.audioPlay('beep.mp3', 80), true);
  assert.deepEqual(calls.native.at(-1), { name: 'audioPlay', arguments: ['beep.mp3', 80, false] });
  sandbox.audioPlay('bgm.mp3');
  assert.deepEqual(calls.native.at(-1), { name: 'audioPlay', arguments: ['bgm.mp3', 100, false] });
  sandbox.audioStop(2);
  assert.deepEqual(calls.native.at(-1), { name: 'audioStop', arguments: [2] });
  sandbox.audioStop();
  assert.deepEqual(calls.native.at(-1), { name: 'audioStop', arguments: [0] });
  assert.equal(sandbox.playMp3('a.mp3'), true);
  assert.deepEqual(calls.native.at(-1), { name: 'playMp3', arguments: ['a.mp3', 100, false, false] });
  assert.equal(sandbox.stopMp3(), true);
  assert.deepEqual(calls.native.at(-1), { name: 'stopMp3', arguments: [] });
});

test('image.compress supports (src, dest, quality?) and legacy (src, quality, dest)', () => {
  const { sandbox, calls } = boot();
  sandbox.image.compress("a.png", "out.jpg", 0.5);
  const first = calls.file.at(-1);
  assert.equal(first.sub, "compress");
  assert.equal(first.destination, "out.jpg");
  assert.equal(first.args.quality, 0.5);
  sandbox.image.compress("a.png", 0.8, "out2.jpg");
  const second = calls.file.at(-1);
  assert.equal(second.destination, "out2.jpg");
  assert.equal(second.args.quality, 0.8);
  sandbox.image.compress("a.png", "out3.jpg");
  const third = calls.file.at(-1);
  assert.equal(third.destination, "out3.jpg");
  assert.equal(third.args.quality, 0.8);
});
test('AScript snake_case aliases: Selector find_one/find_all, node set_text/clear_text, action.*, screen.capture', () => {
  const { sandbox, calls } = boot();
  assert.equal(sandbox.Selector().text("x").find_one().handle, "h1");
  assert.equal(sandbox.Selector().text("x").find_once().handle, "h1");
  assert.equal(sandbox.Selector().text("x").find_all().length, 1);
  assert.equal(sandbox.Selector().text("x").wait_for(2000), true);
  const n = sandbox.node.find({ id: "x" });
  assert.equal(n.set_text("abc"), true);
  assert.equal(n.clear_text(), true);
  assert.equal(typeof sandbox.action, "object");
  sandbox.action.click(100, 200);
  assert.deepEqual(calls.clickPoint.at(-1), { x: 100, y: 200 });
  sandbox.action.slide_path([[0, 0], [50, 50]], 300);
  assert.equal(calls.touch.length, 1);
  assert.equal(sandbox.screen.capture(), "png-data");
});
test('node longClick/tap_hold use seconds and webView message channel forwards', () => {
  const { sandbox, calls, bridge } = boot();
  let lastLongClick = null;
  bridge.invokeLongClick = (data) => { lastLongClick = data; return true; };
  const n = sandbox.node.find({ id: "x" });
  assert.equal(n.tap_hold(), true);
  assert.equal(lastLongClick.duration, 1, "tap_hold defaults to 1 second");
  n.tap_hold(2.5);
  assert.equal(lastLongClick.duration, 2.5);
  n.longClick(3);
  assert.equal(lastLongClick.duration, 3);
  assert.equal(sandbox.webView.takeMessage("w1"), true);
  assert.deepEqual(calls.native.at(-1), { name: "webViewTakeMessage", arguments: ["w1"] });
  assert.equal(sandbox.webView.injectBridge("w1"), true);
  const evalCall = calls.native.at(-1);
  assert.equal(evalCall.name, "webViewEval");
  assert.equal(evalCall.arguments[0], "w1");
  assert.ok(String(evalCall.arguments[1]).includes("autosdkBridge"));
  assert.ok(String(evalCall.arguments[1]).includes("messageHandlers.autosdk"));
});
test('keepScreenOn, webView.loadHTML, ocrClick/ocrText and auto proxy fallback route correctly', () => {
  const { sandbox, calls, bridge } = boot();
  sandbox.device.keepScreenOn(true);
  assert.deepEqual(calls.device.at(-1), { operation: 'keepScreenOn', value: true });
  sandbox.keepScreenOn(false);
  assert.deepEqual(calls.device.at(-1), { operation: 'keepScreenOn', value: false });
  sandbox.keepScreenOn();
  assert.deepEqual(calls.device.at(-1), { operation: 'keepScreenOn', value: true });
  sandbox.auto.keepScreenOn(false); // auto proxy falls back to deviceApi
  assert.deepEqual(calls.device.at(-1), { operation: 'keepScreenOn', value: false });
  sandbox.auto.deleteAllPhotos(); // auto proxy falls back to mediaApi
  assert.deepEqual(calls.media.at(-1), { operation: 'deleteAllPhotos' });
  sandbox.webView.loadHTML('w1', '<html><body>hi</body></html>');
  assert.deepEqual(calls.native.at(-1), { name: 'webViewLoadHTML', arguments: ['w1', '<html><body>hi</body></html>'] });
  sandbox.webView.loadHTML('w2', null);
  assert.deepEqual(calls.native.at(-1), { name: 'webViewLoadHTML', arguments: ['w2', ''] });
  bridge.invokeOCR = () => [{ text: '确定按钮', confidence: 0.95, bounds: { x: 100, y: 200, width: 40, height: 20 } }];
  const before = calls.clickPoint.length;
  assert.equal(sandbox.ocrClick('确定'), true);
  assert.equal(calls.clickPoint.length, before + 1);
  assert.deepEqual(calls.clickPoint.at(-1), { x: 120, y: 210 });
  const item = sandbox.ocrText('确定');
  assert.equal(item && item.text, '确定按钮');
  bridge.invokeOCR = () => [{ text: 'other', confidence: 0.9 }];
  assert.equal(sandbox.ocrClick('nonexistent', 1), false);
  assert.equal(sandbox.ocrText('nonexistent', 1), null);
  assert.equal(sandbox.ocr({ mode: 'fast' }).length, 1);
  assert.equal(typeof sandbox.auto.ocrClick, 'function');
});

test('speak/speechStop, openSettings/openAppStore and locale device getters route to bridge', () => {
  const { sandbox, calls } = boot();
  sandbox.speak('你好');
  assert.deepEqual(calls.native.at(-1), { name: 'speak', arguments: ['你好', {}, false] });
  sandbox.speech.speak('hi', { rate: 0.4, volume: 0.8, language: 'en-US' }, true);
  assert.deepEqual(calls.native.at(-1), { name: 'speak', arguments: ['hi', { rate: 0.4, volume: 0.8, language: 'en-US' }, true] });
  sandbox.tts('x');
  assert.equal(calls.native.at(-1).name, 'speak');
  sandbox.speechStop();
  assert.deepEqual(calls.native.at(-1), { name: 'speechStop', arguments: [] });
  sandbox.stopSpeak();
  assert.deepEqual(calls.native.at(-1), { name: 'speechStop', arguments: [] });
  sandbox.speech.stop();
  assert.deepEqual(calls.native.at(-1), { name: 'speechStop', arguments: [] });
  sandbox.app.openSettings();
  assert.deepEqual(calls.app.at(-1), { operation: 'openSettings' });
  sandbox.openAppSetting();
  assert.deepEqual(calls.app.at(-1), { operation: 'openSettings' });
  sandbox.app.openAppStore('284882215');
  assert.deepEqual(calls.app.at(-1), { operation: 'openAppStore', appId: '284882215' });
  sandbox.openAppStore('x');
  assert.deepEqual(calls.app.at(-1), { operation: 'openAppStore', appId: 'x' });
  sandbox.device.getLanguage();
  assert.deepEqual(calls.device.at(-1), { operation: 'language' });
  sandbox.getCountry();
  assert.deepEqual(calls.device.at(-1), { operation: 'country' });
  sandbox.getLocale();
  assert.deepEqual(calls.device.at(-1), { operation: 'locale' });
  sandbox.getTimezone();
  assert.deepEqual(calls.device.at(-1), { operation: 'timezone' });
  sandbox.getUptime();
  assert.deepEqual(calls.device.at(-1), { operation: 'uptime' });
  assert.equal(typeof sandbox.auto.speak, 'function');
});

test('network type helpers route to bridge and ocrClick guards empty text', () => {
  const { sandbox, calls, bridge } = boot();
  sandbox.device.getNetworkType();
  assert.deepEqual(calls.device.at(-1), { operation: 'networkType' });
  sandbox.isWifi();
  assert.deepEqual(calls.device.at(-1), { operation: 'isWifi' });
  sandbox.auto.getNetworkType();
  assert.deepEqual(calls.device.at(-1), { operation: 'networkType' });
  const clickBefore = calls.clickPoint.length;
  assert.equal(sandbox.ocrClick('', 5), false);
  assert.equal(calls.clickPoint.length, clickBefore, 'empty text must not trigger clicks');
  assert.equal(sandbox.ocrText('', 5), null);
  bridge.invokeOCR = () => [{ text: '确定', bounds: { x: 10, y: 20, width: 10, height: 10 } }];
  assert.equal(sandbox.ocrClick('确定', 5), true);
  assert.deepEqual(calls.clickPoint.at(-1), { x: 15, y: 25 });
});
test('Personal VPN and common system switch helpers route bounded device operations', () => {
  const { sandbox, calls } = boot();
  assert.equal(sandbox.vpn.status(), 'connected');
  assert.deepEqual(calls.device.at(-1), { operation: 'vpnStatus' });
  assert.equal(sandbox.vpn.connect(), true);
  assert.deepEqual(calls.device.at(-1), { operation: 'vpnSet', value: true });
  assert.equal(sandbox.vpn.disconnect(), true);
  assert.deepEqual(calls.device.at(-1), { operation: 'vpnSet', value: false });
  assert.equal(sandbox.vpn.openSettings(), true);
  assert.deepEqual(calls.device.at(-1), { operation: 'openSystemSettings', page: 'vpn' });
  sandbox.system.openSettings('wifi');
  assert.deepEqual(calls.device.at(-1), { operation: 'openSystemSettings', page: 'wifi' });
  sandbox.system.openSettings();
  assert.deepEqual(calls.device.at(-1), { operation: 'openSystemSettings', page: 'app' });
  assert.equal(sandbox.device.isLowPowerModeEnabled(), true);
  assert.deepEqual(calls.device.at(-1), { operation: 'lowPowerMode' });
  assert.equal(sandbox.location.isEnabled(), true);
  assert.deepEqual(calls.device.at(-1), { operation: 'locationServices' });
  assert.equal(sandbox.location.getAuthorizationStatus(), 'authorizedWhenInUse');
  assert.deepEqual(calls.device.at(-1), { operation: 'locationAuthorization' });
  assert.equal(sandbox.auto.isLowPowerModeEnabled(), true);
  assert.deepEqual(calls.device.at(-1), { operation: 'lowPowerMode' });
});
test('flashlight/torch route to bridge and default to on', () => {
  const { sandbox, calls } = boot();
  sandbox.device.setFlashlight(true);
  assert.deepEqual(calls.device.at(-1), { operation: 'flashlight', value: true });
  sandbox.torch(false);
  assert.deepEqual(calls.device.at(-1), { operation: 'flashlight', value: false });
  sandbox.device.flashlight();
  assert.deepEqual(calls.device.at(-1), { operation: 'flashlight', value: true });
  sandbox.setFlashlight(false);
  assert.deepEqual(calls.device.at(-1), { operation: 'flashlight', value: false });
  sandbox.auto.setFlashlight(true); // auto proxy falls back to deviceApi
  assert.deepEqual(calls.device.at(-1), { operation: 'flashlight', value: true });
});
test('app.getAppScheme / launchByScheme route to bridge with name', () => {
  const { sandbox, calls } = boot();
  sandbox.app.getAppScheme('weixin');
  assert.deepEqual(calls.app.at(-1), { operation: 'getAppScheme', name: 'weixin' });
  sandbox.launchByScheme('微信');
  assert.deepEqual(calls.app.at(-1), { operation: 'launchByScheme', name: '微信' });
  sandbox.app.launchByScheme('');
  assert.deepEqual(calls.app.at(-1), { operation: 'launchByScheme', name: '' });
  sandbox.auto.getAppScheme('taobao'); // auto proxy falls back to appApi
  assert.deepEqual(calls.app.at(-1), { operation: 'getAppScheme', name: 'taobao' });
});
test('getFrontmostApp returns the foreground app via app bridge', () => {
  const { sandbox, calls } = boot();
  sandbox.app.getFrontmostApp();
  assert.deepEqual(calls.app.at(-1), { operation: 'current' });
  sandbox.getFrontmostApp();
  assert.deepEqual(calls.app.at(-1), { operation: 'current' });
  sandbox.auto.getFrontmostApp(); // auto proxy falls back to appApi
  assert.deepEqual(calls.app.at(-1), { operation: 'current' });
});
test('ocrBaidu fetches token, posts base64 image and joins words', () => {
  const { sandbox, calls, bridge } = boot();
  let tokenCalls = 0;
  bridge.invokeHTTP = (data) => {
    calls.http.push(data);
    if (data.url.indexOf('/oauth/2.0/token') >= 0) { tokenCalls++; return { ok: true, status: 200, json: { access_token: 'tok123' } }; }
    return { ok: true, status: 200, json: { words_result: [{ words: '你好' }, { words: '世界' }] } };
  };
  const res = sandbox.ocrBaidu('aGVsbG8=', 'ak', 'sk', { timeoutMs: 5000 });
  assert.deepEqual(res, { text: '你好\n世界', lines: ['你好', '世界'] });
  assert.equal(tokenCalls, 1);
  assert.equal(sandbox.ocrBaiduText('aGVsbG8=', 'ak', 'sk'), '你好\n世界');
  assert.equal(sandbox.ocrBaidu('aGVsbG8=', '', 'sk'), null, 'empty api key must return null');
  assert.equal(sandbox.ocrBaidu('', 'ak', 'sk'), null, 'empty image must return null');
  sandbox.ocrBaidu('data:image/png;base64,aGVsbG8=', 'ak', 'sk');
  assert.equal(calls.http.at(-1).body, 'image=aGVsbG8=', 'data-url prefix must be stripped and wrapped in image= form field');
  assert.equal(calls.http.at(-1).bodyBase64, undefined, 'OCR image must not be sent as raw octet-stream body');
  assert.equal(calls.http.at(-1).headers['Content-Type'], 'application/x-www-form-urlencoded');
  sandbox.ocrBaidu('aGVsbG8+', 'ak', 'sk'); // base64 containing '+'
  assert.equal(calls.http.at(-1).body, 'image=aGVsbG8%2B', 'plus sign must be percent-encoded for form-urlencoded');
  assert.equal(typeof sandbox.auto.ocrBaidu, 'function');
});

test('isRunning / isDir / isFile global shorthands route correctly', () => {
  const { sandbox, calls } = boot();
  sandbox.isRunning('com.tencent.xin');
  assert.deepEqual(calls.app.at(-1), { operation: 'state', bundleId: 'com.tencent.xin' });
  sandbox.isDir('/tmp');
  assert.deepEqual(calls.file.at(-1), { operation: 'stat', path: '/tmp' });
  sandbox.isFile('/tmp/a.txt');
  assert.deepEqual(calls.file.at(-1), { operation: 'stat', path: '/tmp/a.txt' });
});

test('round58: lastError surfaces the native error object', () => {
  const { sandbox } = boot();
  assert.deepEqual(sandbox.lastError(), { code: 42, message: 'mock native error', domain: 'AutoSDK' });
});

test('round58: gx bulk aliases keep globals identical to their sources', () => {
  const { sandbox } = boot();
  assert.equal(sandbox.click, sandbox.auto.click);
  assert.equal(sandbox.vibrate, sandbox.device.vibrate);
  assert.equal(sandbox.zip, sandbox.file.zip);
  assert.equal(sandbox.audioPlay, sandbox.media.audioPlay);
});

test('round56: bitmap path-handle model round-trips through file ops', () => {
  const { sandbox, calls } = boot();
  const bmp = sandbox.image.readBitmap('/sandbox/a.png');
  assert.deepEqual(bmp, { path: '/sandbox/a.png', isBitmap: true });
  assert.equal(sandbox.image.bitmapToImage(bmp), '/sandbox/a.png');
  sandbox.image.bitmapBase64(bmp);
  assert.equal(calls.file.at(-1).operation, 'readBase64');
  assert.equal(calls.file.at(-1).path, '/sandbox/a.png');
  const out = sandbox.image.base64Bitmap('QUFBQ==', '/sandbox/b.png');
  assert.equal(calls.file.at(-1).operation, 'writeBase64');
  assert.equal(out.path, '/sandbox/b.png');
  assert.equal(out.isBitmap, true);
  sandbox.image.saveBitmap(bmp, '/sandbox/c.png');
  assert.equal(calls.file.at(-1).operation, 'copy');
  assert.equal(calls.file.at(-1).destination, '/sandbox/c.png');
  sandbox.image.getBitmapPixelColor(bmp, 3, 4);
  assert.equal(calls.file.at(-1).operation, 'imagePixelAt');
  assert.equal(calls.file.at(-1).path, '/sandbox/a.png');
  assert.deepEqual(calls.file.at(-1).args, { x: 3, y: 4 });
  // imageProcess ops and size getters accept handles too
  sandbox.image.getWidth(bmp);
  assert.equal(calls.file.at(-1).operation, 'imageSize');
  assert.equal(calls.file.at(-1).path, '/sandbox/a.png');
  sandbox.image.gray(bmp, '/sandbox/gray.png');
  assert.equal(calls.file.at(-1).operation, 'imageProcess');
  assert.equal(calls.file.at(-1).path, '/sandbox/a.png');
  // aliases keep identity with their canonical methods
  assert.equal(sandbox.file.readFile, sandbox.file.readText);
  assert.equal(sandbox.file.getLineText, sandbox.file.readLine);
  assert.equal(sandbox.device.getDeviceInfo, sandbox.device.info);
});

test('device global shorthand exports mirror deviceApi members', () => {
  const { sandbox, calls } = boot();
  sandbox.getOrientation();
  assert.deepEqual(calls.device.at(-1), { operation: 'orientation' });
  sandbox.getModel();
  assert.deepEqual(calls.device.at(-1), { operation: 'model' });
  sandbox.getBattery();
  assert.deepEqual(calls.device.at(-1), { operation: 'battery' });
  sandbox.isCharging();
  assert.deepEqual(calls.device.at(-1), { operation: 'isCharging' });
  sandbox.getScreenWidth();
  assert.deepEqual(calls.device.at(-1), { operation: 'screenWidth' });
  sandbox.getScreenHeight();
  assert.deepEqual(calls.device.at(-1), { operation: 'screenHeight' });
  sandbox.getDeviceInfo();
  assert.deepEqual(calls.device.at(-1), { operation: 'info' });
  sandbox.volumeUp();
  assert.deepEqual(calls.device.at(-1), { operation: 'volumeUp' });
  sandbox.getMemoryInfo();
  assert.deepEqual(calls.device.at(-1), { operation: 'memory' });
  sandbox.getOSVersion();
  assert.deepEqual(calls.device.at(-1), { operation: 'osVersion' });
});

test('sqlite open/exec/query/close route to native bridge', () => {
  const { sandbox, calls } = boot();
  sandbox.sqlite.open('data/app.db');
  assert.deepEqual(calls.native.at(-1), { name: 'sqO', arguments: ['data/app.db'] });
  sandbox.sqlite.exec(7, 'CREATE TABLE IF NOT EXISTS t(id INTEGER PRIMARY KEY, name TEXT)', []);
  assert.deepEqual(calls.native.at(-1), { name: 'sqE', arguments: [7, 'CREATE TABLE IF NOT EXISTS t(id INTEGER PRIMARY KEY, name TEXT)', []] });
  sandbox.sqlite.exec(7, 'INSERT INTO t(name) VALUES (?)', ['a']);
  assert.deepEqual(calls.native.at(-1), { name: 'sqE', arguments: [7, 'INSERT INTO t(name) VALUES (?)', ['a']] });
  sandbox.sqlite.query(7, 'SELECT * FROM t WHERE name=?', ['a']);
  assert.deepEqual(calls.native.at(-1), { name: 'sqQ', arguments: [7, 'SELECT * FROM t WHERE name=?', ['a']] });
  sandbox.sqlite.close(7);
  assert.deepEqual(calls.native.at(-1), { name: 'sqC', arguments: [7] });
});

test('yolo detect routes to native bridge and exposes aliases', () => {
  const { sandbox, calls } = boot();
  sandbox.yolo.detect('shot.png');
  assert.deepEqual(calls.native.at(-1), { name: 'yoloD', arguments: ['shot.png'] });
  sandbox.yolo.detectByFilePath('shot2.png');
  assert.deepEqual(calls.native.at(-1), { name: 'yoloD', arguments: ['shot2.png'] });
  sandbox.yoloDetect('shot3.png');
  assert.deepEqual(calls.native.at(-1), { name: 'yoloD', arguments: ['shot3.png'] });
  assert.equal(sandbox.yolo.detectByFilePath, sandbox.yolo.detect);
});

test('hmacSHA1 / hmacSHA256 route to native bridge', () => {
  const { sandbox, calls } = boot();
  sandbox.hmacSHA1('message', 'secret');
  assert.deepEqual(calls.native.at(-1), { name: 'hmac1', arguments: ['message', 'secret'] });
  sandbox.strings.hmacSHA256('message', 'secret');
  assert.deepEqual(calls.native.at(-1), { name: 'hmac256', arguments: ['message', 'secret'] });
  sandbox.hmacSHA256('a', 'b');
  assert.deepEqual(calls.native.at(-1), { name: 'hmac256', arguments: ['a', 'b'] });
});

test('location.getLocation routes to native bridge with default timeout', () => {
  const { sandbox, calls } = boot();
  sandbox.location.getLocation();
  assert.deepEqual(calls.native.at(-1), { name: 'locGet', arguments: [5000] });
  sandbox.location.getLocation(10000);
  assert.deepEqual(calls.native.at(-1), { name: 'locGet', arguments: [10000] });
});

test('ws client routes connect/poll/send/close to native bridge', () => {
  const { sandbox, calls } = boot();
  sandbox.ws.connect('wss://example.com/sock');
  assert.deepEqual(calls.native.at(-1), { name: 'wsConnect', arguments: ['wss://example.com/sock'] });
  sandbox.ws.poll(3);
  assert.deepEqual(calls.native.at(-1), { name: 'wsPoll', arguments: [3] });
  sandbox.ws.send(3, 'hello');
  assert.deepEqual(calls.native.at(-1), { name: 'wsSend', arguments: [3, 'hello'] });
  sandbox.ws.close(3);
  assert.deepEqual(calls.native.at(-1), { name: 'wsClose', arguments: [3] });
  sandbox.ws.send(3, '');
  assert.deepEqual(calls.native.at(-1), { name: 'wsSend', arguments: [3, ''] });
  assert.equal(typeof sandbox.ws.connect, 'function');
});

test('scanCode routes image path to native bridge and global alias works', () => {
  const { sandbox, calls } = boot();
  sandbox.screen.scanCode('/tmp/code.png');
  assert.deepEqual(calls.native.at(-1), { name: 'scanCode', arguments: ['/tmp/code.png'] });
  sandbox.scanCode('');
  assert.deepEqual(calls.native.at(-1), { name: 'scanCode', arguments: [''] });
  sandbox.auto.scanCode('a.png'); // auto proxy falls back to screenApi
  assert.deepEqual(calls.native.at(-1), { name: 'scanCode', arguments: ['a.png'] });
  assert.equal(typeof sandbox.screen.scanCode, 'function');
});

test('device isScreenOn/isLocked expose lock state', () => {
  const { sandbox } = boot();
  assert.equal(sandbox.isScreenOn(), true);
  assert.equal(sandbox.isLocked(), false);
  assert.equal(sandbox.device.isScreenOn(), true);
  assert.equal(sandbox.device.isLocked(), false);
});

test('EasyClick color tools: parseColor/int2Hex/hex2Int/rgb/argb and global aliases', () => {
  const { sandbox } = boot();
  assert.equal(sandbox.colors.parseColor('#ffffff'), 0xffffff);
  assert.equal(sandbox.parseColor('#fff'), 0xffffff);
  assert.equal(sandbox.parseColor('0xff0000'), 0xff0000);
  assert.equal(sandbox.parseColor(0x010203), 0x010203);
  assert.equal(sandbox.colors.toInt('#abcdef'), 0xabcdef);
  assert.equal(sandbox.hex2Int('#123456'), 0x123456);
  assert.equal(sandbox.parseColor('not-a-color'), null);
  assert.equal(sandbox.colors.int2Hex(0x010203), '#010203');
  assert.equal(sandbox.int2Hex('#ff0000'), '#ff0000');
  assert.equal(sandbox.colors.toHex(0xffffff), '#ffffff');
  assert.equal(sandbox.colors.int2Hex('zzz'), null);
  assert.equal(sandbox.rgb(255, 0, 0), 0xff0000);
  assert.equal(sandbox.colors.rgb(0, 255, 0), 0x00ff00);
  assert.equal(sandbox.argb(255, 1, 2, 3), 0xff010203);
  assert.equal(sandbox.colors.argb(0, 255, 255, 255), 0x00ffffff);
});

test('round40: thread/utils namespaces, EasyClick global aliases and device/image extras', () => {
  const { sandbox, calls } = boot();
  // thread namespace (EasyClick thread module)
  assert.equal(typeof sandbox.thread, 'object');
  const t = sandbox.thread.execAsync(function () { return 1; }, 'a');
  assert.equal(t.join().threadId, 1001);
  assert.equal(typeof sandbox.thread.execSync, 'function');
  assert.equal(sandbox.thread.execSync(function () { return 1; }, 'hi'), 'sync-result-hi');
  sandbox.thread.stopAll();
  assert.deepEqual(calls.execOp.at(-1), { operation: 'stopAll' });
  sandbox.thread.cancelThread(t);
  assert.deepEqual(calls.execOp.at(-1), { operation: 'cancel', threadId: 1001 });
  assert.equal(sandbox.thread.isCancelled(), false);
  // utils namespace (EasyClick utils module)
  assert.equal(sandbox.utils.dataMd5('abc'), 'md5-of-abc');
  assert.equal(typeof sandbox.utils.fileMd5, 'function');
  assert.equal(typeof sandbox.utils.randomInt, 'function');
  assert.equal(typeof sandbox.utils.randomCharNumber, 'function');
  assert.equal(typeof sandbox.utils.getRangeInt, 'function');
  assert.equal(typeof sandbox.utils.getRatio, 'function');
  assert.equal(typeof sandbox.utils.zip, 'function');
  assert.equal(typeof sandbox.utils.unzip, 'function');
  assert.equal(typeof sandbox.utils.readFileInZip, 'function');
  assert.equal(typeof sandbox.utils.playMp3, 'function');
  assert.equal(typeof sandbox.utils.stopMp3, 'function');
  assert.equal(typeof sandbox.utils.deleteAllPhotos, 'function');
  assert.equal(typeof sandbox.utils.deleteAllVideos, 'function');
  assert.equal(typeof sandbox.utils.requestPhotoAuthorization, 'function');
  // EasyClick global aliases
  assert.equal(sandbox.getPasteboard(), 'clipboard-value');
  assert.equal(sandbox.setPasteboard('new'), true);
  assert.deepEqual(calls.device.at(-1), { operation: 'clipboardSet', text: 'new' });
  sandbox.openUrl('https://example.com');
  assert.deepEqual(calls.app.at(-1), { operation: 'openURL', url: 'https://example.com' });
  assert.equal(sandbox.uploadToAlbum('a.png'), true);
  assert.deepEqual(calls.media.at(-1), { operation: 'saveImage', path: 'a.png' });
  assert.equal(sandbox.childcount({ text: 'x' }), 1);
  // device extras (EasyClick device module)
  assert.deepEqual(sandbox.device.applist(), [{ bundleId: 'com.example.host', name: 'Host' }]);
  assert.equal(sandbox.device.getOrientationNoAuto(), 'portrait');
  assert.ok(String(sandbox.device.getDeviceMsg()).includes('iPhone'));
  // image.captureFullScreen alias
  assert.equal(sandbox.image.captureFullScreen(), 'png-data');
});

test('round59: atrim/isInteger/string.random + pasteboard/json namespaces + device backlight aliases', () => {
  const { sandbox, calls } = boot();
  // string utils (TrollAutoScript string module parity)
  assert.equal(sandbox.atrim(' a b\tc\n '), 'abc');
  assert.equal(sandbox.string.atrim(' x y '), 'xy');
  assert.equal(sandbox.isInteger('-12'), true);
  assert.equal(sandbox.isInteger('1.5'), false);
  assert.equal(sandbox.string.isInteger('42'), true);
  assert.equal(sandbox.string.isIntrger('42'), true); // legacy spelling kept
  assert.equal(sandbox.string.random().length, 8);
  const r = sandbox.string.random(10);
  assert.equal(r.length, 10);
  assert.ok(/^[A-Za-z0-9]+$/.test(r));
  assert.ok(/^[01]+$/.test(sandbox.string.random(6, '01')));
  // pasteboard namespace (TrollAutoScript pasteboard.read/write)
  assert.equal(sandbox.pasteboard.read(), 'clipboard-value');
  assert.equal(sandbox.pasteboard.write('r59'), true);
  assert.deepEqual(calls.device.at(-1), { operation: 'clipboardSet', text: 'r59' });
  // json namespace (TrollAutoScript json.encode/decode)
  assert.equal(sandbox.json.encode({ a: 1 }), '{"a":1}');
  assert.deepEqual(sandbox.json.decode('{"a":1}'), { a: 1 });
  assert.equal(sandbox.json.decode('{bad'), null);
  assert.equal(sandbox.json.decode(null), null);
  // device backlight aliases (TrollAutoScript device module)
  assert.equal(sandbox.device.backlightLevel(), 0.6);
  assert.equal(sandbox.device.setBacklightLevel(0.4), true);
  assert.deepEqual(calls.device.at(-1), { operation: 'brightnessSet', value: 0.4 });
  assert.equal(sandbox.auto.setBacklightLevel(0.3), true);
  assert.equal(sandbox.auto.backlightLevel(), 0.6);
});

