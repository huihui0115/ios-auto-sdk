const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const test = require('node:test');
const {
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
