const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const test = require('node:test');
const {
  DISCOVERY_SETTLE_MS,
  MAX_DISCOVERED_DEVICES,
  boundedTimeout,
  discoverWifiDevices,
  serviceDevice,
  serviceIdentity,
  usableAddress
} = require('../wifi-discovery');

test('Wi-Fi discovery normalizes Bonjour services and prefers IPv4', () => {
  assert.deepEqual(serviceDevice({
    name: 'AutoSDK-1234ABCD',
    fqdn: 'AutoSDK-1234ABCD._autosdk._tcp.local',
    port: 9001,
    addresses: ['fe80::1', '192.168.1.25', '127.0.0.1']
  }), {
    deviceId: 'autosdk:1234abcd',
    name: 'AutoSDK-1234ABCD',
    address: '192.168.1.25',
    addresses: ['192.168.1.25'],
    port: 9001,
    url: 'ws://192.168.1.25:9001'
  });
  assert.equal(serviceDevice({ port: 0, addresses: ['192.168.1.2'] }), undefined);
  assert.equal(usableAddress('127.0.0.1'), undefined);
  assert.equal(serviceIdentity({ name: 'My renamed iPhone · 1234ABCD' }), 'autosdk:1234abcd');
});

test('Wi-Fi discovery scans only the AutoSDK TCP service and closes sockets', async () => {
  let findOptions;
  let stopped = false;
  let destroyed = false;
  class FakeBrowser extends EventEmitter {
    update() {}
    stop() { stopped = true; }
  }
  class FakeBonjour {
    find(options, onup) {
      findOptions = options;
      const browser = new FakeBrowser();
      setImmediate(() => onup({
        name: 'Living Room iPhone',
        fqdn: 'phone._autosdk._tcp.local',
        port: 9001,
        addresses: ['192.168.50.8']
      }));
      return browser;
    }
    destroy() { destroyed = true; }
  }

  const devices = await discoverWifiDevices({ BonjourClass: FakeBonjour, timeoutMs: 100 });
  assert.deepEqual(findOptions, { type: 'autosdk', protocol: 'tcp' });
  assert.equal(devices[0].url, 'ws://192.168.50.8:9001');
  assert.equal(stopped, true);
  assert.equal(destroyed, true);
});

test('Wi-Fi discovery keeps collecting long enough for a delayed second phone', async () => {
  let stopped = false;
  let destroyed = false;
  class FakeBrowser extends EventEmitter {
    update() {}
    stop() { stopped = true; }
  }
  class FakeBonjour {
    find(_options, onup) {
      const browser = new FakeBrowser();
      setImmediate(() => onup({
        name: 'First iPhone · 11111111',
        port: 9001,
        addresses: ['192.168.50.8']
      }));
      setTimeout(() => onup({
        name: 'Second iPhone · 22222222',
        port: 9001,
        addresses: ['192.168.50.9']
      }), 600);
      return browser;
    }
    destroy() { destroyed = true; }
  }

  const devices = await discoverWifiDevices({ BonjourClass: FakeBonjour, timeoutMs: 2500 });
  assert.deepEqual(devices.map(device => device.name), [
    'First iPhone · 11111111',
    'Second iPhone · 22222222'
  ]);
  assert.equal(DISCOVERY_SETTLE_MS, 1200);
  assert.equal(stopped, true);
  assert.equal(destroyed, true);
});

test('Wi-Fi discovery cancellation closes Bonjour resources immediately', async () => {
  let stopped = false;
  let destroyed = false;
  let onService;
  const scheduled = [];
  class FakeBrowser extends EventEmitter {
    update() {}
    stop() { stopped = true; }
  }
  class FakeBonjour {
    find(_options, callback) { onService = callback; return new FakeBrowser(); }
    destroy() { destroyed = true; }
  }
  const controller = new AbortController();
  const discovery = discoverWifiDevices({
    BonjourClass: FakeBonjour,
    timeoutMs: 15000,
    signal: controller.signal,
    scheduleTimeout(callback, delay) {
      const timer = { callback, delay };
      scheduled.push(timer);
      return timer;
    },
    cancelTimeout() {}
  });
  controller.abort();
  await assert.rejects(discovery, error => error.name === 'AbortError');
  const scheduledAtCancellation = scheduled.length;
  onService({ name: 'Late iPhone · 33333333', port: 9001, addresses: ['192.168.50.10'] });
  assert.equal(scheduled.length, scheduledAtCancellation);
  assert.equal(stopped, true);
  assert.equal(destroyed, true);
});

test('Wi-Fi discovery rejects multicast socket failures cleanly', async () => {
  class FailedBonjour {
    constructor(_options, onError) { setImmediate(() => onError(new Error('socket unavailable'))); }
    find() { return { stop() {} }; }
    destroy() {}
  }
  await assert.rejects(
    discoverWifiDevices({ BonjourClass: FailedBonjour, timeoutMs: 100 }),
    /Wi-Fi discovery failed: socket unavailable/
  );
});

test('Wi-Fi discovery time and result limits stay bounded', () => {
  assert.equal(boundedTimeout(Infinity), 3500);
  assert.equal(boundedTimeout(1), 100);
  assert.equal(boundedTimeout(999999), 15000);
  assert.equal(MAX_DISCOVERED_DEVICES, 64);
});

test('Wi-Fi discovery cleans up synchronous find failures without starting timers', async () => {
  let stopped = 0; let timers = 0;
  class Bonjour {
    constructor(_options, onError) { this.onError = onError; }
    find() { this.onError(new Error('sync failure')); return { stop() { stopped++; } }; }
    destroy() {}
  }
  await assert.rejects(discoverWifiDevices({ BonjourClass: Bonjour,
    scheduleTimeout() { timers++; }, cancelTimeout() {} }), /sync failure/);
  assert.equal(stopped, 1);
  assert.equal(timers, 0);
});

test('Wi-Fi discovery cancellation during update creates no orphan timer', async () => {
  const controller = new AbortController(); let timers = 0; let stopped = 0;
  class Bonjour {
    find() { return { update() { controller.abort(); }, stop() { stopped++; } }; }
    destroy() {}
  }
  await assert.rejects(discoverWifiDevices({ BonjourClass: Bonjour, signal: controller.signal,
    scheduleTimeout() { timers++; }, cancelTimeout() {} }), { name: 'AbortError' });
  assert.equal(stopped, 1); assert.equal(timers, 0);
});

test('Wi-Fi discovery refreshes known addresses at the device limit and ignores malformed services', async () => {
  let onService; let finish;
  class Bonjour {
    find(_options, callback) { onService = callback; return { stop() {} }; }
    destroy() {}
  }
  const promise = discoverWifiDevices({ BonjourClass: Bonjour,
    scheduleTimeout(callback) { finish = callback; }, cancelTimeout() {} });
  onService({ port: 9001, addresses: 'malformed' });
  for (let index = 0; index < MAX_DISCOVERED_DEVICES; index++) {
    onService({ name: `phone-${index}`, port: 9001, addresses: ['192.168.1.2'] });
  }
  onService({ name: 'overflow', port: 9001, addresses: ['192.168.1.3'] });
  onService({ name: 'phone-0', port: 9001, addresses: ['192.168.1.9'] });
  finish(); const devices = await promise;
  assert.equal(devices.length, MAX_DISCOVERED_DEVICES);
  assert.equal(devices.find(device => device.name === 'phone-0').address, '192.168.1.9');
});
