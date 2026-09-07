const vscode = require('vscode');
const { randomBytes } = require('crypto');

function deviceHomeHtml(webview, extensionUri) {
  const nonce = randomBytes(16).toString('hex');
  const resource = file => webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', file));
  return `<!doctype html><html lang="zh-CN"><head>
  <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${webview.cspSource}; script-src 'nonce-${nonce}';">
  <link rel="stylesheet" href="${resource('device-home.css')}"><title>设备与调试</title></head>
  <body>
    <header><h1>连接手机，开始调试</h1><p>同一 Wi-Fi · 无需输入连接命令</p></header>
    <section aria-labelledby="devices-heading">
      <h2 id="devices-heading">1 · 我的手机</h2>
      <div class="device current"><strong id="device-name">尚未添加手机</strong><span id="connection" role="status">未连接</span><small id="device-address"></small></div>
      <div class="buttons"><button id="scan" data-action="scan">搜索 Wi-Fi 手机</button><button id="cancelScan" data-action="cancelScan" class="secondary" hidden>取消搜索</button></div>
      <div class="buttons"><button id="reconnect" data-action="reconnect" hidden>连接</button><button id="disconnect" data-action="disconnect" class="secondary" hidden>断开</button><button id="pair" data-action="pair" class="secondary" hidden>重新配对</button></div>
      <p id="message" role="status" aria-live="polite"></p>
      <div id="devices" aria-label="搜索到的手机"></div>
      <p class="hint">首次添加：输入手机上显示的配对码。以后同一手机无需重复输入。请勿把配对码发给他人。</p>
    </section>
    <section aria-labelledby="script-heading">
      <h2 id="script-heading">2 · 编写与运行</h2>
      <p id="script-name">还没有打开脚本</p><p id="trust" class="hint" hidden>请先通过 VS Code 信任此工作区，再运行脚本。</p>
      <div class="buttons"><button id="newScript" data-action="newScript" class="secondary">新建示例脚本</button><button id="run" data-action="run">运行整个脚本</button><button id="runSelection" data-action="runSelection" class="secondary">只运行选中代码</button><button id="stop" data-action="stop" class="secondary">停止脚本</button></div>
      <p class="hint">也可以在代码上右键运行，或点编辑器右上角 ▶。先连接手机，再运行。</p>
    </section>
    <section aria-labelledby="inspect-heading">
      <h2 id="inspect-heading">3 · 查看与采集</h2>
      <div class="buttons"><button id="inspector" data-action="inspector">截图与节点</button><button id="logs" data-action="logs" class="secondary">运行日志</button><button id="help" data-action="help" class="secondary">使用指南</button></div>
      <p class="hint">点选画面生成操作代码。此处是运行与采集调试，不是断点单步调试。</p>
    </section>
    <details><summary>找不到手机？更多连接方式</summary><p class="hint">仅在广播被网络屏蔽时使用；正常连接不需要这些设置。</p><div class="buttons"><button id="manual" data-action="manual" class="secondary">手动填写手机地址</button><button id="usb" data-action="usb" class="secondary">USB 备用连接</button></div></details>
    <script nonce="${nonce}" src="${resource('device-home.js')}"></script>
  </body></html>`;
}

module.exports = { deviceHomeHtml };
