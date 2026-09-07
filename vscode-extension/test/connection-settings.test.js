const assert = require('node:assert/strict');
const test = require('node:test');
const {
  bindTokenToUrl,
  boundTokenSecretKey,
  canonicalDebugUrl,
  connectionCredentials,
  currentBindingSecretKey,
  normalizeWifiDebugUrl,
  tokenForConfiguration,
  updateConnectionConfiguration,
  workspaceTokenSecretKey
} = require('../connection-settings');

test('Wi-Fi addresses accept a bare phone IP and add the default port', () => {
  assert.equal(normalizeWifiDebugUrl('192.168.1.25'), 'ws://192.168.1.25:9001/');
  assert.equal(normalizeWifiDebugUrl('phone.local:9100'), 'ws://phone.local:9100/');
  assert.equal(normalizeWifiDebugUrl('wss://phone.local:9443/debug'), 'wss://phone.local:9443/debug');
});

test('Wi-Fi addresses reject loopback, credentials, fragments and invalid schemes', () => {
  assert.throws(() => normalizeWifiDebugUrl('127.0.0.1'), /LAN address/);
  assert.throws(() => normalizeWifiDebugUrl('ws://user:pass@phone.local'), /token separately/);
  assert.throws(() => normalizeWifiDebugUrl('ws://phone.local/#bad'), /#fragment/);
  assert.throws(() => normalizeWifiDebugUrl('http://phone.local'), /ws:\/\//);
});

function settings(values) {
  return { get: key => values[key] };
}

function secretStorage(initial = {}) {
  const values = new Map(Object.entries(initial));
  return {
    values,
    get: async key => values.get(key),
    store: async (key, value) => values.set(key, value),
    delete: async key => values.delete(key)
  };
}

test('debug URLs are canonicalized before binding credentials', () => {
  assert.equal(canonicalDebugUrl('  ws://127.0.0.1:9001  '), 'ws://127.0.0.1:9001/');
  assert.equal(canonicalDebugUrl('invalid url'), 'invalid url');
});

test('a secret token is returned only for its URL and workspace', async () => {
  const secrets = secretStorage();
  await bindTokenToUrl(secrets, 'phone-secret', 'ws://phone.local:9001', 'workspace-a');

  assert.deepEqual(
    await connectionCredentials(settings({ debugUrl: 'ws://phone.local:9001' }), secrets, 'workspace-a'),
    { url: 'ws://phone.local:9001/', token: 'phone-secret' }
  );
  assert.deepEqual(
    await connectionCredentials(settings({ debugUrl: 'ws://attacker.local:9001' }), secrets, 'workspace-a'),
    { url: 'ws://attacker.local:9001/', token: '' }
  );
  assert.deepEqual(
    await connectionCredentials(settings({ debugUrl: 'ws://phone.local:9001' }), secrets, 'workspace-b'),
    { url: 'ws://phone.local:9001/', token: '' }
  );
});

test('legacy plaintext debugToken settings are never read', async () => {
  const secrets = secretStorage({ 'autosdk.debugToken': 'unbound-legacy-secret' });
  const values = settings({ debugUrl: 'ws://phone.local:9001', debugToken: 'plaintext-secret' });

  assert.deepEqual(
    await connectionCredentials(values, secrets, 'workspace-a'),
    { url: 'ws://phone.local:9001/', token: '' }
  );
  assert.equal(await tokenForConfiguration(values, secrets, 'workspace-a'), '');
});

test('the configure form does not prefill another workspace token', async () => {
  const secrets = secretStorage();
  await bindTokenToUrl(secrets, 'workspace-a-secret', 'ws://phone.local:9001', 'workspace-a');

  assert.equal(await tokenForConfiguration(settings({ debugToken: '' }), secrets, 'workspace-b'), '');
  assert.equal(await tokenForConfiguration(settings({ debugToken: '' }), secrets, 'workspace-a'), 'workspace-a-secret');
});

test('binding uses independent hashed keys without exposing URL or path text', async () => {
  const secrets = secretStorage();
  await bindTokenToUrl(secrets, 'new-secret', ' ws://phone.local:9001 ', 'file:///private/project');

  const boundKey = boundTokenSecretKey('ws://phone.local:9001/', 'file:///private/project');
  const workspaceKey = workspaceTokenSecretKey('file:///private/project');
  assert.equal(secrets.values.get(boundKey), 'new-secret');
  assert.equal(secrets.values.get(workspaceKey), 'new-secret');
  assert.doesNotMatch(boundKey, /phone|private|project/);
  assert.doesNotMatch(workspaceKey, /private|project/);
});

test('rebinding a workspace removes its obsolete URL credential', async () => {
  const secrets = secretStorage();
  await bindTokenToUrl(secrets, 'first-secret', 'ws://192.168.1.10:9001', 'workspace-a');
  const firstKey = boundTokenSecretKey('ws://192.168.1.10:9001', 'workspace-a');
  await bindTokenToUrl(secrets, 'second-secret', 'ws://192.168.1.11:9001', 'workspace-a');
  const secondKey = boundTokenSecretKey('ws://192.168.1.11:9001', 'workspace-a');

  assert.equal(secrets.values.has(firstKey), false);
  assert.equal(secrets.values.get(secondKey), 'second-secret');
  assert.equal(secrets.values.get(currentBindingSecretKey('workspace-a')), secondKey);
});

test('a failed rebind preserves the last committed credential', async () => {
  const secrets = secretStorage();
  await bindTokenToUrl(secrets, 'first-secret', 'ws://192.168.1.10:9001', 'workspace-a');
  const currentKey = currentBindingSecretKey('workspace-a');
  const originalStore = secrets.store;
  secrets.store = async (key, value) => {
    if (key === currentKey) throw new Error('SecretStorage unavailable');
    return originalStore(key, value);
  };

  await assert.rejects(
    bindTokenToUrl(secrets, 'second-secret', 'ws://192.168.1.11:9001', 'workspace-a'),
    /SecretStorage unavailable/
  );
  assert.deepEqual(
    await connectionCredentials(settings({ debugUrl: 'ws://192.168.1.10:9001' }), secrets, 'workspace-a'),
    { url: 'ws://192.168.1.10:9001/', token: 'first-secret' }
  );
});

test('a failed secret rebind restores the previous workspace URL', async () => {
  const secrets = secretStorage();
  await bindTokenToUrl(secrets, 'first-secret', 'ws://192.168.1.10:9001', 'workspace-a');
  let workspaceUrl = 'ws://192.168.1.10:9001/';
  const values = {
    get: key => key === 'debugUrl' ? workspaceUrl : '',
    inspect: key => key === 'debugUrl' ? { workspaceValue: workspaceUrl } : undefined,
    update: async (key, value) => { if (key === 'debugUrl') workspaceUrl = value; }
  };
  const currentKey = currentBindingSecretKey('workspace-a');
  const originalStore = secrets.store;
  secrets.store = async (key, value) => {
    if (key === currentKey) throw new Error('SecretStorage unavailable');
    return originalStore(key, value);
  };

  await assert.rejects(
    updateConnectionConfiguration(values, secrets, 'second-secret', 'ws://192.168.1.11:9001', 'workspace-a', 'workspace'),
    /SecretStorage unavailable/
  );
  assert.equal(workspaceUrl, 'ws://192.168.1.10:9001/');
  assert.deepEqual(
    await connectionCredentials(values, secrets, 'workspace-a'),
    { url: 'ws://192.168.1.10:9001/', token: 'first-secret' }
  );
});

test('an empty-window secret failure restores the global URL rather than deleting it', async () => {
  let url = 'ws://previous:9001/';
  const values = { inspect: () => ({ globalValue: url }), update: async (key, value) => { if (key === 'debugUrl') url = value; } };
  const secrets = { get: async () => '', store: async () => { throw new Error('SecretStorage unavailable'); } };
  await assert.rejects(updateConnectionConfiguration(values, secrets, 'token', 'ws://next:9001', 'empty-window', 1, [], 'globalValue'), /unavailable/);
  assert.equal(url, 'ws://previous:9001/');
});

test('a committed rebind remains successful when plaintext cleanup is unavailable', async () => {
  const secrets = secretStorage();
  await bindTokenToUrl(secrets, 'new-secret', 'ws://192.168.1.11:9001', 'workspace-a');
  const values = {
    get: key => key === 'debugUrl' ? 'ws://192.168.1.11:9001/' : 'plaintext-secret',
    inspect: key => key === 'debugToken' ? { globalValue: 'plaintext-secret' } : { workspaceValue: 'ws://192.168.1.11:9001/' },
    update: async (key, value, target) => {
      if (key === 'debugToken' && target === 'global') throw new Error('settings are read-only');
    }
  };

  const result = await updateConnectionConfiguration(
    values, secrets, 'new-secret', 'ws://192.168.1.11:9001', 'workspace-a', 'workspace',
    [{ target: 'global', inspectKey: 'globalValue' }]
  );
  assert.equal(result.canonicalUrl, 'ws://192.168.1.11:9001/');
  assert.equal(result.plaintextCleanupErrors.length, 1);
  assert.deepEqual(
    await connectionCredentials(values, secrets, 'workspace-a'),
    { url: 'ws://192.168.1.11:9001/', token: 'new-secret' }
  );
});
