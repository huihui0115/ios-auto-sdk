const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const test = require('node:test');
const {
  deviceName,
  discoverUsbDevices,
  parseDeviceIds,
  runTool,
  toolCandidates
} = require('../device-discovery');

test('device discovery parses and deduplicates safe USB device IDs', () => {
  assert.deepEqual(parseDeviceIds('00008110-ABCDEF123456\r\ninvalid id\n00008110-ABCDEF123456\n1234567890\n'), [
    '00008110-ABCDEF123456',
    '1234567890'
  ]);
  assert.equal(deviceName('\n Xiao iPhone \r\nignored\n'), 'Xiao iPhone');
});

test('device discovery reuses tools beside the configured iproxy', () => {
  assert.deepEqual(toolCandidates('C:\\MobileDevice\\iproxy.exe', 'idevice_id', 'win32'), [
    'C:\\MobileDevice\\idevice_id.exe',
    'idevice_id.exe',
    'idevice_id'
  ]);
});

test('device discovery lists phones and resolves friendly names', async () => {
  const calls = [];
  const run = async (executable, args) => {
    calls.push({ executable, args });
    if (args[0] === '-l') return { stdout: 'phone-1\nphone-2\n', stderr: '' };
    if (args[1] === 'phone-1') return { stdout: 'Work iPhone\n', stderr: '' };
    throw new Error('name unavailable');
  };
  const result = await discoverUsbDevices({ iproxyPath: 'iproxy', platform: 'linux', run });

  assert.deepEqual(result.devices, [
    { id: 'phone-1', name: 'Work iPhone', connectionType: 'USB' },
    { id: 'phone-2', name: 'iPhone', connectionType: 'USB' }
  ]);
  assert.deepEqual(calls[0], { executable: 'idevice_id', args: ['-l'] });
});

test('device discovery reports a useful error when USB tools are missing', async () => {
  await assert.rejects(
    discoverUsbDevices({ run: async () => { throw new Error('ENOENT'); } }),
    /Install libimobiledevice.*idevice_id beside iproxy/
  );
});

test('device discovery tool runner never invokes a shell', async () => {
  const calls = [];
  const spawn = (command, args, options) => {
    calls.push({ command, args, options });
    const child = new EventEmitter();
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    child.kill = () => true;
    queueMicrotask(() => {
      child.stdout.emit('data', Buffer.from('phone-id\n'));
      child.emit('close', 0);
    });
    return child;
  };
  const result = await runTool('idevice_id', ['-l'], { spawn, timeoutMs: 1000 });

  assert.equal(result.stdout, 'phone-id\n');
  assert.equal(calls[0].options.shell, false);
  assert.equal(calls[0].options.windowsHide, true);
});
