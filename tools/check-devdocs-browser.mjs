#!/usr/bin/env node
// Optional local visual regression: isolated Chrome CDP on localhost:9222.
// Only operates on this repository's already-open generated docs tab.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const root = path.resolve(import.meta.dirname, '..');
const require = createRequire(path.join(root, 'vscode-extension/package.json'));
const WebSocket = require('ws');
const url = pathToFileURL(path.join(root, 'docs/index.html')).href;
const tabs = await (await fetch('http://localhost:9222/json')).json();
const target = tabs.find(t => t.type === 'page' && t.url.split('#')[0] === url);
assert.ok(target, 'Open this repository docs in the isolated CDP browser first');
const socket = new WebSocket(target.webSocketDebuggerUrl), pending = new Map();
let serial = 0;
await new Promise((resolve, reject) => { socket.once('open', resolve); socket.once('error', reject); });
socket.on('message', data => {
  const message = JSON.parse(data), callbacks = pending.get(message.id);
  if (callbacks) { pending.delete(message.id); message.error ? callbacks.reject(new Error(JSON.stringify(message.error))) : callbacks.resolve(message.result); }
});
function cdp(method, params = {}) {
  return new Promise((resolve, reject) => { const id = ++serial; pending.set(id, { resolve, reject }); socket.send(JSON.stringify({ id, method, params })); });
}
async function evaluate(expression) {
  const result = await cdp('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  assert.ok(!result.exceptionDetails, JSON.stringify(result.exceptionDetails));
  return result.result.value;
}
const timer = setTimeout(() => { socket.terminate(); throw new Error('Browser check timeout'); }, 20000);
try {
  await cdp('Page.reload', { ignoreCache: true });
  for (let retry = 0; retry < 40; retry++) {
    if (await evaluate('document.readyState === "complete" && !!document.getElementById("page-ai")')) break;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  const results = [];
  for (const width of [320, 390, 900, 1024, 1280]) {
    await cdp('Emulation.setDeviceMetricsOverride', { width, height: 900, deviceScaleFactor: 1, mobile: false });
    await evaluate('location.hash = "#/ai"; new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))');
    const state = await evaluate('({page: document.querySelector(".page.current").id, width:innerWidth, scroll:document.documentElement.scrollWidth, text:document.getElementById("page-ai").innerText, copies:document.querySelectorAll("#page-ai [data-copy]").length})');
    assert.equal(state.page, 'page-ai');
    assert.ok(state.scroll <= state.width, `Overflow at ${width}px: ${state.scroll}`);
    assert.ok(state.text.includes('validate_script') && state.text.includes('不执行提交的代码'));
    assert.equal(state.copies, 3);
    results.push({ width, scroll: state.scroll, page: state.page });
  }
  const search = await evaluate('(() => { const input=document.querySelector("input[type=search]"); input.value="MCP"; input.dispatchEvent(new Event("input",{bubbles:true})); return [...document.querySelectorAll(".search-result")].map(e=>e.getAttribute("href")); })()');
  assert.ok(search.includes('#/ai'), 'AI guide must be searchable');
  await evaluate('document.querySelector("input[type=search]").value=""; document.querySelector("input[type=search]").dispatchEvent(new Event("input",{bubbles:true}));');
  await cdp('Emulation.clearDeviceMetricsOverride');
  console.log(JSON.stringify({ passed: true, viewports: results, search }, null, 2));
} finally { clearTimeout(timer); socket.close(); }
