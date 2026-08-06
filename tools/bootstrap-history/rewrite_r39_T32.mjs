import fs from 'node:fs';
import vm from 'node:vm';

const FILE = 'Sources/AutoSDK/AutoBootstrapScript.m';
const src = fs.readFileSync(FILE, 'utf8');
const startMark = 'NSString *AutoBootstrapScript(void) {';
const start = src.indexOf(startMark);
const ret = src.indexOf('return @"', start);
const term = '"})(this);"';
const at = src.indexOf(term, ret);
const end = at >= 0 ? at + term.length : -1;
if (start < 0 || ret < 0 || end < 0) throw new Error('cannot locate bootstrap block');

function decode(src, ret, end) {
  const block = src.slice(ret, end);
  const ls = [...block.matchAll(/@?"((?:\\.|[^"\\])*)"/g)];
  return ls.map(m => JSON.parse('"' + m[1] + '"')).join('');
}
let js = decode(src, ret, end);
console.log('decoded length before:', js.length);

function replaceOnce(text, oldStr, newStr, label) {
  const c = text.split(oldStr).length - 1;
  if (c !== 1) throw new Error(label + ': expected exactly 1 occurrence, found ' + c);
  return text.split(oldStr).join(newStr);
}

// ---- T32a: arr() helper + slice call compaction ----
js = replaceOnce(js,
  "function _pc(x,y){return bridge.invokePixelColor({x:x,y:y});}",
  "function _pc(x,y){return bridge.invokePixelColor({x:x,y:y});}function arr(a,n){return Array.prototype.slice.call(a,n);}",
  'T32a arr helper');
js = replaceOnce(js,
  "format:function(){var args=Array.prototype.slice.call(arguments),pattern",
  "format:function(){var args=arr(arguments),pattern",
  'T32a format');
js = replaceOnce(js,
  "base.execAsync=function(fn){var args=Array.prototype.slice.call(arguments,1);",
  "base.execAsync=function(fn){var args=arr(arguments,1);",
  'T32a execAsync');
js = replaceOnce(js,
  "base.execSync=function(fn){var args=Array.prototype.slice.call(arguments,1);",
  "base.execSync=function(fn){var args=arr(arguments,1);",
  'T32a execSync');
js = replaceOnce(js,
  "return function(){ensureRunning();return _nn(Str(key),Array.prototype.slice.call(arguments));};",
  "return function(){ensureRunning();return _nn(Str(key),arr(arguments));};",
  'T32a proxy');
js = replaceOnce(js,
  "ensureRunning();return scheduleTimer(fn,ms,false,Array.prototype.slice.call(arguments,2));};g.clearTimeout",
  "ensureRunning();return scheduleTimer(fn,ms,false,arr(arguments,2));};g.clearTimeout",
  'T32a setTimeout');
js = replaceOnce(js,
  "ensureRunning();return scheduleTimer(fn,ms,true,Array.prototype.slice.call(arguments,2));};g.clearInterval",
  "ensureRunning();return scheduleTimer(fn,ms,true,arr(arguments,2));};g.clearInterval",
  'T32a setInterval');

// ---- T32b: stringsApi export clusters -> forEach ----
js = replaceOnce(js,
  "g.strings=stringsApi;g.trim=stringsApi.trim;g.ltrim=stringsApi.ltrim;g.rtrim=stringsApi.rtrim;g.split=stringsApi.split;g.chars=stringsApi.chars;g.toHex=stringsApi.toHex;g.fromHex=stringsApi.fromHex;g.isUpper=stringsApi.isUpper;g.isLower=stringsApi.isLower;g.isNumber=stringsApi.isNumber;g.isIntrger=stringsApi.isIntrger;g.isLetter=stringsApi.isLetter;g.isChinese=stringsApi.isChinese;g.isEmail=stringsApi.isEmail;g.isLink=stringsApi.isLink;",
  "g.strings=stringsApi;['trim','ltrim','rtrim','split','chars','toHex','fromHex','isUpper','isLower','isNumber','isIntrger','isLetter','isChinese','isEmail','isLink'].forEach(function(n){g[n]=stringsApi[n];});",
  'T32b strings S1');
js = replaceOnce(js,
  "g.startWith=stringsApi.startWith;g.endWith=stringsApi.endWith;g.contains=stringsApi.contains;g.padZero=stringsApi.padZero;",
  "['startWith','endWith','contains','padZero'].forEach(function(n){g[n]=stringsApi[n];});",
  'T32b strings S2');
js = replaceOnce(js,
  "g.toPinYin=stringsApi.toPinYin;g.stripUtf8Bom=stringsApi.stripUtf8Bom;g.fromUnicode=stringsApi.fromUnicode;",
  "['toPinYin','stripUtf8Bom','fromUnicode'].forEach(function(n){g[n]=stringsApi[n];});",
  'T32b strings S3');

// ---- T32c: color utils (EasyClick parseColor/int2Hex/hex2Int/rgb/argb parity) ----
js = replaceOnce(js,
  "yoloApi.detectByFilePath=yoloApi.detect;var locApi=",
  "function pCol(c){if(typeof c==='number')return c>>>0;var s=String(c).replace(/^#|0x/i,'');if(s.length===3)s=s[0]+s[0]+s[1]+s[1]+s[2]+s[2];var n=parseInt(s,16);return isNaN(n)?null:n>>>0;}function int2Hex(c){var n=pCol(c);return n==null?null:'#'+('000000'+n.toString(16)).slice(-6);}var colorsApi={parseColor:pCol,toInt:pCol,int2Hex:int2Hex,toHex:int2Hex,hex2Int:pCol,rgb:function(r,g,b){return ((r&255)<<16|(g&255)<<8|(b&255))>>>0;},argb:function(a,r,g,b){return ((a&255)<<24|(r&255)<<16|(g&255)<<8|(b&255))>>>0;}};yoloApi.detectByFilePath=yoloApi.detect;var locApi=",
  'T32c colors');

// ---- T32d: exports ----
js = replaceOnce(js,
  "g.location=locApi;g.string=stringsApi;return drainTimers;",
  "g.location=locApi;g.colors=colorsApi;g.parseColor=pCol;g.int2Hex=int2Hex;g.hex2Int=pCol;g.rgb=colorsApi.rgb;g.argb=colorsApi.argb;g.string=stringsApi;return drainTimers;",
  'T32d colors exports');

console.log('decoded length after:', js.length);

const reqs = [
  'function pCol(c)',
  'var colorsApi={parseColor:pCol',
  'g.colors=colorsApi',
  'g.parseColor=pCol',
  'function arr(a,n){return Array.prototype.slice.call(a,n);}',
  "['trim','ltrim','rtrim','split','chars','toHex','fromHex','isUpper','isLower','isNumber','isIntrger','isLetter','isChinese','isEmail','isLink'].forEach(function(n){g[n]=stringsApi[n];})",
];
for (const req of reqs) if (!js.includes(req)) throw new Error('missing: ' + req.slice(0, 45));
const sliceCount = (js.match(/Array\.prototype\.slice\.call/g) || []).length;
if (sliceCount !== 1) throw new Error('slice occurrences should be exactly 1 (helper), found ' + sliceCount);
if (js.includes('g.trim=stringsApi.trim')) throw new Error('S1 not compacted');

function escapeLiteral(text) { return text.replace(/\\/g, '\\\\').replace(/"/g, '\\"'); }
const CHUNK = 4000;
const lines = [];
const bodyTerm = '})(this);';
const bodyLen = js.length - bodyTerm.length;
let pos = 0;
let first = true;
lines.push(startMark);
while (pos < bodyLen) {
  const take = Math.min(CHUNK, bodyLen - pos);
  const chunk = js.slice(pos, pos + take);
  lines.push(first ? '    return @"' + escapeLiteral(chunk) + '"' : '            "' + escapeLiteral(chunk) + '"');
  first = false;
  pos += take;
}
lines.push('            "' + bodyTerm + '";');
lines.push('}');

const newFile = lines.join('\r\n') + '\r\n';
fs.writeFileSync(FILE, newFile, 'utf8');

const reread = fs.readFileSync(FILE, 'utf8');
const ret2 = reread.indexOf('return @"', reread.indexOf(startMark));
const at2 = reread.indexOf(term, ret2);
const reblock = reread.slice(ret2, at2 + term.length);
const rels = [...reblock.matchAll(/@?"((?:\\.|[^"\\])*)"/g)];
const rejs = rels.map(m => JSON.parse('"' + m[1] + '"')).join('');
console.log('round-trip length:', rejs.length, 'match:', rejs === js);
if (rejs !== js) throw new Error('round-trip mismatch');
new vm.Script(rejs, { filename: 'bootstrap-rt.js' });
console.log('write-back OK; file lines:', reread.split(/\r?\n/).length);
fs.writeFileSync(process.env.TEMP + '/bootstrap39.js', js, 'utf8');