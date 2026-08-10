const { generatedCode, inputText, nodeAction, ocrRegion, point, selectorObject } = require('./inspector-input');

const MAX_REQUEST_ID_LENGTH = 128;

function requestId(value, fallback) {
  return typeof value === 'string' && value && value.length <= MAX_REQUEST_ID_LENGTH ? value : fallback;
}

function abortError(error) {
  return error?.name === 'AbortError';
}

class LatestTaskQueue {
  constructor() {
    this.tail = Promise.resolve();
    this.generations = new Map();
    this.disposed = false;
  }

  schedule(key, task) {
    if (this.disposed) return Promise.resolve(false);
    const generation = (this.generations.get(key) || 0) + 1;
    this.generations.set(key, generation);
    const current = () => !this.disposed && this.generations.get(key) === generation;
    const execute = async () => {
      if (!current()) return false;
      await task(current);
      return true;
    };
    const scheduled = this.tail.then(execute, execute);
    this.tail = scheduled.catch(() => {});
    return scheduled;
  }

  invalidate() {
    for (const [key, generation] of this.generations) this.generations.set(key, generation + 1);
  }

  dispose() {
    this.disposed = true;
    this.invalidate();
  }
}

class InspectorSession {
  constructor(options) {
    if (!options?.service) throw new TypeError('InspectorSession requires an InspectorService.');
    if (typeof options.postMessage !== 'function') throw new TypeError('InspectorSession requires postMessage.');
    this.service = options.service;
    this.postMessage = options.postMessage;
    this.selectImage = options.selectImage || (async () => undefined);
    this.requestInput = options.requestInput || (async () => undefined);
    this.copyCode = options.copyCode || (async () => {});
    this.insertCode = options.insertCode || (async () => {});
    this.saveSnapshot = options.saveSnapshot || (async () => {});
    this.delay = options.delay || (milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds)));
    this.maxNodes = options.maxNodes;
    this.queue = new LatestTaskQueue();
    this.abortController = new AbortController();
    this.visible = true;
    this.disposed = false;
    this.sequence = 0;
    this.lastSnapshot = undefined;
  }

  nextRequestId(value) {
    this.sequence += 1;
    return requestId(value, `host-${this.sequence}`);
  }

  post(type, operation, id, payload = {}) {
    if (this.disposed) return;
    this.postMessage({ type, operation, requestId: id, ...payload });
  }

  signal() {
    return this.abortController.signal;
  }

  setVisible(visible) {
    this.visible = Boolean(visible);
    if (!this.visible) {
      this.abortController.abort();
      this.queue.invalidate();
    } else if (this.abortController.signal.aborted) {
      this.abortController = new AbortController();
    }
  }

  run(operation, messageId, status, task, resultType, queueKey = operation) {
    const id = this.nextRequestId(messageId);
    this.post('operationStart', operation, id, { message: status });
    return this.queue.schedule(queueKey, async isCurrent => {
      if (!this.visible || this.signal().aborted) return;
      try {
        const payload = await task(this.signal());
        if (isCurrent() && this.visible && payload !== undefined) this.post(resultType, operation, id, payload);
      } catch (error) {
        if (!abortError(error) && isCurrent() && this.visible) this.post('error', operation, id, { message: error.message });
      } finally {
        this.post('operationEnd', operation, id);
      }
    }).then(executed => {
      if (!executed) this.post('operationEnd', operation, id);
      return executed;
    });
  }

  refresh(messageId) {
    return this.run('snapshot', messageId, 'Capturing screenshot and node tree...', async signal => {
      const snapshot = await this.service.snapshot({ maxNodes: this.maxNodes, signal });
      this.lastSnapshot = snapshot;
      return snapshot;
    }, 'snapshot');
  }

  async handleMessage(message) {
    if (this.disposed || !message || typeof message !== 'object') return;
    const id = message.requestId;
    if (message.type === 'ready' || message.type === 'refresh') {
      await this.refresh(id);
      return;
    }
    if (message.type === 'testSelector') {
      const selector = selectorObject(message.selector);
      await this.run('selector', id, 'Testing selector...', async signal => ({
        nodes: await this.service.nodes(selector, signal)
      }), 'selectorResult');
      return;
    }
    if (message.type === 'testImage') {
      await this.run('image', id, 'Choose and test an image template...', async signal => {
        const template = await this.selectImage(signal);
        if (!template || signal.aborted) return undefined;
        return this.service.deployAndFindImage(template, signal);
      }, 'imageResult');
      return;
    }
    if (message.type === 'testOCR') {
      const region = ocrRegion(message.region);
      await this.run('ocr', id, 'Running OCR...', async signal => ({
        items: await this.service.ocr(region, signal), region
      }), 'ocrResult');
      return;
    }
    if (message.type === 'pixelColor') {
      const coordinates = point(message.x, message.y);
      await this.run('pixel', id, 'Reading pixel color...', async signal => ({
        color: await this.service.pixel(coordinates, signal)
      }), 'pixelColor');
      return;
    }
    if (message.type === 'nodeAction') {
      const action = nodeAction(message.action);
      const payload = { action };
      if (message.selector !== undefined) payload.selector = selectorObject(message.selector);
      if (message.x !== undefined || message.y !== undefined) Object.assign(payload, point(message.x, message.y));
      if (!payload.selector && payload.x === undefined) throw new Error('Node action requires a selector or point.');
      if (!payload.selector && payload.action !== 'click') throw new Error('Only coordinate clicks can omit a selector.');
      if (payload.action === 'input' && !payload.selector) throw new Error('Node input requires a selector.');
      await this.run('action', id, `Running ${action}...`, async signal => {
        if (payload.action === 'input') {
          const text = await this.requestInput();
          if (text === undefined || signal.aborted) return undefined;
          payload.text = inputText(text);
        }
        await this.service.nodeAction(payload, signal);
        await this.delay(250);
        if (signal.aborted) return undefined;
        const snapshot = await this.service.snapshot({ maxNodes: this.maxNodes, signal });
        this.lastSnapshot = snapshot;
        return { ...snapshot, notice: `${action} completed` };
      }, 'snapshot', `action:${this.nextRequestId(id)}`);
      return;
    }
    if (message.type === 'copyCode') {
      await this.copyCode(generatedCode(message.code));
      this.post('notice', 'code', this.nextRequestId(id), { message: 'Code copied' });
      return;
    }
    if (message.type === 'insertCode') {
      await this.insertCode(generatedCode(message.code));
      this.post('notice', 'code', this.nextRequestId(id), { message: 'Code inserted' });
      return;
    }
    if (message.type === 'saveSnapshot') {
      if (!this.lastSnapshot) throw new Error('Capture an Inspector snapshot before exporting it.');
      const saved = await this.saveSnapshot(this.lastSnapshot);
      if (saved !== false) this.post('notice', 'export', this.nextRequestId(id), { message: 'Snapshot exported' });
    }
  }

  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this.abortController.abort();
    this.queue.dispose();
    this.lastSnapshot = undefined;
  }
}

module.exports = { InspectorSession, LatestTaskQueue };
