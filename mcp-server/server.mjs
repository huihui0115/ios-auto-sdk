#!/usr/bin/env node
import { fileURLToPath } from 'node:url';
import { McpServer } from '@modelcontextprotocol/server';
import { serveStdio, StdioServerTransport } from '@modelcontextprotocol/server/stdio';
import { z } from 'zod';
import { catalog, instructions, caveats, searchApi, getApi } from './catalog.mjs';
import { createValidator, MAX_SCRIPT_LENGTH } from './validator.mjs';

const args = process.argv.slice(2);
if (args.length) {
  if (args.length !== 1 || args[0] !== '--config') {
    console.error('Usage: node server.mjs [--config]'); process.exitCode = 1;
  } else {
    // Explicit CLI mode only. A live MCP session never logs to stdout.
    console.log(JSON.stringify({ mcpServers: { 'autosdk-docs': {
      command: process.execPath, args: [fileURLToPath(import.meta.url)]
    } } }, null, 2));
  }
} else {
  const validator = createValidator();
  const annotations = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };
  const result = (value, isError = false) => ({ content: [{ type: 'text', text: JSON.stringify(value) }], structuredContent: value, ...(isError ? { isError } : {}) });
  const handle = serveStdio(() => {
    const server = new McpServer({ name: 'autosdk-docs', version: catalog.sdkVersion }, { instructions });
    server.registerTool('search_api', {
      description: '搜索本地 AutoSDK 真实函数、类型与中文文档。写脚本前先查；返回 name 可交给 get_api。不是手机操作工具。', annotations,
      inputSchema: z.object({ query: z.string().trim().min(1).max(200), limit: z.number().int().min(1).max(20).default(8), offset: z.number().int().min(0).max(10000).default(0) }).strict()
    }, ({ query, limit, offset }) => result(searchApi(query, limit, offset)));
    server.registerTool('get_api', {
      description: '按 search_api 的精确 name 读取声明、重载、参数、返回值、原始文档示例和限制；类型名可查结构，doc:N 可查文档组。未找到时不得编造。', annotations,
      inputSchema: z.object({ name: z.string().trim().min(1).max(200) }).strict()
    }, ({ name }) => result(getApi(name)));
    server.registerTool('validate_script', {
      description: '仅静态检查 AutoSDK JS/TS 的语法、未声明函数、参数类型和模块误用。绝不执行代码、不读取用户文件、不访问手机。最多 65536 码元；结果不证明权限和真机可用。', annotations,
      inputSchema: z.object({ code: z.string().min(1).max(MAX_SCRIPT_LENGTH), language: z.enum(['javascript', 'typescript']).default('javascript') }).strict()
    }, async ({ code, language }, context) => {
      try { return result({ sdkVersion: catalog.sdkVersion, ...await validator.validate(code, language, context.mcpReq.signal), caveats }); }
      catch (error) { return result({ sdkVersion: catalog.sdkVersion, valid: false, status: 'not_checked', executed: false, message: error.message, caveats }, true); }
    });
    server.registerResource('autosdk-guide', 'autosdk://guide', { description: 'AutoSDK 脚本编写约束、检查流程与静态验证边界', mimeType: 'text/plain' },
      uri => ({ contents: [{ uri: uri.href, mimeType: 'text/plain', text: instructions + '\n' + caveats.join('\n') }] }));
    return server;
  }, { transport: new StdioServerTransport(process.stdin, process.stdout, { maxBufferSize: 1024 * 1024 }),
    onerror: () => console.error('AutoSDK MCP transport error; verify client protocol/configuration.') });
  let closing = false;
  const close = async () => { if (closing) return; closing = true; validator.close(); await handle.close(); };
  process.stdin.once('end', close);
  process.once('SIGINT', close); process.once('SIGTERM', close);
}
