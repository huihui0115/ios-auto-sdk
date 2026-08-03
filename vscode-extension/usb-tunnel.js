const { spawn } = require('child_process');

function portNumber(value, label) {
  const port = Number(value);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`${label} must be an integer between 1 and 65535.`);
  }
  return port;
}

class UsbTunnel {
  constructor(options = {}) {
    this.spawn = options.spawn || spawn;
    this.onOutput = options.onOutput || (() => {});
    this.onExit = options.onExit || (() => {});
    const startupGraceMs = Number(options.startupGraceMs);
    this.startupGraceMs = Number.isFinite(startupGraceMs) ? Math.max(0, startupGraceMs) : 350;
    this.child = undefined;
    this.commandLine = '';
    this.stopping = new WeakSet();
    this.transition = Promise.resolve();
    this.disposed = false;
  }

  get running() {
    return Boolean(this.child && this.child.exitCode === null);
  }

  enqueue(operation) {
    const result = this.transition.then(operation);
    this.transition = result.catch(() => {});
    return result;
  }

  start(options = {}) {
    return this.enqueue(() => this.startNow(options));
  }

  async startNow(options = {}) {
    if (this.disposed) throw new Error('The AutoSDK USB tunnel manager has stopped.');
    const executable = String(options.executable || 'iproxy').trim();
    if (!executable) throw new Error('Configure the iproxy executable path first.');
    const localPort = portNumber(options.localPort, 'USB local port');
    const devicePort = portNumber(options.devicePort, 'USB device port');
    const udid = String(options.udid || '').trim();
    if (udid && !/^[A-Za-z0-9][A-Za-z0-9-]{0,127}$/.test(udid)) {
      throw new Error('USB device UDID must start with a letter or number and contain only letters, numbers, or hyphens (maximum 128 characters).');
    }
    const udidStyle = String(options.udidStyle || 'modern').trim().toLowerCase();
    if (udidStyle !== 'modern' && udidStyle !== 'legacy') {
      throw new Error('iproxy UDID argument style must be modern or legacy.');
    }
    const args = udid && udidStyle === 'modern'
      ? ['-u', udid, String(localPort), String(devicePort)]
      : [String(localPort), String(devicePort)];
    if (udid && udidStyle === 'legacy') args.push(udid);
    const commandLine = [executable, ...args].map(value => /\s/.test(value) ? `"${value}"` : value).join(' ');

    if (this.child) {
      if (this.running && !this.stopping.has(this.child) && this.commandLine === commandLine) {
        return { alreadyRunning: true, commandLine };
      }
      await this.stopNow();
    }

    let child;
    try {
      child = this.spawn(executable, args, {
        shell: false,
        windowsHide: true,
        stdio: ['ignore', 'pipe', 'pipe']
      });
    } catch (error) {
      throw new Error(`Could not start iproxy: ${error.message}`);
    }
    this.child = child;
    this.commandLine = commandLine;
    child.stdout?.on('data', data => this.onOutput(data.toString()));
    child.stderr?.on('data', data => this.onOutput(data.toString()));

    return new Promise((resolve, reject) => {
      let settled = false;
      let spawned = false;
      let startupSucceeded = false;
      let graceTimer;
      const finishStart = error => {
        if (settled) return;
        settled = true;
        if (graceTimer) clearTimeout(graceTimer);
        if (error) reject(error);
        else {
          startupSucceeded = true;
          resolve({ alreadyRunning: false, commandLine });
        }
      };
      child.on('spawn', () => {
        spawned = true;
        graceTimer = setTimeout(() => {
          if (this.child !== child || child.exitCode !== null) {
            finishStart(new Error(`iproxy exited while starting: ${commandLine}`));
            return;
          }
          finishStart();
        }, this.startupGraceMs);
      });
      child.on('error', error => {
        if (!startupSucceeded) {
          if (this.child === child) {
            this.child = undefined;
            this.commandLine = '';
          }
          finishStart(new Error(`Could not start iproxy: ${error.message}`));
        } else {
          this.onOutput(`iproxy process error: ${error.message}\n`);
        }
      });
      child.on('close', (code, signal) => {
        const expected = this.stopping.has(child);
        this.stopping.delete(child);
        if (this.child === child) {
          this.child = undefined;
          this.commandLine = '';
        }
        const detail = signal ? `signal ${signal}` : `exit code ${code ?? 'unknown'}`;
        if (!spawned || !settled) finishStart(new Error(`iproxy exited while starting (${detail}).`));
        if (startupSucceeded) this.onExit({ expected, code, signal, detail });
      });
    });
  }

  stop(timeoutMs = 2000) {
    return this.enqueue(() => this.stopNow(timeoutMs));
  }

  async stopNow(timeoutMs = 2000) {
    const child = this.child;
    if (!child) return false;
    if (child.exitCode !== null) {
      this.stopping.add(child);
      if (this.child === child) {
        this.child = undefined;
        this.commandLine = '';
      }
      return true;
    }
    this.stopping.add(child);
    return new Promise((resolve, reject) => {
      let settled = false;
      let timer;
      const onClose = () => finish();
      const finish = error => {
        if (settled) return;
        settled = true;
        if (timer) clearTimeout(timer);
        child.removeListener('close', onClose);
        if (!error && this.child === child) {
          this.child = undefined;
          this.commandLine = '';
        }
        if (error) reject(error);
        else resolve(true);
      };
      child.once('close', onClose);
      const requestedTimeout = Number(timeoutMs);
      const boundedTimeout = Number.isFinite(requestedTimeout) ? Math.max(0, requestedTimeout) : 2000;
      timer = setTimeout(() => finish(new Error('Timed out waiting for iproxy to stop; the managed process is still retained.')), boundedTimeout);
      try {
        if (!child.killed && !child.kill() && child.exitCode !== null) finish();
      } catch (error) {
        finish(new Error(`Could not stop iproxy: ${error.message}`));
      }
    });
  }

  dispose() {
    this.disposed = true;
    this.onOutput = () => {};
    this.onExit = () => {};
    const child = this.child;
    if (!child) return;
    this.stopping.add(child);
    this.child = undefined;
    this.commandLine = '';
    try { child.kill(); } catch (_) { /* process already exited */ }
  }
}

module.exports = { UsbTunnel, portNumber };
