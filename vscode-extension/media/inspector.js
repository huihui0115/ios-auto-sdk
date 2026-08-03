(function () {
  const vscode = acquireVsCodeApi();
  const elements = {
    refresh: document.getElementById('refresh'),
    testImage: document.getElementById('test-image'),
    testOCR: document.getElementById('test-ocr'),
    status: document.getElementById('status'),
    screen: document.getElementById('device-screen'),
    screenshot: document.getElementById('screenshot'),
    overlays: document.getElementById('node-overlays'),
    selection: document.getElementById('selection'),
    coordinates: document.getElementById('coordinates'),
    deviceSummary: document.getElementById('device-summary'),
    nodeFilter: document.getElementById('node-filter'),
    nodeList: document.getElementById('node-list'),
    nodeCount: document.getElementById('node-count'),
    details: document.getElementById('details'),
    clickNode: document.getElementById('click-node'),
    inputNode: document.getElementById('input-node'),
    scrollNode: document.getElementById('scroll-node'),
    selector: document.getElementById('selector'),
    testSelector: document.getElementById('test-selector'),
    useSelector: document.getElementById('use-selector'),
    generatedCode: document.getElementById('generated-code'),
    copyCode: document.getElementById('copy-code'),
    insertCode: document.getElementById('insert-code')
  };
  const state = { nodes: [], device: {}, selectedIndex: -1, mode: 'node', regionStart: null, region: null, match: null };

  function number(value, fallback) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  function screenSize() {
    return {
      width: Math.max(1, number(state.device.screenWidth, elements.screenshot.naturalWidth || 1)),
      height: Math.max(1, number(state.device.screenHeight, elements.screenshot.naturalHeight || 1))
    };
  }

  function pointForEvent(event) {
    const rect = elements.screen.getBoundingClientRect();
    const size = screenSize();
    const renderedWidth = Math.max(1, rect.width);
    const renderedHeight = Math.max(1, rect.height);
    return {
      x: Math.max(0, Math.min(size.width, (event.clientX - rect.left) * size.width / renderedWidth)),
      y: Math.max(0, Math.min(size.height, (event.clientY - rect.top) * size.height / renderedHeight))
    };
  }

  function nodeSelector(node) {
    if (!node || typeof node !== 'object') return null;
    const text = function (value) { return typeof value === 'string' && value.trim() ? value.trim() : null; };
    const id = text(node.id);
    const label = text(node.label);
    const name = text(node.name);
    const value = text(node.value);
    const type = text(node.type);
    const original = node.selector && typeof node.selector === 'object' ? node.selector : {};
    const candidates = [];
    if (id) candidates.push(type ? { id: id, type: type } : { id: id });
    if (label) candidates.push(type ? { label: label, type: type } : { label: label });
    if (name) candidates.push(type ? { name: name, type: type } : { name: name });
    if (value && type) candidates.push({ value: value, type: type });
    const unique = candidates.find(function (selector) {
      const entries = Object.entries(selector);
      return state.nodes.filter(function (candidate) {
        return entries.every(function (entry) { return String(candidate[entry[0]] ?? '') === String(entry[1]); });
      }).length === 1;
    });
    if (unique) return unique;
    if (typeof original.xpath === 'string' && original.xpath) return { xpath: original.xpath };
    return null;
  }

  function nodeTitle(node) {
    return node.label || node.text || node.id || node.name || node.value || '(unnamed)';
  }

  function codeForSelector(selector, operation) {
    if (!selector) return '';
    const encoded = JSON.stringify(selector);
    if (operation === 'find') return 'const node = auto.findElement(' + encoded + ');\nconsole.log(node);';
    if (operation === 'wait') return 'auto.waitFor(' + encoded + ', 5000);';
    return 'auto.click(' + encoded + ');';
  }

  function setGenerated(code) {
    elements.generatedCode.value = code || '';
  }

  function setStatus(message, error) {
    elements.status.textContent = message || '';
    elements.status.style.color = error ? 'var(--vscode-errorForeground)' : '';
  }

  function overlay(bounds, className) {
    if (!bounds || number(bounds.width, 0) <= 0 || number(bounds.height, 0) <= 0) return;
    const size = screenSize();
    const item = document.createElement('div');
    item.className = 'node-overlay ' + (className || '');
    item.style.left = (number(bounds.x, 0) / size.width * 100) + '%';
    item.style.top = (number(bounds.y, 0) / size.height * 100) + '%';
    item.style.width = (number(bounds.width, 0) / size.width * 100) + '%';
    item.style.height = (number(bounds.height, 0) / size.height * 100) + '%';
    elements.overlays.appendChild(item);
  }

  function renderOverlays() {
    elements.overlays.replaceChildren();
    const visible = state.nodes.filter(function (node) {
      const bounds = node && node.bounds;
      return bounds && number(bounds.width, 0) > 0 && number(bounds.height, 0) > 0;
    }).slice(0, 200);
    visible.forEach(function (node) { overlay(node.bounds, ''); });
    if (state.selectedIndex >= 0 && state.nodes[state.selectedIndex]) overlay(state.nodes[state.selectedIndex].bounds, 'selected');
    if (state.match && state.match.found) overlay(state.match, 'match');
  }

  function renderNodes() {
    const query = elements.nodeFilter.value.trim().toLowerCase();
    elements.nodeList.replaceChildren();
    const matches = [];
    state.nodes.forEach(function (node, index) {
      const haystack = [node.type, node.id, node.label, node.text, node.name, node.value].filter(Boolean).join(' ').toLowerCase();
      if (!query || haystack.includes(query)) matches.push({ node: node, index: index });
    });
    elements.nodeCount.textContent = String(matches.length) + (matches.length !== state.nodes.length ? ' / ' + state.nodes.length : '');
    matches.slice(0, 600).forEach(function (entry) {
      const row = document.createElement('button');
      row.type = 'button';
      row.className = 'node-row' + (entry.index === state.selectedIndex ? ' selected' : '');
      row.style.setProperty('--node-depth', String(Math.min(12, Math.max(0, number(entry.node.depth, 0)))));
      row.setAttribute('role', 'option');
      row.setAttribute('aria-selected', entry.index === state.selectedIndex ? 'true' : 'false');
      const type = document.createElement('span');
      type.className = 'node-type';
      type.textContent = entry.node.type || entry.node.className || 'Node';
      const label = document.createElement('span');
      label.className = 'node-label';
      label.textContent = nodeTitle(entry.node);
      row.append(type, label);
      row.addEventListener('click', function () { selectNode(entry.index); });
      elements.nodeList.appendChild(row);
    });
  }

  function selectNode(index) {
    state.selectedIndex = index;
    const node = state.nodes[index];
    const selector = nodeSelector(node);
    elements.details.textContent = node ? JSON.stringify(node, null, 2) : 'Select a node or point.';
    if (selector) {
      elements.selector.value = JSON.stringify(selector, null, 2);
      setGenerated(codeForSelector(selector, 'click'));
    } else if (node && node.bounds) {
      const x = Math.round(number(node.bounds.centerX, number(node.bounds.x, 0) + number(node.bounds.width, 0) / 2));
      const y = Math.round(number(node.bounds.centerY, number(node.bounds.y, 0) + number(node.bounds.height, 0) / 2));
      elements.selector.value = JSON.stringify({ x: x, y: y }, null, 2);
      setGenerated('auto.clickPoint(' + x + ', ' + y + ');');
    }
    renderNodes();
    renderOverlays();
  }

  function selectAtPoint(point) {
    const candidates = state.nodes.map(function (node, index) { return { node: node, index: index }; }).filter(function (entry) {
      const b = entry.node && entry.node.bounds;
      return b && point.x >= number(b.x, 0) && point.y >= number(b.y, 0) &&
        point.x <= number(b.x, 0) + number(b.width, 0) && point.y <= number(b.y, 0) + number(b.height, 0);
    });
    candidates.sort(function (left, right) {
      const a = left.node.bounds;
      const b = right.node.bounds;
      return number(a.width, 0) * number(a.height, 0) - number(b.width, 0) * number(b.height, 0);
    });
    if (candidates.length) selectNode(candidates[0].index);
  }

  function requestNodeAction(action) {
    const node = state.selectedIndex >= 0 ? state.nodes[state.selectedIndex] : null;
    if (!node) {
      setStatus('Select a node first.', true);
      return;
    }
    const transientSelector = node.selector && typeof node.selector === 'object' ? node.selector : nodeSelector(node);
    if (transientSelector) {
      vscode.postMessage({ type: 'nodeAction', action: action, selector: transientSelector });
      return;
    }
    if (action === 'click' && node.bounds) {
      vscode.postMessage({
        type: 'nodeAction', action: action,
        x: number(node.bounds.centerX, number(node.bounds.x, 0) + number(node.bounds.width, 0) / 2),
        y: number(node.bounds.centerY, number(node.bounds.y, 0) + number(node.bounds.height, 0) / 2)
      });
      return;
    }
    setStatus('This node has no actionable selector.', true);
  }

  function showRegion(start, end) {
    const size = screenSize();
    const x = Math.min(start.x, end.x);
    const y = Math.min(start.y, end.y);
    const width = Math.abs(start.x - end.x);
    const height = Math.abs(start.y - end.y);
    elements.selection.hidden = false;
    elements.selection.style.left = (x / size.width * 100) + '%';
    elements.selection.style.top = (y / size.height * 100) + '%';
    elements.selection.style.width = (width / size.width * 100) + '%';
    elements.selection.style.height = (height / size.height * 100) + '%';
    return { x: Math.round(x), y: Math.round(y), width: Math.round(width), height: Math.round(height) };
  }

  document.querySelectorAll('[data-mode]').forEach(function (button) {
    button.addEventListener('click', function () {
      state.mode = button.dataset.mode;
      state.regionStart = null;
      elements.selection.hidden = true;
      document.querySelectorAll('[data-mode]').forEach(function (item) { item.classList.toggle('active', item === button); });
    });
  });

  elements.screen.addEventListener('pointermove', function (event) {
    const point = pointForEvent(event);
    elements.coordinates.textContent = 'x: ' + Math.round(point.x) + ', y: ' + Math.round(point.y);
    if (state.mode === 'region' && state.regionStart) showRegion(state.regionStart, point);
  });

  elements.screen.addEventListener('pointerdown', function (event) {
    const point = pointForEvent(event);
    if (state.mode === 'region') {
      state.regionStart = point;
      elements.screen.setPointerCapture(event.pointerId);
      showRegion(point, point);
      return;
    }
    if (state.mode === 'node') selectAtPoint(point);
    else {
      state.selectedIndex = -1;
      elements.details.textContent = JSON.stringify({ x: Math.round(point.x), y: Math.round(point.y) }, null, 2);
      setGenerated('auto.clickPoint(' + Math.round(point.x) + ', ' + Math.round(point.y) + ');');
      renderNodes();
      renderOverlays();
      vscode.postMessage({ type: 'pixelColor', x: point.x, y: point.y });
    }
  });

  elements.screen.addEventListener('pointerup', function (event) {
    if (state.mode !== 'region' || !state.regionStart) return;
    const region = showRegion(state.regionStart, pointForEvent(event));
    state.regionStart = null;
    state.region = region;
    elements.details.textContent = JSON.stringify(region, null, 2);
    setGenerated('const region = ' + JSON.stringify(region) + ';\nconst words = auto.ocr(region);\nconsole.log(words);');
  });

  elements.screen.addEventListener('pointercancel', function () {
    state.regionStart = null;
    elements.selection.hidden = true;
  });

  elements.refresh.addEventListener('click', function () { vscode.postMessage({ type: 'refresh' }); });
  elements.testImage.addEventListener('click', function () { vscode.postMessage({ type: 'testImage' }); });
  elements.testOCR.addEventListener('click', function () {
    if (!state.region || state.region.width <= 0 || state.region.height <= 0) {
      setStatus('Select a region first.', true);
      return;
    }
    vscode.postMessage({ type: 'testOCR', region: state.region });
  });
  elements.nodeFilter.addEventListener('input', renderNodes);
  elements.testSelector.addEventListener('click', function () {
    try {
      const selector = JSON.parse(elements.selector.value);
      vscode.postMessage({ type: 'testSelector', selector: selector });
    } catch (error) {
      setStatus('Invalid selector JSON: ' + error.message, true);
    }
  });
  elements.useSelector.addEventListener('click', function () {
    try { setGenerated(codeForSelector(JSON.parse(elements.selector.value), 'find')); }
    catch (error) { setStatus('Invalid selector JSON: ' + error.message, true); }
  });
  elements.clickNode.addEventListener('click', function () { requestNodeAction('click'); });
  elements.inputNode.addEventListener('click', function () { requestNodeAction('input'); });
  elements.scrollNode.addEventListener('click', function () { requestNodeAction('scroll'); });
  elements.copyCode.addEventListener('click', function () { vscode.postMessage({ type: 'copyCode', code: elements.generatedCode.value }); });
  elements.insertCode.addEventListener('click', function () { vscode.postMessage({ type: 'insertCode', code: elements.generatedCode.value }); });

  elements.screenshot.addEventListener('load', function () {
    const size = screenSize();
    elements.screen.style.aspectRatio = String(size.width) + ' / ' + String(size.height);
    renderOverlays();
  });

  window.addEventListener('message', function (event) {
    const message = event.data || {};
    if (message.type === 'loading') setStatus(message.message || 'Loading...');
    if (message.type === 'error') setStatus(message.message || 'Operation failed.', true);
    if (message.type === 'snapshot') {
      state.nodes = Array.isArray(message.nodes) ? message.nodes : [];
      state.device = message.deviceInfo || {};
      state.selectedIndex = -1;
      state.regionStart = null;
      state.region = null;
      state.match = null;
      elements.selection.hidden = true;
      elements.screenshot.src = 'data:image/png;base64,' + message.pngBase64;
      elements.deviceSummary.textContent = [state.device.model, state.device.systemVersion, state.device.adapter].filter(Boolean).join(' | ');
      elements.details.textContent = 'Select a node or point.';
      renderNodes();
      const timing = number(message.durationMs, 0) > 0 ? ' in ' + Math.round(number(message.durationMs, 0)) + ' ms' : '';
      const suffix = message.truncated ? ' (limited)' : '';
      setStatus(state.nodes.length + ' nodes loaded' + timing + suffix);
    }
    if (message.type === 'selectorResult') {
      const nodes = Array.isArray(message.nodes) ? message.nodes : [];
      state.nodes = nodes;
      state.selectedIndex = nodes.length ? 0 : -1;
      elements.details.textContent = nodes.length ? JSON.stringify(nodes[0], null, 2) : 'No matching nodes.';
      renderNodes();
      renderOverlays();
      setStatus(nodes.length + ' selector match' + (nodes.length === 1 ? '' : 'es'));
    }
    if (message.type === 'imageResult') {
      state.match = message.match || null;
      renderOverlays();
      elements.details.textContent = JSON.stringify(message.match || {}, null, 2);
      const imageStatus = state.match && state.match.found
        ? 'Image match found'
        : (state.match && state.match.truncated ? 'Image search incomplete: work limit reached' : 'Image was not found');
      setStatus(imageStatus, Boolean(state.match && state.match.truncated));
      if (state.match && state.match.found) {
        const assetPath = typeof message.assetPath === 'string' ? message.assetPath : 'debug-assets/template.png';
        setGenerated('const match = auto.findImage(' + JSON.stringify(assetPath) + ', {threshold: 0.9});\nif (match && match.found) auto.clickPoint(match.centerX, match.centerY);');
      }
    }
    if (message.type === 'ocrResult') {
      const items = Array.isArray(message.items) ? message.items : [];
      elements.details.textContent = JSON.stringify(items, null, 2);
      setStatus(items.length + ' OCR result' + (items.length === 1 ? '' : 's'));
      setGenerated('const words = auto.ocr(' + JSON.stringify(message.region || {}) + ');\nconsole.log(words);');
    }
    if (message.type === 'pixelColor') {
      const color = message.color || {};
      elements.details.textContent = JSON.stringify(color, null, 2);
      if (color.hex) setGenerated('const matches = auto.compareColors([{x:' + Math.round(number(color.x, 0)) + ',y:' + Math.round(number(color.y, 0)) + ',color:' + JSON.stringify(color.hex) + '}], {tolerance:8});\nconsole.log(matches);');
    }
    if (message.type === 'notice') setStatus(message.message || 'Done');
  });

  vscode.postMessage({ type: 'ready' });
}());
