const DEFAULT_MAX_NODES = 1000;
const MAX_NODES = 2000;
const MAX_ERROR_LENGTH = 2048;
const MAX_PNG_BASE64_LENGTH = 24 * 1024 * 1024;

function responseError(response, fallback = 'The device returned an invalid response.') {
  if (typeof response?.error === 'string' && response.error.trim()) {
    return response.error.length <= MAX_ERROR_LENGTH
      ? response.error
      : `${response.error.slice(0, MAX_ERROR_LENGTH)}...`;
  }
  if (response?.error && typeof response.error === 'object') {
    try {
      const encoded = JSON.stringify(response.error);
      if (encoded) return encoded.length <= MAX_ERROR_LENGTH ? encoded : `${encoded.slice(0, MAX_ERROR_LENGTH)}...`;
    } catch (_) { /* fall through to the bounded generic error */ }
  }
  if (Number.isFinite(Number(response?.code))) return `${fallback} (code ${Number(response.code)})`;
  return fallback;
}

function successful(response, operation) {
  if (!response || typeof response !== 'object' || Array.isArray(response)) {
    throw new Error(`Device returned a malformed ${operation} response.`);
  }
  if (response.ok !== true) throw new Error(responseError(response, `${operation} failed.`));
  return response;
}

function maxNodes(value, fallback = DEFAULT_MAX_NODES) {
  const parsed = Number(value);
  const parsedFallback = Number(fallback);
  const safeFallback = Number.isFinite(parsedFallback)
    ? Math.min(MAX_NODES, Math.max(1, Math.floor(parsedFallback)))
    : DEFAULT_MAX_NODES;
  return Number.isFinite(parsed) ? Math.min(MAX_NODES, Math.max(1, Math.floor(parsed))) : safeFallback;
}

function pngBase64(value, operation) {
  if (typeof value !== 'string' || !value || value.length > MAX_PNG_BASE64_LENGTH) {
    throw new Error(`Device returned an invalid or oversized PNG for ${operation}.`);
  }
  if (!/^iVBORw0KGgo[A-Za-z0-9+/]*={0,2}$/.test(value)) {
    throw new Error(`Device returned non-PNG screenshot data for ${operation}.`);
  }
  return value;
}

function nodeArray(value, operation) {
  if (!Array.isArray(value) || value.length > MAX_NODES) {
    throw new Error(`Device returned an invalid or oversized node list for ${operation}.`);
  }
  if (value.some(node => !node || typeof node !== 'object' || Array.isArray(node))) {
    throw new Error(`Device returned a malformed node in ${operation}.`);
  }
  return value;
}

function objectValue(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`Device returned invalid ${label}.`);
  }
  return value;
}

function boundedIdentifier(value, fallback = '') {
  return typeof value === 'string' && value.length <= 128 ? value : fallback;
}

class InspectorService {
  constructor(request) {
    if (typeof request !== 'function') throw new TypeError('InspectorService requires a request function.');
    this.request = request;
    this.visualTail = Promise.resolve();
  }

  enqueue(task) {
    const scheduled = this.visualTail.then(task, task);
    this.visualTail = scheduled.catch(() => {});
    return scheduled;
  }

  screenshot(signal) {
    return this.enqueue(async () => {
      const response = successful(await this.request({ type: 'screenshot' }, { signal }), 'screenshot capture');
      return pngBase64(response.pngBase64, 'screenshot capture');
    });
  }

  nodes(selector, signal) {
    return this.enqueue(async () => {
      const payload = { type: 'nodes' };
      if (selector !== undefined) payload.selector = selector;
      const response = successful(await this.request(payload, { signal }), 'node capture');
      return nodeArray(response.nodes, 'node capture');
    });
  }

  snapshot(options = {}) {
    return this.enqueue(async () => {
      const limit = maxNodes(options.maxNodes);
      const response = successful(await this.request(
        { type: 'inspectSnapshot', options: { maxNodes: limit } },
        { signal: options.signal }
      ), 'Inspector snapshot');
      const protocolVersion = Number(response.protocolVersion);
      const capturedAtMs = Number(response.capturedAtMs);
      const durationMs = Number(response.durationMs);
      return {
        protocolVersion: Number.isFinite(protocolVersion) ? protocolVersion : 0,
        snapshotId: boundedIdentifier(response.snapshotId),
        capturedAtMs: Number.isFinite(capturedAtMs) && capturedAtMs >= 0 ? capturedAtMs : 0,
        durationMs: Number.isFinite(durationMs) && durationMs >= 0 ? durationMs : 0,
        pngBase64: pngBase64(response.pngBase64, 'Inspector snapshot'),
        nodes: nodeArray(response.nodes, 'Inspector snapshot'),
        deviceInfo: objectValue(response.deviceInfo, 'Inspector device information'),
        truncated: Boolean(response.truncated)
      };
    });
  }

  pixel(coordinates, signal) {
    return this.enqueue(async () => {
      const response = successful(await this.request({ type: 'pixelColor', ...coordinates }, { signal }), 'pixel inspection');
      return objectValue(response.color, 'pixel color');
    });
  }

  ocr(region, signal) {
    return this.enqueue(async () => {
      const response = successful(await this.request({
        type: 'testOCR',
        region: { ...region, mode: 'fast', maxResults: 100 }
      }, { signal }), 'OCR test');
      return nodeArray(response.items, 'OCR test');
    });
  }

  deployAndFindImage(template, signal) {
    return this.enqueue(async () => {
      const deployed = successful(await this.request({
        type: 'putAsset',
        name: template.name,
        dataBase64: template.dataBase64
      }, { signal }), 'image deployment');
      const response = successful(await this.request({
        type: 'findImage',
        assetName: template.name,
        options: { threshold: 0.9, maxCandidates: 100000, maxComparedPixels: 50000000 }
      }, { signal }), 'image test');
      const match = response.match === undefined || response.match === null
        ? { found: false }
        : objectValue(response.match, 'image match');
      return { match, assetPath: boundedIdentifier(deployed.path, `debug-assets/${template.name}`) };
    });
  }

  nodeAction(payload, signal) {
    return this.enqueue(async () => {
      successful(await this.request({ type: 'nodeAction', ...payload }, { signal }), 'node action');
    });
  }
}

module.exports = { InspectorService, maxNodes, responseError };
