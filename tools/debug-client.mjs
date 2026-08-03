#!/usr/bin/env node
import { randomUUID } from 'node:crypto';
import { readFile, stat } from 'node:fs/promises';

const MAX_FRAME_BYTES = 1024 * 1024;
const MAX_RESPONSE_BYTES = 32 * 1024 * 1024;
const MAX_SCRIPT_BYTES = MAX_FRAME_BYTES - 4096;
const MAX_TIMEOUT_MS = 60 * 60 * 1000;

function valueAfter(flag) {
  const index = process.argv.indexOf(flag);
  const value = index >= 0 ? process.argv[index + 1] : undefined;
  return value !== undefined && !value.startsWith('--') ? value : undefined;
}

function hasMissingValue(flag) {
  const index = process.argv.indexOf(flag);
  const value = index >= 0 ? process.argv[index + 1] : undefined;
  return index >= 0 && (value === undefined || value.startsWith('--'));
}

function usage() {
  return 'Usage: node tools/debug-client.mjs [--token <token>] [--url ws://127.0.0.1:9001] [--script <js> | --script-file <path>] [--timeout <ms>]';
}

function timeoutMilliseconds(value) {
  const timeout = Number(value);
  return Number.isFinite(timeout)
    ? Math.min(MAX_TIMEOUT_MS, Math.max(1000, timeout))
    : 300000;
}

async function main() {
  for (const flag of ['--token', '--url', '--script', '--script-file', '--timeout']) {
    if (hasMissingValue(flag)) {
      console.error(`${usage()}\n${flag} requires a value.`);
      process.exitCode = 2;
      return;
    }
  }
  const requestedURL = valueAfter('--url');
  const requestedToken = valueAfter('--token');
  const url = requestedURL !== undefined ? requestedURL : 'ws://127.0.0.1:9001';
  const token = requestedToken !== undefined ? requestedToken : process.env.AUTOSDK_DEBUG_TOKEN;
  const inlineScript = valueAfter('--script');
  const scriptFile = valueAfter('--script-file');
  const timeoutMs = timeoutMilliseconds(valueAfter('--timeout'));

  if (!token) {
    console.error(`${usage()}\nProvide --token or set AUTOSDK_DEBUG_TOKEN.`);
    process.exitCode = 2;
    return;
  }
  if (Buffer.byteLength(token, 'utf8') > 1024) {
    console.error('The debug token must not exceed 1024 UTF-8 bytes.');
    process.exitCode = 2;
    return;
  }
  if (url.length > 2048) {
    console.error('The debug URL must not exceed 2048 characters.');
    process.exitCode = 2;
    return;
  }
  if (inlineScript !== undefined && scriptFile !== undefined) {
    console.error(`${usage()}\nChoose either --script or --script-file, not both.`);
    process.exitCode = 2;
    return;
  }

  let parsedURL;
  try {
    parsedURL = new URL(url);
  } catch (_) {
    console.error(`Invalid WebSocket URL: ${url}`);
    process.exitCode = 2;
    return;
  }
  if (!['ws:', 'wss:'].includes(parsedURL.protocol) || !parsedURL.hostname || !parsedURL.port) {
    console.error('The debug URL must be an explicit ws:// or wss:// host and port.');
    process.exitCode = 2;
    return;
  }
  if (parsedURL.hash) {
    console.error('The debug URL must not contain a fragment.');
    process.exitCode = 2;
    return;
  }
  if (parsedURL.username || parsedURL.password) {
    console.error('Do not put credentials in the debug URL; provide the debug token separately.');
    process.exitCode = 2;
    return;
  }

  let script = inlineScript ?? "console.log('debug client connected');";
  if (scriptFile !== undefined) {
    if (!scriptFile || scriptFile.startsWith('--')) {
      console.error(`${usage()}\n--script-file requires a path.`);
      process.exitCode = 2;
      return;
    }
    try {
      const metadata = await stat(scriptFile);
      if (!metadata.isFile()) throw new Error('The script path is not a regular file.');
      if (metadata.size > MAX_SCRIPT_BYTES) {
        throw new Error(`The script file exceeds the ${MAX_SCRIPT_BYTES} byte protocol budget.`);
      }
      script = await readFile(scriptFile, 'utf8');
      if (Buffer.byteLength(script, 'utf8') > MAX_SCRIPT_BYTES) {
        throw new Error(`The script file exceeds the ${MAX_SCRIPT_BYTES} byte protocol budget.`);
      }
    } catch (error) {
      console.error(`Unable to read script file ${scriptFile}: ${error.message}`);
      process.exitCode = 2;
      return;
    }
  }

  if (Buffer.byteLength(script, 'utf8') > MAX_SCRIPT_BYTES) {
    console.error(`The script exceeds the ${MAX_SCRIPT_BYTES} byte protocol budget.`);
    process.exitCode = 2;
    return;
  }

  const id = randomUUID();
  const message = JSON.stringify({ id, token, type: 'run', script, timeoutMs });
  const messageBytes = Buffer.byteLength(message, 'utf8');
  if (messageBytes > MAX_FRAME_BYTES) {
    console.error(`Debug request is ${messageBytes} bytes and exceeds the 1 MB protocol frame limit.`);
    process.exitCode = 2;
    return;
  }

  let socket;
  try {
    socket = new WebSocket(parsedURL.href);
  } catch (error) {
    console.error(`Unable to open ${url}: ${error.message}`);
    process.exitCode = 2;
    return;
  }

  let settled = false;
  let timer;
  const finish = code => {
    if (settled) return;
    settled = true;
    clearTimeout(timer);
    try { socket.close(); } catch (_) { /* socket may already be closed */ }
    process.exitCode = code;
  };
  timer = setTimeout(() => {
    console.error(`Timed out waiting for ${url}`);
    finish(1);
  }, timeoutMs);
  socket.addEventListener('open', () => {
    try {
      socket.send(message);
    } catch (error) {
      console.error(`Unable to send the debug request: ${error.message}`);
      finish(1);
    }
  });
  socket.addEventListener('message', event => {
    try {
      if (typeof event.data !== 'string' || Buffer.byteLength(event.data, 'utf8') > MAX_RESPONSE_BYTES) {
        throw new Error(`Debug response exceeds the ${MAX_RESPONSE_BYTES} byte limit.`);
      }
      const response = JSON.parse(event.data);
      if (!response || typeof response !== 'object' || Array.isArray(response) ||
          (response.ok !== true && response.ok !== false)) {
        throw new Error('Debug response must be an object with a boolean ok field.');
      }
      if (String(response?.id || '') !== id) {
        console.error('Ignored an uncorrelated debug response.');
        return;
      }
      console.log(JSON.stringify(response, null, 2));
      finish(response.ok === false ? 1 : 0);
    } catch (error) {
      console.error(`Invalid JSON response: ${error.message}`);
      finish(1);
    }
  });
  socket.addEventListener('error', event => {
    const detail = event?.error?.message || event?.message;
    console.error(`Unable to connect to ${url}${detail ? `: ${detail}` : ''}`);
    finish(1);
  });
  socket.addEventListener('close', () => {
    if (!settled) {
      console.error(`Connection closed before a response from ${url}`);
      finish(1);
    }
  });
}

await main();
