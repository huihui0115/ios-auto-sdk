(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.AutoSDKInspectorModel = api;
}(typeof globalThis === 'object' ? globalThis : this, function () {
  function number(value, fallback) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  function stableStringify(value, seen) {
    if (value === null || typeof value !== 'object') return JSON.stringify(value);
    if (seen.indexOf(value) >= 0) throw new TypeError('Circular value');
    seen.push(value);
    var result;
    if (Array.isArray(value)) {
      result = '[' + value.map(function (item) { return stableStringify(item, seen); }).join(',') + ']';
    } else {
      result = '{' + Object.keys(value).sort().map(function (key) {
        return JSON.stringify(key) + ':' + stableStringify(value[key], seen);
      }).join(',') + '}';
    }
    seen.pop();
    return result;
  }

  function nodeKey(node) {
    if (!node || typeof node !== 'object') return '';
    for (const key of ['nodeId', 'handle', 'path']) {
      if (typeof node[key] === 'string' && node[key]) return key + ':' + node[key];
    }
    if (node.selector && typeof node.selector === 'object') {
      try { return 'selector:' + stableStringify(node.selector, []); }
      catch (_) { return ''; }
    }
    return '';
  }

  function selectorForNode(node, nodes) {
    if (!node || typeof node !== 'object') return null;
    const text = function (value) { return typeof value === 'string' && value.trim() ? value.trim() : null; };
    const id = text(node.id);
    const label = text(node.label);
    const name = text(node.name);
    const value = text(node.value);
    const type = text(node.type);
    const original = node.selector && typeof node.selector === 'object' ? node.selector : {};
    const candidates = [];
    function addCandidate(key, candidateValue) {
      var simple = {};
      simple[key] = candidateValue;
      candidates.push(simple);
      if (type) {
        var typed = {};
        typed[key] = candidateValue;
        typed.type = type;
        candidates.push(typed);
      }
    }
    if (id) addCandidate('id', id);
    if (label) addCandidate('label', label);
    if (name) addCandidate('name', name);
    if (value) addCandidate('value', value);
    const unique = candidates.find(function (selector) {
      const entries = Object.entries(selector);
      return (Array.isArray(nodes) ? nodes : []).filter(function (candidate) {
        if (!candidate || typeof candidate !== 'object') return false;
        return entries.every(function (entry) { return String(candidate[entry[0]] ?? '') === String(entry[1]); });
      }).length === 1;
    });
    if (unique) return unique;
    if (typeof original.xpath === 'string' && original.xpath) return { xpath: original.xpath };
    return null;
  }

  function indexAtPoint(nodes, point) {
    const candidates = (Array.isArray(nodes) ? nodes : []).map(function (node, index) {
      return { node: node, index: index };
    }).filter(function (entry) {
      const bounds = entry.node && entry.node.bounds;
      return bounds && number(bounds.width, 0) > 0 && number(bounds.height, 0) > 0 &&
        point.x >= number(bounds.x, 0) && point.y >= number(bounds.y, 0) &&
        point.x <= number(bounds.x, 0) + number(bounds.width, 0) &&
        point.y <= number(bounds.y, 0) + number(bounds.height, 0);
    });
    candidates.sort(function (left, right) {
      const a = left.node.bounds;
      const b = right.node.bounds;
      const area = number(a.width, 0) * number(a.height, 0) - number(b.width, 0) * number(b.height, 0);
      if (area) return area;
      const depth = number(right.node.depth, 0) - number(left.node.depth, 0);
      return depth || right.index - left.index;
    });
    return candidates.length ? candidates[0].index : -1;
  }

  function selectionIndex(nodes, previousKey) {
    if (!previousKey) return -1;
    return (Array.isArray(nodes) ? nodes : []).findIndex(node => nodeKey(node) === previousKey);
  }

  function pointFromClient(clientX, clientY, rect, size) {
    const renderedWidth = Math.max(1, number(rect?.width, 1));
    const renderedHeight = Math.max(1, number(rect?.height, 1));
    const width = Math.max(1, number(size?.width, 1));
    const height = Math.max(1, number(size?.height, 1));
    const maximumX = Math.max(0, width - 1);
    const maximumY = Math.max(0, height - 1);
    return {
      x: Math.max(0, Math.min(maximumX, (number(clientX, 0) - number(rect?.left, 0)) * width / renderedWidth)),
      y: Math.max(0, Math.min(maximumY, (number(clientY, 0) - number(rect?.top, 0)) * height / renderedHeight))
    };
  }

  function regionBetween(start, end) {
    const x = Math.min(start.x, end.x);
    const y = Math.min(start.y, end.y);
    return {
      x: Math.round(x),
      y: Math.round(y),
      width: Math.round(Math.abs(start.x - end.x)),
      height: Math.round(Math.abs(start.y - end.y))
    };
  }

  function codeForSelector(selector, operation) {
    if (!selector || typeof selector !== 'object' || Array.isArray(selector)) return '';
    var encoded = JSON.stringify(selector);
    if (operation === 'find') return 'const node = auto.findElement(' + encoded + ');\nconsole.log(node);';
    if (operation === 'wait') return 'auto.waitFor(' + encoded + ', 5000);';
    return 'auto.click(' + encoded + ');';
  }

  function codeForPoint(point) {
    return 'auto.clickPoint(' + Math.round(number(point && point.x, 0)) + ', ' + Math.round(number(point && point.y, 0)) + ');';
  }

  function codeForOCR(region) {
    return 'const region = ' + JSON.stringify(region || {}) + ';\nconst words = auto.ocr(region);\nconsole.log(words);';
  }

  function codeForImage(assetPath) {
    return 'const match = auto.findImage(' + JSON.stringify(String(assetPath || '')) + ', {threshold: 0.9});\nif (match && match.found) auto.clickPoint(match.centerX, match.centerY);';
  }

  function codeForColor(color) {
    if (!color || typeof color.hex !== 'string' || !color.hex) return '';
    return 'const matches = auto.compareColors([{x:' + Math.round(number(color.x, 0)) + ',y:' +
      Math.round(number(color.y, 0)) + ',color:' + JSON.stringify(color.hex) + '}], {tolerance:8});\nconsole.log(matches);';
  }

  return {
    codeForColor, codeForImage, codeForOCR, codeForPoint, codeForSelector,
    indexAtPoint, nodeKey, number, pointFromClient, regionBetween, selectionIndex, selectorForNode
  };
}));
