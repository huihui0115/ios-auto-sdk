const path = require('path');
const { spawn } = require('child_process');

const MAX_TOOL_OUTPUT_BYTES = 256 * 1024;
const TOOL_TIMEOUT_MS = 8000;

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

function toolCandidates(iproxyPath, tool, platform = process.platform) {
  const configured = String(iproxyPath || '').trim();
  const executable = platform === 'win32' ? `${tool}.exe` : tool;
  const candidates = [];
  if (configured) {
    const directory = path.dirname(configured);
    if (directory && directory !== '.') candidates.push(path.join(directory, executable));
  }
  candidates.push(executable);
  if (platform === 'win32') candidates.push(tool);
  return unique(candidates);
}

function parseDeviceIds(output) {
  return unique(String(output || '')
    .split(/\r?\n/)
    .map(value => value.trim())
    .filter(value => /^[A-Za-z0-9][A-Za-z0-9-]{5,127}$/.test(value)));
}

function runTool(executable, args, options = {}) {
  const spawnProcess = options.spawn || spawn;
  const timeoutMs = Number.isFinite(Number(options.timeoutMs))
    ? Math.max(100, Math.min(30000, Number(options.timeoutMs)))
    : TOOL_TIMEOUT_MS;
  return new Promise((resolve, reject) => {
    let child;
    try {
      child = spawnProcess(executable, args, {
        shell: false,
        windowsHide: true,
        stdio: ['ignore', 'pipe', 'pipe']
      });
    } catch (error) {
      reject(new Error(`${executable} could not start: ${error.message}`));
      return;
    }
    let settled = false;
    let stdout = '';
    let stderr = '';
    let outputBytes = 0;
    let timer;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) reject(error);
      else resolve(value);
    };
    const append = (target, data) => {
      const text = data.toString();
      outputBytes += Buffer.byteLength(text, 'utf8');
      if (outputBytes > MAX_TOOL_OUTPUT_BYTES) {
        try { child.kill(); } catch (_) { /* process already exited */ }
        finish(new Error(`${executable} produced too much output.`));
        return target;
      }
      return target + text;
    };
    child.stdout?.on('data', data => { stdout = append(stdout, data); });
    child.stderr?.on('data', data => { stderr = append(stderr, data); });
    child.once('error', error => finish(new Error(`${executable} could not start: ${error.message}`)));
    child.once('close', code => {
      if (code !== 0) {
        const detail = stderr.trim().slice(0, 1024) || `exit code ${code ?? 'unknown'}`;
        finish(new Error(`${executable} failed: ${detail}`));
        return;
      }
      finish(undefined, { stdout, stderr });
    });
    timer = setTimeout(() => {
      try { child.kill(); } catch (_) { /* process already exited */ }
      finish(new Error(`${executable} timed out after ${timeoutMs} ms.`));
    }, timeoutMs);
  });
}

async function firstSuccessful(candidates, args, run) {
  const errors = [];
  for (const executable of candidates) {
    try {
      return { executable, result: await run(executable, args) };
    } catch (error) {
      errors.push(`${path.basename(executable)}: ${error.message}`);
    }
  }
  throw new Error(errors.join(' | '));
}

function deviceName(output) {
  const value = String(output || '').split(/\r?\n/).map(item => item.trim()).find(Boolean) || '';
  return value.replace(/[\u0000-\u001f\u007f]/g, '').slice(0, 128);
}

async function discoverUsbDevices(options = {}) {
  const platform = options.platform || process.platform;
  const iproxyPath = options.iproxyPath || 'iproxy';
  const run = options.run || ((executable, args) => runTool(executable, args, options));
  const listCandidates = toolCandidates(iproxyPath, 'idevice_id', platform);
  let listed;
  try {
    listed = await firstSuccessful(listCandidates, ['-l'], run);
  } catch (error) {
    throw new Error(`Could not search for USB iPhones. Install libimobiledevice or place idevice_id beside iproxy. ${error.message}`);
  }
  const ids = parseDeviceIds(listed.result.stdout);
  const infoCandidates = toolCandidates(iproxyPath, 'ideviceinfo', platform);
  const devices = [];
  for (const id of ids) {
    let name = '';
    try {
      const info = await firstSuccessful(infoCandidates, ['-u', id, '-k', 'DeviceName'], run);
      name = deviceName(info.result.stdout);
    } catch (_) { /* the UDID is still usable when ideviceinfo is unavailable */ }
    devices.push({ id, name: name || 'iPhone', connectionType: 'USB' });
  }
  return { devices, executable: listed.executable };
}

module.exports = {
  MAX_TOOL_OUTPUT_BYTES,
  deviceName,
  discoverUsbDevices,
  parseDeviceIds,
  runTool,
  toolCandidates
};
