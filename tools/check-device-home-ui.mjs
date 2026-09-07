// Optional real-Chromium UI smoke test. Supply installed Playwright and Chrome paths;
// it uses an isolated headless profile and only a temporary loopback preview server.
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.AUTOSDK_PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(import.meta.dirname, '..');
const extension = path.join(root, 'vscode-extension');
const module = { exports: {} };
vm.runInNewContext(fs.readFileSync(path.join(extension, 'device-home-view.js'), 'utf8'), {
  module, require: name => name === 'vscode' ? { Uri: { joinPath: (...parts) => parts.join('/') } } : require(name)
});
const theme = `:root { --vscode-foreground:#cccccc; --vscode-font-size:13px; --vscode-font-family:Arial,"Microsoft YaHei",sans-serif; --vscode-descriptionForeground:#a0a0a0; --vscode-panel-border:#454545; --vscode-sideBarSectionHeader-background:#2b2b2b; --vscode-button-foreground:#fff; --vscode-button-background:#0078d4; --vscode-button-hoverBackground:#026ec1; --vscode-button-secondaryForeground:#fff; --vscode-button-secondaryBackground:#3c3c3c; --vscode-button-secondaryHoverBackground:#505050; --vscode-testing-iconPassed:#73c991; --vscode-focusBorder:#0078d4; background:#202020; }`;
const server = http.createServer((req, res) => {
  const files = { '/media/device-home.js': 'device-home.js', '/media/device-home.css': 'device-home.css' };
  if (req.url === '/') {
    const origin = `http://127.0.0.1:${server.address().port}`;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.end(module.exports.deviceHomeHtml({ cspSource: origin, asWebviewUri: uri => origin + uri }, ''));
  } else if (files[req.url]) {
    const css = req.url.endsWith('.css');
    res.setHeader('Content-Type', css ? 'text/css; charset=utf-8' : 'text/javascript; charset=utf-8');
    res.end((css ? theme : '') + fs.readFileSync(path.join(extension, 'media', files[req.url]), 'utf8'));
  } else { res.writeHead(404); res.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
let browser;
try {
  browser = await chromium.launch({ executablePath: process.env.AUTOSDK_CHROME_PATH, headless: true });
  const page = await browser.newPage({ viewport: { width: 320, height: 1050 } });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
  await page.addInitScript(() => {
    window.sent = [];
    window.acquireVsCodeApi = () => ({ postMessage: message => window.sent.push(message) });
  });
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await page.waitForFunction(() => window.sent.some(message => message.action === 'ready'));
  const state = { connection: 'disconnected', configured: false, trusted: true, canRun: true,
    canSelect: false, scriptName: '我的第一个脚本.js', message: '找到 1 台手机，点击「添加并连接」。',
    devices: [{ key: '1:0', name: '我的 iPhone · 1234ABCD', address: '192.168.1.25:9001' }] };
  const update = value => page.evaluate(state => window.postMessage({ type: 'state', state }), value);
  await update(state);
  await page.getByRole('button', { name: '添加并连接' }).click();
  assert.equal(await page.evaluate(() => window.sent.at(-1).key), '1:0');
  assert.equal(await page.locator('#run').isDisabled(), true);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  fs.mkdirSync(path.join(root, 'dist'), { recursive: true });
  await page.screenshot({ path: path.join(root, 'dist/device-home-320.png'), fullPage: true });
  await update({ ...state, connection: 'ready', configured: true, deviceName: '我的 iPhone', address: '192.168.1.25:9001', devices: [], message: '手机已连接，可以运行脚本或打开截图与节点。' });
  await page.getByRole('button', { name: '运行整个脚本', exact: true }).click();
  assert.equal(await page.evaluate(() => window.sent.at(-1).action), 'run');
  await page.screenshot({ path: path.join(root, 'dist/device-home-connected.png'), fullPage: true });
  await page.setViewportSize({ width: 240, height: 1050 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  assert.deepEqual(errors, []);
  console.log('PASS: real Chromium sidebar rendering, CSP, device card, run button, 240/320px widths; screenshots in dist/. Simulated device only.');
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}
