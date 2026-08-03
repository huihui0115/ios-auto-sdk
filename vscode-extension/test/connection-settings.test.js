const assert = require('node:assert/strict');
const test = require('node:test');
const {
  bindTokenToUrl,
  boundTokenSecretKey,
  canonicalDebugUrl,
  connectionCredentials,
  currentBindingSecretKey,
  tokenForConfiguration,
  updateConnectionConfiguration,
  workspaceTokenSecretKey
} = require('../connection-settings');

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

test('plaintext legacy tokens are available only to the configure form', async () => {
  const secrets = secretStorage({ 'autosdk.debugToken': 'unbound-legacy-secret' });
  const values = settings({ debugUrl: 'ws://phone.local:9001', debugToken: 'plaintext-secret' });

  assert.deepEqual(
    await connectionCredentials(values, secrets, 'workspace-a'),
    { url: 'ws://phone.local:9001/', token: '' }
  );
  assert.equal(await tokenForConfiguration(values, secrets, 'workspace-a'), 'plaintext-secret');
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
