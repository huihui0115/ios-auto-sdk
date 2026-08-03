const MAX_CODE_BYTES = 64 * 1024;
const MAX_SELECTOR_BYTES = 16 * 1024;
const MAX_TEXT_BYTES = 64 * 1024;
const MAX_COORDINATE = 1000000;
const NODE_ACTIONS = new Set(['click', 'input', 'scroll']);

function boundedText(value, label, maximumBytes) {
  const text = String(value || '');
  if (Buffer.byteLength(text, 'utf8') > maximumBytes) {
    throw new Error(`${label} exceeds the ${maximumBytes / 1024} KB limit.`);
  }
  return text;
}

function selectorObject(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('Selector must be a JSON object.');
  }
  let encoded;
  try { encoded = JSON.stringify(value); }
  catch (_) { throw new Error('Selector must be JSON serializable.'); }
  if (Buffer.byteLength(encoded, 'utf8') > MAX_SELECTOR_BYTES) {
    throw new Error('Selector exceeds the 16 KB limit.');
  }
  return value;
}

function coordinate(value, label) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0 || number > MAX_COORDINATE) {
    throw new Error(`${label} must be a finite number between 0 and ${MAX_COORDINATE}.`);
  }
  return number;
}

function point(x, y) {
  return { x: coordinate(x, 'x'), y: coordinate(y, 'y') };
}

function ocrRegion(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('OCR region must be an object.');
  }
  const region = {
    x: coordinate(value.x, 'region.x'),
    y: coordinate(value.y, 'region.y'),
    width: coordinate(value.width, 'region.width'),
    height: coordinate(value.height, 'region.height')
  };
  if (region.width <= 0 || region.height <= 0) throw new Error('OCR region width and height must be greater than zero.');
  return region;
}

function nodeAction(value) {
  const action = String(value || '');
  if (!NODE_ACTIONS.has(action)) throw new Error('Node action must be click, input, or scroll.');
  return action;
}

function generatedCode(value) {
  return boundedText(value, 'Generated code', MAX_CODE_BYTES);
}

function inputText(value) {
  return boundedText(value, 'Input text', MAX_TEXT_BYTES);
}

module.exports = { generatedCode, inputText, nodeAction, ocrRegion, point, selectorObject };
