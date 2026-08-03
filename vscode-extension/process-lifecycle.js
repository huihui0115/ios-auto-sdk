const { spawn } = require('child_process');
const terminatingProcesses = new WeakSet();

function terminateOwnedProcess(child, options = {}) {
  if (!child || child.exitCode !== null || terminatingProcesses.has(child)) return false;
  terminatingProcesses.add(child);
  const platform = options.platform || process.platform;
  const spawnProcess = options.spawn || spawn;
  const directKill = () => {
    try {
      const requested = child.kill();
      if (!requested) terminatingProcesses.delete(child);
      return requested;
    } catch (_) {
      terminatingProcesses.delete(child);
      return false;
    }
  };
  if (platform !== 'win32' || !Number.isInteger(child.pid) || child.pid <= 0) {
    return directKill();
  }

  let fallbackUsed = false;
  const fallback = () => {
    if (fallbackUsed || child.exitCode !== null) return false;
    fallbackUsed = true;
    return directKill();
  };
  try {
    const killer = spawnProcess('taskkill', ['/PID', String(child.pid), '/T', '/F'], {
      shell: false,
      windowsHide: true,
      stdio: 'ignore'
    });
    killer.once('error', fallback);
    killer.once('close', code => { if (code !== 0) fallback(); });
    return true;
  } catch (_) {
    return fallback();
  }
}

module.exports = { terminateOwnedProcess };
