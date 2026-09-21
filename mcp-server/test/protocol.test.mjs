import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';

// Also exercise an independently unpacked, production-only release package.
const serverPath = process.env.AUTOSDK_MCP_TEST_SERVER || fileURLToPath(new URL('../server.mjs', import.meta.url));
for (const mode of ['legacy', { pin: '2026-07-28' }]) {
  test(`official client stdio end-to-end: ${JSON.stringify(mode)}`, { timeout: 20000 }, async () => {
    const client = new Client({ name: 'autosdk-test', version: '1.0.0' }, { versionNegotiation: { mode } });
    const transport = new StdioClientTransport({ command: process.execPath, args: [serverPath], stderr: 'pipe' });
    let errors = ''; transport.stderr?.on('data', data => { errors += data; });
    try {
      await client.connect(transport);
      const tools = (await client.listTools()).tools;
      assert.deepEqual(tools.map(t => t.name).sort(), ['get_api', 'search_api', 'validate_script']);
      assert.ok(tools.every(t => t.annotations.readOnlyHint === true && t.annotations.openWorldHint === false));
      const search = await client.callTool({ name: 'search_api', arguments: { query: '小白点' } });
      assert.ok(search.structuredContent.results.length);
      const api = await client.callTool({ name: 'get_api', arguments: { name: 'device.setAssistiveTouchEnabled' } });
      assert.equal(api.structuredContent.found, true);
      const valid = await client.callTool({ name: 'validate_script', arguments: { code: 'logd("ok");' } });
      assert.equal(valid.structuredContent.valid, true, JSON.stringify(valid));
      assert.equal(valid.structuredContent.executed, false);
      const invalid = await client.callTool({ name: 'validate_script', arguments: { code: 'device.madeUp();' } });
      assert.equal(invalid.structuredContent.valid, false);
      const malformed = await client.callTool({ name: 'search_api', arguments: { query: 'x', limit: -1 } });
      assert.equal(malformed.isError, true);
      const resource = await client.readResource({ uri: 'autosdk://guide' });
      assert.match(resource.contents[0].text, /不执行代码/);
      const resources = await client.listResources();
      assert.equal(resources.resources.length, 1);
      assert.equal(errors, '');
    } finally { await client.close(); }
  });
}
test('2024 protocol handshake and stdout contain JSON-RPC only', { timeout: 10000 }, async () => {
  const child = spawn(process.execPath, [serverPath], { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
  const pending = new Map(), lines = createInterface({ input: child.stdout });
  const failures = [];
  lines.on('line', line => { try { const msg = JSON.parse(line); assert.equal(msg.jsonrpc, '2.0'); pending.get(msg.id)?.(msg); } catch (error) { failures.push(error); } });
  const request = (id, method, params) => new Promise(resolve => { pending.set(id, resolve); child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n'); });
  try {
    const init = await request(1, 'initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'old-client', version: '1.0' } });
    assert.equal(init.result.protocolVersion, '2024-11-05');
    child.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n');
    const list = await request(2, 'tools/list', {});
    assert.equal(list.result.tools.length, 3);
    const unknown = await request(3, 'tools/call', { name: 'run_phone_script', arguments: {} });
    assert.ok(unknown.error || unknown.result?.isError);
    assert.deepEqual(failures, []);
  } finally { lines.close(); child.stdin.end(); child.kill(); }
});
test('config is portable absolute stdio command without shell, token or port', () => {
  const result = spawnSync(process.execPath, [serverPath, '--config'], { encoding: 'utf8', windowsHide: true });
  assert.equal(result.status, 0, result.stderr);
  const config = JSON.parse(result.stdout).mcpServers['autosdk-docs'];
  assert.equal(config.command, process.execPath);
  assert.deepEqual(config.args, [serverPath]);
  assert.deepEqual(Object.keys(config).sort(), ['args', 'command']);
});
