const crypto = require('crypto');

const BOUND_TOKEN_PREFIX = 'autosdk.debugToken.binding.';
const CURRENT_BINDING_PREFIX = 'autosdk.debugToken.current.';
const LEGACY_TOKEN_SECRET = 'autosdk.debugToken';
const WORKSPACE_TOKEN_PREFIX = 'autosdk.debugToken.workspace.';

function canonicalDebugUrl(value) {
  const url = String(value || '').trim();
  if (!url) return '';
  try { return new URL(url).href; }
  catch (_) { return url; }
}

function secretDigest(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest('hex');
}

function boundTokenSecretKey(url, scope) {
  return `${BOUND_TOKEN_PREFIX}${secretDigest(`${String(scope || '')}\0${canonicalDebugUrl(url)}`)}`;
}

function workspaceTokenSecretKey(scope) {
  return `${WORKSPACE_TOKEN_PREFIX}${secretDigest(scope)}`;
}

function currentBindingSecretKey(scope) {
  return `${CURRENT_BINDING_PREFIX}${secretDigest(scope)}`;
}

async function connectionCredentials(settings, secrets, scope) {
  const url = canonicalDebugUrl(settings.get('debugUrl'));
  const bindingKey = boundTokenSecretKey(url, scope);
  const currentBinding = String((await secrets.get(currentBindingSecretKey(scope))) || '');
  const token = url && currentBinding === bindingKey
    ? String((await secrets.get(bindingKey)) || '')
    : '';
  return { url, token };
}

async function tokenForConfiguration(settings, secrets, scope) {
  // SecretStorage is the only credential source; the legacy plaintext
  // autosdk.debugToken setting is never read (it is removed on save).
  const secretToken = await secrets.get(workspaceTokenSecretKey(scope));
  return String(secretToken || '');
}

async function bindTokenToUrl(secrets, token, url, scope) {
  const value = String(token || '');
  const bindingKey = boundTokenSecretKey(url, scope);
  const currentKey = currentBindingSecretKey(scope);
  const previousBinding = String((await secrets.get(currentKey)) || '');

  // Commit the new credential before removing the previous binding so a
  // partial SecretStorage failure never destroys the last working setup.
  await secrets.store(bindingKey, value);
  await secrets.store(workspaceTokenSecretKey(scope), value);
  await secrets.store(currentKey, bindingKey);
  if (previousBinding && previousBinding !== bindingKey && previousBinding.startsWith(BOUND_TOKEN_PREFIX)) {
    try { await secrets.delete(previousBinding); } catch (_) { /* inaccessible stale binding */ }
  }
  try { await secrets.delete(LEGACY_TOKEN_SECRET); } catch (_) { /* legacy cleanup is best effort */ }
}

async function updateConnectionConfiguration(settings, secrets, token, url, scope, target, cleanupTargets = []) {
  const canonicalUrl = canonicalDebugUrl(url);
  const previousWorkspaceUrl = settings.inspect?.('debugUrl')?.workspaceValue;
  await settings.update('debugUrl', canonicalUrl, target);
  try {
    await bindTokenToUrl(secrets, token, canonicalUrl, scope);
  } catch (error) {
    try {
      await settings.update('debugUrl', previousWorkspaceUrl, target);
    } catch (rollbackError) {
      throw new Error(`${error.message} Restoring the previous device URL also failed: ${rollbackError.message}`);
    }
    throw error;
  }
  const cleanupErrors = [];
  const primaryCleanup = { target, inspectKey: undefined };
  const inspection = settings.inspect?.('debugToken');
  for (const cleanup of [primaryCleanup, ...cleanupTargets]) {
    if (!cleanup || cleanup.target === undefined) continue;
    if (cleanup.inspectKey && inspection && inspection[cleanup.inspectKey] === undefined) continue;
    try {
      await settings.update('debugToken', undefined, cleanup.target);
    } catch (error) {
      cleanupErrors.push(error);
    }
  }
  return { canonicalUrl, plaintextCleanupErrors: cleanupErrors };
}

module.exports = {
  bindTokenToUrl,
  boundTokenSecretKey,
  canonicalDebugUrl,
  connectionCredentials,
  currentBindingSecretKey,
  tokenForConfiguration,
  updateConnectionConfiguration,
  workspaceTokenSecretKey
};
