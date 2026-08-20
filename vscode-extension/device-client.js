const crypto = require('crypto');

// The device defaults screenshots to 16 MB; leave headroom for base64 and node JSON.
const DEFAULT_MAX_PAYLOAD = 32 * 1024 * 1024;
const MAX_REQUEST_TIMEOUT_MS = 60 * 60 * 1000;
const MAX_PENDING_REQUESTS = 32;
const MAX_IGNORED_RESPONSES = 128;

function boundedText(value, maximumLength = 1024) {
  if (typeof value !== 'string') return undefined;
  return value.length <= maximumLength ? value : `${value.slice(0, maximumLength)}...`;
}

function requestTimeoutMilliseconds(value, fallback = 30000) {
  const timeout = Number(value);
  const fallbackValue = Number(fallback);
  const boundedFallback = Number.isFinite(fallbackValue)
    ? Math.min(MAX_REQUEST_TIMEOUT_MS, Math.max(1000, fallbackValue))
    : 30000;
  return Number.isFinite(timeout)
    ? Math.min(MAX_REQUEST_TIMEOUT_MS, Math.max(1000, timeout))
    : boundedFallback;
}

function abortError(requestType) {
  const error = new Error(`Cancelled ${requestType || 'device request'}.`);
  error.name = 'AbortError';
  return error;
}

function cleanupPending(pending) {
  if (pending.timer) clearTimeout(pending.timer);
  if (pending.signal && pending.onAbort) pending.signal.removeEventListener('abort', pending.onAbort);
}

class DeviceClient {
  constructor(options) {
    this.credentials = options.credentials;
    this.onState = options.onState || (() => {});
    this.onEvent = options.onEvent || (() => {});
    this.WebSocket = options.WebSocket;
    const maxPending = Number(options.maxPending);
    this.maxPending = Number.isFinite(maxPending)
      ? Math.min(MAX_PENDING_REQUESTS, Math.max(1, Math.floor(maxPending)))
      : 8;
    this.socket = undefined;
    this.connecting = undefined;
    this.rejectConnecting = undefined;
    this.connectionGeneration = 0;
    this.credentialGeneration = 0;
    this.pending = new Map();
    this.ignoredResponses = new Set();
    this.url = '';
    this.token = '';
    this.heartbeat = undefined;
    this.alive = false;
    this.disposed = false;
  }

  setState(state, detail) {
    this.onState(state, detail);
  }

  async ensureConnected(connectTimeoutMs = 10000) {
    if (this.disposed) throw new Error('The AutoSDK device client has stopped.');
    const credentialGeneration = this.credentialGeneration;
    const credentials = await this.credentials();
    if (this.disposed) throw new Error('The AutoSDK device client has stopped.');
    if (credentialGeneration !== this.credentialGeneration) {
      throw new Error('Device connection settings changed while credentials were loading. Retry the request.');
    }
    const url = String(credentials?.url || '').trim();
    const token = String(credentials?.token || '');
    if (!token) throw new Error('Run AutoSDK: Scan Wi-Fi and Add iPhone first.');
    if (!url) throw new Error('Configure an AutoSDK device URL first.');
    if (Buffer.byteLength(token, 'utf8') > 1024) throw new Error('The AutoSDK debug token exceeds 1024 UTF-8 bytes.');
    if (url.length > 2048) throw new Error('The AutoSDK device URL is too long.');
    let parsedURL;
    try { parsedURL = new URL(url); }
    catch (_) { throw new Error('Configure a valid ws:// or wss:// AutoSDK device URL.'); }
    if (!['ws:', 'wss:'].includes(parsedURL.protocol) || !parsedURL.hostname || !parsedURL.port) {
      throw new Error('The AutoSDK device URL must include a ws:// or wss:// host and port.');
    }
    if (parsedURL.hash) throw new Error('The AutoSDK device URL must not contain a fragment.');
    if (parsedURL.username || parsedURL.password) {
      throw new Error('Do not put credentials in the AutoSDK device URL; configure the debug token separately.');
    }
    if (this.socket?.readyState === this.WebSocket.OPEN && this.url === url && this.token === token) {
      return this.socket;
    }
    if ((this.url !== url || this.token !== token) && (this.socket || this.connecting || this.pending.size > 0)) {
      this.disconnect('Device connection settings changed.');
    }
    if (this.connecting) return this.connecting;
    this.url = url;
    this.token = token;
    const generation = ++this.connectionGeneration;
    const handshakeTimeout = Math.min(30000, requestTimeoutMilliseconds(connectTimeoutMs, 10000));
    this.setState('connecting', url);
    let socket;
    try {
      if (!this.WebSocket) this.WebSocket = require('ws');
      socket = new this.WebSocket(url, {
        handshakeTimeout,
        maxPayload: DEFAULT_MAX_PAYLOAD,
        perMessageDeflate: false
      });
    } catch (error) {
      if (this.connectionGeneration === generation) {
        this.socket = undefined;
        this.connecting = undefined;
        this.rejectConnecting = undefined;
        this.setState('disconnected', error.message);
      }
      throw new Error(`Cannot connect to ${url}: ${error.message}`);
    }
    this.socket = socket;
    const connecting = new Promise((resolve, reject) => {
      let settled = false;
      const finish = (error) => {
        if (settled) return;
        settled = true;
        const current = this.connectionGeneration === generation && this.socket === socket;
        if (current) {
          this.connecting = undefined;
          this.rejectConnecting = undefined;
        }
        if (error) {
          if (current) this.setState('disconnected', error.message);
          reject(error);
        } else if (!current) {
          reject(new Error(`Connection attempt to ${url} was replaced.`));
        } else {
          this.startHeartbeat(socket, generation);
          this.setState('ready', url);
          resolve(socket);
        }
      };
      this.rejectConnecting = error => finish(error);
      socket.once('open', () => finish());
      socket.once('error', error => finish(new Error(`Cannot connect to ${url}: ${error.message}`)));
      socket.on('message', data => this.handleMessage(data, socket));
      socket.on('pong', () => {
        if (this.socket === socket && this.connectionGeneration === generation) this.alive = true;
      });
      socket.on('close', () => {
        if (!settled) finish(new Error(`Debug connection closed before it was ready at ${url}.`));
        this.handleClose(new Error(`Debug connection closed at ${url}.`), socket, generation);
      });
    });
    this.connecting = connecting;
    return connecting;
  }

  handleMessage(data, socket = this.socket) {
    if (socket !== this.socket) return;
    const text = data.toString();
    const payloadBytes = Buffer.isBuffer(data) ? data.length : Buffer.byteLength(text, 'utf8');
    let response;
    try {
      response = JSON.parse(text);
    } catch (error) {
      this.onEvent({ type: 'protocolError', error: `Invalid JSON response: ${error.message}`, payloadBytes });
      return;
    }
    const id = typeof response?.id === 'string' ? response.id : String(response?.id || '');
    if (!id) {
      this.onEvent({
        type: 'unidentifiedResponse',
        responseType: boundedText(response?.type, 64),
        ok: response?.ok,
        error: boundedText(response?.error),
        payloadBytes
      });
      return;
    }
    const pending = this.pending.get(id);
    if (!pending) {
      if (this.ignoredResponses.delete(id)) return;
      this.onEvent({
        type: 'orphanResponse',
        id: boundedText(id, 128),
        ok: response?.ok,
        error: boundedText(response?.error),
        payloadBytes
      });
      return;
    }
    this.pending.delete(id);
    cleanupPending(pending);
    pending.resolve(response);
  }

  handleClose(error, socket = this.socket, generation = this.connectionGeneration) {
    if (socket !== this.socket || generation !== this.connectionGeneration) return;
    this.stopHeartbeat();
    this.socket = undefined;
    this.connecting = undefined;
    this.rejectConnecting = undefined;
    this.url = '';
    this.token = '';
    for (const pending of this.pending.values()) {
      cleanupPending(pending);
      pending.reject(error);
    }
    this.pending.clear();
    this.ignoredResponses.clear();
    this.setState('disconnected', error.message);
  }

  startHeartbeat(socket = this.socket, generation = this.connectionGeneration) {
    this.stopHeartbeat();
    this.alive = true;
    this.heartbeat = setInterval(() => {
      if (this.socket !== socket || this.connectionGeneration !== generation) return;
      if (!socket || socket.readyState !== this.WebSocket.OPEN) return;
      if (!this.alive) {
        socket.terminate();
        return;
      }
      this.alive = false;
      try { socket.ping(); }
      catch (_) { socket.terminate(); }
    }, 20000);
  }

  stopHeartbeat() {
    if (this.heartbeat) clearInterval(this.heartbeat);
    this.heartbeat = undefined;
  }

  async request(payload, options = {}) {
    const timeoutMs = requestTimeoutMilliseconds(options.timeoutMs);
    const signal = options.signal;
    if (signal && (typeof signal.aborted !== 'boolean' || typeof signal.addEventListener !== 'function' || typeof signal.removeEventListener !== 'function')) {
      throw new TypeError('The device request signal must be an AbortSignal.');
    }
    if (signal?.aborted) throw abortError(payload.type);
    const socket = await this.ensureConnected(Math.min(timeoutMs, 10000));
    if (signal?.aborted) throw abortError(payload.type);
    if (socket !== this.socket || socket.readyState !== this.WebSocket.OPEN) {
      throw new Error(`Debug connection changed before ${payload.type || 'request'} could be sent. Retry the request.`);
    }
    if (this.pending.size >= this.maxPending) {
      throw new Error(`Too many AutoSDK requests are waiting (${this.maxPending}). Wait for the device before retrying.`);
    }
    const id = crypto.randomUUID();
    const message = JSON.stringify({ ...payload, id, token: this.token, timeoutMs });
    if (Buffer.byteLength(message, 'utf8') > 1024 * 1024) {
      throw new Error('Debug request exceeds the device protocol 1 MB frame limit. Reduce the script or image size.');
    }
    return new Promise((resolve, reject) => {
      const pending = { resolve, reject, timer: undefined, signal, onAbort: undefined };
      pending.onAbort = () => {
        if (this.pending.get(id) !== pending) return;
        this.pending.delete(id);
        this.ignoredResponses.add(id);
        if (this.ignoredResponses.size > MAX_IGNORED_RESPONSES) {
          this.ignoredResponses.delete(this.ignoredResponses.values().next().value);
        }
        cleanupPending(pending);
        reject(abortError(payload.type));
      };
      pending.timer = setTimeout(() => {
        if (this.pending.get(id) !== pending) return;
        this.pending.delete(id);
        cleanupPending(pending);
        reject(new Error(`Timed out waiting for ${payload.type || 'request'} from ${this.url}.`));
      }, timeoutMs);
      this.pending.set(id, pending);
      signal?.addEventListener('abort', pending.onAbort, { once: true });
      if (signal?.aborted) {
        pending.onAbort();
        return;
      }
      try {
        socket.send(message, error => {
          if (!error) return;
          if (this.pending.get(id) !== pending) return;
          this.pending.delete(id);
          cleanupPending(pending);
          pending.reject(new Error(`Failed to send ${payload.type || 'request'}: ${error.message}`));
        });
      } catch (error) {
        if (this.pending.get(id) === pending) {
          this.pending.delete(id);
          cleanupPending(pending);
          pending.reject(new Error(`Failed to send ${payload.type || 'request'}: ${error.message}`));
        }
      }
    });
  }

  disconnect(reason = 'Disconnected.') {
    const socket = this.socket;
    const rejectConnecting = this.rejectConnecting;
    this.connectionGeneration += 1;
    this.credentialGeneration += 1;
    this.stopHeartbeat();
    this.socket = undefined;
    this.connecting = undefined;
    this.rejectConnecting = undefined;
    this.url = '';
    this.token = '';
    if (rejectConnecting) rejectConnecting(new Error(reason));
    if (socket) {
      try {
        if (typeof socket.terminate === 'function') socket.terminate();
        else socket.close();
      } catch (_) { /* already closed */ }
    }
    for (const pending of this.pending.values()) {
      cleanupPending(pending);
      pending.reject(new Error(reason));
    }
    this.pending.clear();
    this.ignoredResponses.clear();
    this.setState('disconnected', reason);
  }

  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this.disconnect('AutoSDK extension stopped.');
  }
}

module.exports = { DeviceClient, requestTimeoutMilliseconds };
