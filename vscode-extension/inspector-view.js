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
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Content-Security-Policy" content="${csp}">
  <link rel="stylesheet" href="${styleUri}">
  <title>AutoSDK Inspector</title>
</head>
<body>
  <header class="toolbar">
    <button id="refresh" type="button" title="Refresh screenshot and nodes">Refresh</button>
    <div class="segmented" role="group" aria-label="Inspection mode">
      <button type="button" class="active" data-mode="node">Node</button>
      <button type="button" data-mode="point">Point</button>
      <button type="button" data-mode="region">Region</button>
    </div>
    <button id="test-image" type="button" title="Choose a local template and test it on the device">Test image</button>
    <button id="test-ocr" type="button" title="Run OCR in the selected region">Test OCR</button>
    <button id="save-snapshot" type="button" title="Export the correlated screenshot, node tree, and metadata">Export</button>
    <span id="status" role="status">Connecting...</span>
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
          <label for="node-filter">Nodes</label>
          <span id="node-count">0</span>
        </div>
        <input id="node-filter" type="search" placeholder="Filter id, label, type or text">
        <div id="node-list" class="node-list" role="listbox" aria-label="Device nodes"></div>
      </section>
      <section class="panel-section details-section">
        <div class="section-heading"><span>Selection</span></div>
        <pre id="details">Select a node or point.</pre>
        <div class="button-row">
          <button id="click-node" type="button">Click</button>
          <button id="input-node" type="button">Input</button>
          <button id="scroll-node" type="button">Scroll</button>
        </div>
      </section>
      <section class="panel-section selector-section">
        <label for="selector">Selector JSON</label>
        <textarea id="selector" spellcheck="false" rows="4">{"visible":true,"maxResults":20}</textarea>
        <div class="button-row">
          <button id="test-selector" type="button">Test selector</button>
          <button id="use-selector" type="button">Generate find</button>
        </div>
      </section>
      <section class="panel-section code-section">
        <label for="generated-code">Generated code</label>
        <textarea id="generated-code" spellcheck="false" rows="5"></textarea>
        <div class="button-row">
          <button id="copy-code" type="button">Copy</button>
          <button id="insert-code" class="primary" type="button">Insert into script</button>
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
