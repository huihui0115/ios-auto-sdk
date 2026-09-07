const vscode = require('vscode');

function inspectorHtml(webview, extensionUri) {
  const modelUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'inspector-model.js'));
  const scriptUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'inspector.js'));
  const styleUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'inspector.css'));
  const csp = [
    "default-src 'none'",
    `img-src data: ${webview.cspSource}`,
    `style-src ${webview.cspSource}`,
    `script-src ${webview.cspSource}`
  ].join('; ');
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Content-Security-Policy" content="${csp}">
  <link rel="stylesheet" href="${styleUri}">
  <title>AutoSDK 截图与节点</title>
</head>
<body>
  <header class="toolbar">
    <button id="refresh" type="button" title="重新采集截图和节点">刷新</button>
    <div class="segmented" role="group" aria-label="Inspection mode">
      <button type="button" class="active" data-mode="node">节点</button>
      <button type="button" data-mode="point" title="点击画面取色并生成颜色比较代码">取色</button>
      <button type="button" data-mode="region">框选区域</button>
    </div>
    <button id="test-image" type="button" title="选择本地模板图片并在手机上测试匹配">测试找图</button>
    <button id="test-ocr" type="button" title="识别框选区域中的文字">识别文字</button>
    <button id="save-snapshot" type="button" title="导出同一轮截图、节点树和采集信息">导出快照</button>
    <button id="cancel-operation" type="button" title="取消当前采集操作（Escape）" disabled>取消</button>
    <span id="status" role="status">正在连接…</span>
  </header>
  <main class="workspace">
    <section class="preview" aria-label="Device screenshot">
      <div id="device-screen" class="device-screen">
        <img id="screenshot" alt="Device screenshot">
        <div id="node-overlays" class="overlays" aria-hidden="true"></div>
        <div id="selection" class="selection" hidden></div>
      </div>
      <div class="readout">
        <span id="coordinates">x: -, y: -</span>
        <span><span id="snapshot-summary"></span><span id="device-summary"></span></span>
      </div>
    </section>
    <aside class="sidebar">
      <section class="panel-section node-section">
        <div class="section-heading">
          <label for="node-filter">节点列表</label>
          <span id="node-count">0</span>
        </div>
        <input id="node-filter" type="search" placeholder="搜索控件文字、名称、类型或 ID">
        <div id="node-list" class="node-list" role="listbox" aria-label="Device nodes"></div>
      </section>
      <section class="panel-section details-section">
        <div class="section-heading"><span>选中控件</span></div>
        <pre id="details">点击截图中的控件，或选择左侧节点。</pre>
        <div class="button-row">
          <button id="click-node" type="button">点击控件</button>
          <button id="input-node" type="button">输入文字</button>
          <button id="scroll-node" type="button">滚动</button>
        </div>
      </section>
      <section class="panel-section selector-section">
        <label for="selector">高级：选择器 JSON（点选控件自动生成）</label>
        <textarea id="selector" spellcheck="false" rows="4">{"visible":true,"maxResults":20}</textarea>
        <div class="button-row">
          <button id="test-selector" type="button">验证匹配</button>
          <button id="use-selector" type="button">生成查找代码</button>
        </div>
      </section>
      <section class="panel-section code-section">
        <label for="generated-code">生成的脚本代码</label>
        <textarea id="generated-code" spellcheck="false" rows="5"></textarea>
        <div class="button-row">
          <button id="copy-code" type="button">复制</button>
          <button id="insert-code" class="primary" type="button">插入脚本</button>
        </div>
      </section>
    </aside>
  </main>
  <script src="${modelUri}"></script>
  <script src="${scriptUri}"></script>
</body>
</html>`;
}

module.exports = { inspectorHtml };
