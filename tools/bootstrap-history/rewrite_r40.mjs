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

// ---- R40-1: zero-arg _dv/_av getters -> dvf/avf helpers ----
js = js.replace(/function\(\)\{return _dv\('([^']+)'\);\}/g, "dvf('$1')");
js = js.replace(/function\(\)\{return _av\('([^']+)'\);\}/g, "avf('$1')");
if (js.includes("function(){return _dv('")) throw new Error('dv pattern not fully replaced');
if (js.includes("function(){return _av('")) throw new Error('av pattern not fully replaced');

// ---- R40-2: torch/flashlight after literal ----
js = replaceOnce(js,
  ",torch:function(on){return deviceApi.setFlashlight(on);},flashlight:function(on){return deviceApi.setFlashlight(on);}};",
  "};deviceApi.torch=deviceApi.setFlashlight;deviceApi.flashlight=deviceApi.setFlashlight;",
  'torch/flashlight');

// ---- R40-3: helpers before var deviceApi ----
js = replaceOnce(js, "var deviceApi={info:dvf('info'),",
  "function dvf(k){return function(){return _dv(k);};}function avf(k){return function(){return _av(k);};}var deviceApi={info:dvf('info'),",
  'helpers');

// ---- R40-4: hash helpers + md5/sha family compaction ----
js = replaceOnce(js, "var stringsApi=",
  "function hsh(n){return function(s){return _nn(n,[SS(s)]);};}function hsh2(n){return function(s,k){return _nn(n,[SS(s),SS(k)]);};}var stringsApi=",
  'hsh helpers');
js = replaceOnce(js,
  "md5:function(s){return _nn('md5',[SS(s)]);},sha1:function(s){return _nn('sha1',[SS(s)]);},sha256:function(s){return _nn('sha256',[SS(s)]);},sha512:function(s){return _nn('sha512',[SS(s)]);}",
  "md5:hsh('md5'),sha1:hsh('sha1'),sha256:hsh('sha256'),sha512:hsh('sha512')",
  'md5/sha');
js = replaceOnce(js,
  "hmacSHA1:function(s,k){return _nn('hmac1',[SS(s),SS(k)]);},hmacSHA256:function(s,k){return _nn('hmac256',[SS(s),SS(k)]);}",
  "hmacSHA1:hsh2('hmac1'),hmacSHA256:hsh2('hmac256')",
  'hmac');

// ---- R40-5: boolean flag compaction ----
js = replaceOnce(js,
  "keepScreenOn:function(value){return _dv('keepScreenOn',value===false?false:true,'value');}",
  "keepScreenOn:function(value){return _dv('keepScreenOn',value!==false,'value');}",
  'keepScreenOn');
js = replaceOnce(js,
  "setFlashlight:function(on){return _dv('flashlight',on===false?false:true,'value');}",
  "setFlashlight:function(on){return _dv('flashlight',on!==false,'value');}",
  'setFlashlight');

// ---- R40-6: arr helper micro-compaction ----
js = replaceOnce(js,
  "function arr(a,n){return Array.prototype.slice.call(a,n);}",
  "function arr(a,n){return [].slice.call(a,n);}",
  'arr helper');

// ---- R40-7: tail additions ----
const tailAnchor = "g.string=stringsApi;return drainTimers;";
const additions = "var threadApi={execAsync:base.execAsync,execSync:base.execSync,cancelThread:g.cancelThread,stopAll:g.stopAllThreads,isCancelled:base.isCancelled};g.thread=threadApi;" +
  "var utilsApi={dataMd5:base.md5,fileMd5:fileApi.md5File,randomInt:base.randomInt,randomCharNumber:randomCharNumber,getRangeInt:getRangeInt,getRatio:getRatio,zip:fileApi.zip,unzip:fileApi.unzip,readFileInZip:fileApi.readFileInZip,playMp3:base.playMp3,stopMp3:base.stopMp3,deleteAllPhotos:mediaApi.deleteAllPhotos,deleteAllVideos:mediaApi.deleteAllVideos,requestPhotoAuthorization:mediaApi.requestPhotoAuthorization};g.utils=utilsApi;" +
  "g.getPasteboard=deviceApi.getClipboard;g.setPasteboard=deviceApi.setClipboard;g.openUrl=appApi.openURL;g.uploadToAlbum=base.saveImageToAlbum;g.childcount=base.childCount;" +
  "deviceApi.applist=appApi.appList;deviceApi.getOrientationNoAuto=deviceApi.getOrientation;deviceApi.getDeviceMsg=function(){return JSON.stringify(deviceApi.info());};" +
  "imageApi.captureFullScreen=base.screenshot;" + tailAnchor;
js = replaceOnce(js, tailAnchor, additions, 'tail additions');

for (const probe of ['g.thread=threadApi', 'g.utils=utilsApi', 'g.getPasteboard=', 'g.openUrl=', 'g.uploadToAlbum=', 'g.childcount=', 'deviceApi.applist=', 'deviceApi.getOrientationNoAuto=', 'deviceApi.getDeviceMsg=', 'imageApi.captureFullScreen=', 'dvf(', 'avf(', 'hsh(']) {
  if (!js.includes(probe)) throw new Error('missing probe: ' + probe);
}
console.log('decoded length after:', js.length, 'budget ok:', js.length <= 61440);

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
console.log('round-trip length:', rejs.length, 'match:', rejs === js, 'budget 61440:', rejs.length <= 61440);
if (rejs !== js) throw new Error('round-trip mismatch');
new vm.Script(rejs, { filename: 'bootstrap-rt.js' });
console.log('write-back OK; file lines:', reread.split(/\r?\n/).length);
fs.writeFileSync(process.env.TEMP + '/bootstrap40.js', js, 'utf8');
