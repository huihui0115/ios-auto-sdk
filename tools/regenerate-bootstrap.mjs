import fs from 'node:fs';
import vm from 'node:vm';

const SOURCE = 'tools/bootstrap-source.js';
const TARGET = 'Sources/AutoSDK/AutoBootstrapScript.m';
const START_MARK = 'NSString *AutoBootstrapScript(void) {';
const TERM = '"})(this);"';
const CHUNK = 4000;

const js = fs.readFileSync(SOURCE, 'utf8').replace(/^\uFEFF/, '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
if (js.length > 60 * 1024) throw new Error('bootstrap exceeds 61440 budget: ' + js.length);

// sanity: must parse as JavaScript and install the auto global
const compiled = new vm.Script(js, { filename: 'bootstrap-source.js' });
if (!js.includes('g.auto=')) throw new Error('bootstrap-source.js does not install the auto global');

function escapeLiteral(text) {
  return text.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

const bodyTerm = '})(this);';
const bodyLen = js.length - bodyTerm.length;
const lines = [START_MARK];
let pos = 0;
let first = true;
while (pos < bodyLen) {
  const take = Math.min(CHUNK, bodyLen - pos);
  const chunk = js.slice(pos, pos + take);
  lines.push(first ? '    return @"' + escapeLiteral(chunk) + '"' : '            "' + escapeLiteral(chunk) + '"');
  first = false;
  pos += take;
}
lines.push('            "' + bodyTerm + '";');
lines.push('}');
fs.writeFileSync(TARGET, lines.join('\r\n') + '\r\n', 'utf8');

// round-trip verify
const reread = fs.readFileSync(TARGET, 'utf8');
const ret2 = reread.indexOf('return @"', reread.indexOf(START_MARK));
const at2 = reread.indexOf(TERM, ret2);
const reblock = reread.slice(ret2, at2 + TERM.length);
const rels = [...reblock.matchAll(/@?"((?:\\.|[^"\\])*)"/g)];
const rejs = rels.map(m => JSON.parse('"' + m[1] + '"')).join('');
if (rejs !== js) throw new Error('round-trip mismatch');
console.log('regenerated ' + TARGET + ' (' + js.length + ' chars, budget ' + 60 * 1024 + ')');
