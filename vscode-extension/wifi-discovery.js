const net = require('node:net');
const { Bonjour } = require('bonjour-service');

const DEFAULT_DISCOVERY_TIMEOUT_MS = 3500;
// Bonjour responses may arrive in separate multicast bursts. Keep listening long
// enough after the latest valid phone to include slower responders, while the
// overall discovery timeout below remains the hard upper bound.
const DISCOVERY_SETTLE_MS = 1200;
const MAX_DISCOVERY_TIMEOUT_MS = 15000;
const MAX_DISCOVERED_DEVICES = 64;

function boundedTimeout(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return DEFAULT_DISCOVERY_TIMEOUT_MS;
  return Math.min(MAX_DISCOVERY_TIMEOUT_MS, Math.max(100, Math.trunc(number)));
}

function usableAddress(value) {
  const address = String(value || '').trim();
  const family = net.isIP(address);
  if (!family) return undefined;
  if (address === '0.0.0.0' || address === '::' || address === '::1' || address.startsWith('127.')) return undefined;
  if (family === 6 && /^(?:fe[89ab]|ff)/i.test(address)) return undefined;
  return { address, family };
}

function serviceIdentity(service) {
  const name = String(service?.name || '').trim();
  const stableSuffix = name.match(/(?:·\s*|AutoSDK-)([a-f0-9]{8})$/i);
  if (stableSuffix) return `autosdk:${stableSuffix[1].toLowerCase()}`;
  return String(service?.fqdn || name).trim().slice(0, 256);
}

function serviceDevice(service) {
  const port = Number(service?.port);
  if (!Number.isSafeInteger(port) || port < 1 || port > 65535) return undefined;
  const addresses = [...new Set((Array.isArray(service?.addresses) ? service.addresses : []).map(usableAddress).filter(Boolean)
    .sort((left, right) => left.family - right.family).map(item => item.address))];
  if (!addresses.length) return undefined;
  const address = addresses[0];
  const host = net.isIP(address) === 6 ? `[${address}]` : address;
  const name = String(service?.name || 'AutoSDK iPhone').trim().slice(0, 128) || 'AutoSDK iPhone';
  const deviceId = serviceIdentity(service) || `${address}:${port}`;
  return { deviceId, name, address, addresses, port, url: `ws://${host}:${port}` };
}

async function discoverWifiDevices(options = {}) {
  const timeoutMs = boundedTimeout(options.timeoutMs);
  const BonjourClass = options.BonjourClass || Bonjour;
  const signal = options.signal;
  const scheduleTimeout = options.scheduleTimeout || setTimeout;
  const cancelTimeout = options.cancelTimeout || clearTimeout;
  const found = new Map();
  let browser;
  let bonjour;
  let settleTimer;
  let timer;
  let settled = false;
  let abortListener;

  const cleanup = () => {
    cancelTimeout(timer);
    cancelTimeout(settleTimer);
    if (abortListener) signal?.removeEventListener('abort', abortListener);
    try { browser?.stop(); } catch (_) { /* browser already stopped */ }
    try { bonjour?.destroy(); } catch (_) { /* socket already closed */ }
  };

  return new Promise((resolve, reject) => {
    const finish = error => {
      if (settled) return;
      settled = true;
      cleanup();
      if (error) reject(error);
      else resolve([...found.values()].sort((left, right) => left.name.localeCompare(right.name)));
    };
    abortListener = () => {
      const error = new Error('Wi-Fi discovery cancelled.');
      error.name = 'AbortError';
      finish(error);
    };
    if (signal?.aborted) {
      abortListener();
      return;
    }
    signal?.addEventListener('abort', abortListener, { once: true });
    const onService = service => {
      if (settled) return;
      const device = serviceDevice(service);
      if (!device) return;
      const identity = device.deviceId || device.url;
      if (found.size >= MAX_DISCOVERED_DEVICES && !found.has(identity)) return;
      found.set(identity, device);
      cancelTimeout(settleTimer);
      settleTimer = scheduleTimeout(() => finish(), DISCOVERY_SETTLE_MS);
    };

    try {
      bonjour = new BonjourClass({}, error => finish(new Error(`Wi-Fi discovery failed: ${error.message || error}`)));
      if (settled) {
        cleanup();
        return;
      }
      browser = bonjour.find({ type: 'autosdk', protocol: 'tcp' }, onService);
      if (settled) {
        cleanup();
        return;
      }
      browser?.update?.();
    } catch (error) {
      finish(new Error(`Wi-Fi discovery could not start: ${error.message}`));
      return;
    }
    if (!settled) timer = scheduleTimeout(() => finish(), timeoutMs);
  });
}

module.exports = {
  DEFAULT_DISCOVERY_TIMEOUT_MS,
  DISCOVERY_SETTLE_MS,
  MAX_DISCOVERED_DEVICES,
  boundedTimeout,
  discoverWifiDevices,
  serviceDevice,
  serviceIdentity,
  usableAddress
};
