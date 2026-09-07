const REENTER_TOKEN = 'Re-enter Token';
const RETRY_CONNECTION = 'Retry Connection';
const SCAN_WIFI_DEVICE = 'Scan Wi-Fi and Add iPhone';
const { canonicalDebugUrl } = require('./connection-settings');

function connectionTargetIsCurrent(actual, expected) {
  const url = canonicalDebugUrl(actual.url);
  return Boolean(url) && url === canonicalDebugUrl(expected.url) &&
    actual.scope === expected.scope && (actual.deviceId || '') === (expected.deviceId || '');
}

function errorMessage(error) {
  return String(error && error.message ? error.message : error || 'Unknown connection error');
}

function isUnconfiguredConnectionError(error) {
  const message = errorMessage(error);
  return message.includes('Run AutoSDK: Scan Wi-Fi and Add iPhone first.') ||
    message.includes('Configure an AutoSDK device URL first.');
}

function runErrorActions(error) {
  return isUnconfiguredConnectionError(error) ? [SCAN_WIFI_DEVICE] : [];
}

async function connectWithRecovery(options) {
  const testConnection = options && options.testConnection;
  const chooseAction = options && options.chooseAction;
  const replaceToken = options && options.replaceToken;
  const isCurrent = options?.isCurrent || (() => true);
  if (typeof testConnection !== 'function' || typeof chooseAction !== 'function' || typeof replaceToken !== 'function') {
    throw new TypeError('Connection recovery requires testConnection, chooseAction, and replaceToken functions.');
  }

  while (isCurrent()) {
    const connected = await testConnection();
    if (!isCurrent()) return false;
    if (connected) return true;
    const action = await chooseAction();
    if (!isCurrent()) return false;
    if (action === RETRY_CONNECTION) continue;
    if (action !== REENTER_TOKEN || !await replaceToken()) return false;
  }
  return false;
}

module.exports = {
  REENTER_TOKEN,
  RETRY_CONNECTION,
  SCAN_WIFI_DEVICE,
  connectWithRecovery,
  connectionTargetIsCurrent,
  errorMessage,
  isUnconfiguredConnectionError,
  runErrorActions
};
