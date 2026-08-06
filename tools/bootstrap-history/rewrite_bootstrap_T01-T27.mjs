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
console.log('decoded length:', js.length);

function replaceOnce(text, oldStr, newStr, label) {
  const c = text.split(oldStr).length - 1;
  if (c !== 1) throw new Error(label + ': expected exactly 1 occurrence, found ' + c);
  return text.split(oldStr).join(newStr);
}

// ---- T1: remove duplicate isScreenOn member in deviceApi ----
js = replaceOnce(js,
  "},volumeDown:function(){return bridge.invokeDevice({operation:'volumeDown'});},isScreenOn:function(){return bridge.invokeDevice({operation:'isScreenOn'});},getMemoryInfo",
  "},volumeDown:function(){return bridge.invokeDevice({operation:'volumeDown'});},getMemoryInfo",
  'T1');

// ---- T2: remove base duplicate clipboard/brightness/volume/vibrate run ----
js = replaceOnce(js,
  "openURL:function(url){return bridge.invokeApp({operation:'openURL',url:String(url||'')});},getClipboard:function(){return bridge.invokeDevice({operation:'clipboardGet'});},setClipboard:function(t){return bridge.invokeDevice({operation:'clipboardSet',text:String(t)});},getBrightness:function(){return bridge.invokeDevice({operation:'brightnessGet'});},setBrightness:function(v){return bridge.invokeDevice({operation:'brightnessSet',value:v});},getVolume:function(){return bridge.invokeDevice({operation:'volumeGet'});},vibrate:function(ms){return bridge.invokeDevice({operation:'vibrate',duration:ms});},capabilities",
  "openURL:function(url){return bridge.invokeApp({operation:'openURL',url:String(url||'')});},capabilities",
  'T2');

// ---- T3: point exports at deviceApi ----
js = replaceOnce(js,
  "g.getClipboard=base.getClipboard;g.setClipboard=base.setClipboard;g.getBrightness=base.getBrightness;g.setBrightness=base.setBrightness;g.getVolume=base.getVolume;g.vibrate=base.vibrate;",
  "g.getClipboard=deviceApi.getClipboard;g.setClipboard=deviceApi.setClipboard;g.getBrightness=deviceApi.getBrightness;g.setBrightness=deviceApi.setBrightness;g.getVolume=deviceApi.getVolume;g.vibrate=deviceApi.vibrate;",
  'T3');

// ---- T4: remove base duplicate deleteAll* media run ----
js = replaceOnce(js,
  "saveScreenshotToAlbum:function(){return bridge.invokeMedia({operation:'saveScreenshot'});},deleteAllPhotos:function(){return bridge.invokeMedia({operation:'deleteAllPhotos'});},deleteAllVideos:function(){return bridge.invokeMedia({operation:'deleteAllVideos'});},deleteAllMedia:function(){return bridge.invokeMedia({operation:'deleteAllMedia'});},",
  "saveScreenshotToAlbum:function(){return bridge.invokeMedia({operation:'saveScreenshot'});},",
  'T4');

// ---- T5: mechanical refactor of bridge calls (before helpers are inserted) ----
function readBalanced(text, openIdx) {
  const pairs = { '(': ')', '{': '}', '[': ']' };
  const stack = [];
  let inStr = false;
  let i = openIdx;
  for (; i < text.length; i++) {
    const ch = text[i];
    if (inStr) { if (ch === '\\') i++; else if (ch === "'") inStr = false; continue; }
    if (ch === "'") { inStr = true; continue; }
    if (ch === '(' || ch === '{' || ch === '[') stack.push(pairs[ch]);
    else if (ch === ')' || ch === '}' || ch === ']') {
      if (!stack.length) break;
      if (stack[stack.length - 1] !== ch) throw new Error('mismatch at ' + i);
      stack.pop();
      if (!stack.length) return i + 1;
    }
  }
  throw new Error('unbalanced from ' + openIdx);
}

const beforeDev1 = (js.match(/bridge\.invokeDevice\(\{operation:'[^']+'\}\)/g) || []).length;
const beforeDev2 = (js.match(/bridge\.invokeDevice\(\{operation:'[^']+',[A-Za-z_$][\w$]*:/g) || []).length;
js = js.replace(/bridge\.invokeDevice\(\{operation:'([^']+)'\}\)/g, "_dv('$1')");
js = js.replace(/bridge\.invokeDevice\(\{operation:'([^']+)',([A-Za-z_$][\w$]*):(.*?)\}\)/g, "_dv('$1',$3,'$2')");
js = js.replace(/bridge\.invokeMedia\(\{operation:'([^']+)'\}\)/g, "_md('$1')");
js = js.replace(/bridge\.invokeMedia\(\{operation:'([^']+)',([A-Za-z_$][\w$]*):(.*?)\}\)/g, "_md('$1',$3,'$2')");
js = js.replace(/bridge\.invokeApp\(\{operation:'([^']+)'\}\)/g, "_av('$1')");
js = js.replace(/bridge\.invokeApp\(\{operation:'([^']+)',([A-Za-z_$][\w$]*):(.*?)\}\)/g, "_av('$1',$3,'$2')");

const out = [];
let idx = 0;
let nativeCount = 0;
while (true) {
  const p = js.indexOf('bridge.invokeNative({', idx);
  if (p < 0) { out.push(js.slice(idx)); break; }
  out.push(js.slice(idx, p));
  const close = readBalanced(js, p + 'bridge.invokeNative'.length);
  const objText = js.slice(p + 'bridge.invokeNative'.length, close);
  const inner = objText.slice(2, -2);
  const m = inner.match(/^name:(.*),arguments:(.*)$/);
  if (!m) throw new Error('native obj parse fail: ' + inner.slice(0, 80));
  out.push('_nn(' + m[1] + ',' + m[2] + ')');
  nativeCount++;
  idx = close;
}
js = out.join('');
console.log('refactor counts: device1=' + beforeDev1 + ' device2=' + beforeDev2 + ' native=' + nativeCount);

// ---- T5b: insert helper definitions ----
const helpers = "function _dv(op,v,k){var d={operation:op};if(k)d[k]=v;return bridge.invokeDevice(d);}function _md(op,v,k){var d={operation:op};if(k)d[k]=v;return bridge.invokeMedia(d);}function _av(op,v,k){var d={operation:op};if(k)d[k]=v;return bridge.invokeApp(d);}function _nn(n,a){return bridge.invokeNative({name:n,arguments:a});}";
js = replaceOnce(js,
  "function ensureRunning(){if(bridge.invokeIsStopped())throw new Error('Script cancelled.');}",
  "function ensureRunning(){if(bridge.invokeIsStopped())throw new Error('Script cancelled.');}" + helpers,
  'T5b');

// ---- T6: keepScreenOn member in deviceApi ----
js = replaceOnce(js,
  "isLocked:function(){var on=_dv('isScreenOn');return on==null?null:!on;},",
  "isLocked:function(){var on=_dv('isScreenOn');return on==null?null:!on;},keepScreenOn:function(value){return _dv('keepScreenOn',value===false?false:true,'value');},",
  'T6');

// ---- T7: webView.loadHTML ----
js = replaceOnce(js,
  "takeMessage:function(token){return _nn('webViewTakeMessage',[String(token)]);},",
  "takeMessage:function(token){return _nn('webViewTakeMessage',[String(token)]);},loadHTML:function(token,html){return _nn('webViewLoadHTML',[String(token),String(html==null?'':html)]);},",
  'T7');

// ---- T8: ocrFind / ocrClick / ocrText after base object ----
const ocrBlock = "function ocrFind(text,timeoutMs,click){if(text==null||String(text).length===0)return click?false:null;var limit=timeoutMs==null?10000:Number(timeoutMs),t0=Date.now();for(;;){var items=base.ocr();if(items&&items.length)for(var i=0;i<items.length;i++){var it=items[i];if(it.text&&String(it.text).indexOf(text)>=0){if(click){var b=it.bounds;if(b)return base.clickPoint(b.x+b.width/2,b.y+b.height/2);}else return it;}}if(Date.now()-t0>=limit)return click?false:null;base.sleep(200);}}function ocrClick(text,timeoutMs){return ocrFind(text,timeoutMs,true);}function ocrText(text,timeoutMs){return ocrFind(text,timeoutMs,false);}";
js = replaceOnce(js,
  "Math.random()*(max-min+1))+min;}};base.getChild=function",
  "Math.random()*(max-min+1))+min;}};" + ocrBlock + "base.getChild=function",
  'T8');

// ---- T9: exports ----
js = replaceOnce(js,
  "g.webView=webViewApi;",
  "g.webView=webViewApi;g.ocr=base.ocr;g.ocrClick=ocrClick;g.ocrText=ocrText;g.keepScreenOn=deviceApi.keepScreenOn;",
  'T9');

// ---- T10: auto proxy falls back to API objects before native dispatch ----
js = replaceOnce(js,
  "if(key in target)return target[key];return function(){ensureRunning();return _nn(String(key),Array.prototype.slice.call(arguments));};",
  "if(key in target)return target[key];if(key in deviceApi)return deviceApi[key];if(key in mediaApi)return mediaApi[key];if(key in appApi)return appApi[key];if(key in fileApi)return fileApi[key];if(key in imageApi)return imageApi[key];return function(){ensureRunning();return _nn(String(key),Array.prototype.slice.call(arguments));};",
  'T10');

// ---- T11: deviceApi locale/timezone/uptime getters ----
js = replaceOnce(js,
  "getMemoryInfo:function(){return _dv('memory');}};",
  "getMemoryInfo:function(){return _dv('memory');},getLanguage:function(){return _dv('language');},getCountry:function(){return _dv('country');},getLocale:function(){return _dv('locale');},getTimezone:function(){return _dv('timezone');},getUptime:function(){return _dv('uptime');},getNetworkType:function(){return _dv('networkType');},isWifi:function(){return _dv('isWifi');}};",
  'T11');

// ---- T12: appApi openSettings/openAppSetting/openAppStore ----
js = replaceOnce(js,
  "unlock:function(){return _av('unlock');},",
  "unlock:function(){return _av('unlock');},openSettings:function(){return _av('openSettings');},openAppSetting:function(){return _av('openSettings');},openAppStore:function(appId){return _av('openAppStore',String(appId||''),'appId');},",
  'T12');

// ---- T13: speechApi ----
js = replaceOnce(js,
  "isRunning:function(bundleId){var st=appApi.state(bundleId);return typeof st==='number'&&st>=2;}};",
  "isRunning:function(bundleId){var st=appApi.state(bundleId);return typeof st==='number'&&st>=2;}};var speechApi={speak:function(text,o,s){return _nn('speak',[String(text==null?'':text),o||{},Boolean(s)]);},tts:function(text,o,s){return speechApi.speak(text,o,s);},stop:function(){return _nn('speechStop',[]);},stopSpeak:function(){return speechApi.stop();}};",
  'T13');

// ---- T14: exports ----
js = replaceOnce(js,
  "g.app=appApi;",
  "g.app=appApi;g.speech=speechApi;g.speak=speechApi.speak;g.tts=speechApi.tts;g.speechStop=speechApi.stop;g.stopSpeak=speechApi.stopSpeak;",
  'T14a');
js = replaceOnce(js,
  "g.getAppVersion=deviceApi.getAppVersion;g.getPackageName=deviceApi.getPackageName;",
  "g.getAppVersion=deviceApi.getAppVersion;g.getPackageName=deviceApi.getPackageName;g.getLanguage=deviceApi.getLanguage;g.getCountry=deviceApi.getCountry;g.getLocale=deviceApi.getLocale;g.getTimezone=deviceApi.getTimezone;g.getUptime=deviceApi.getUptime;g.getNetworkType=deviceApi.getNetworkType;g.isWifi=deviceApi.isWifi;g.openAppSetting=appApi.openSettings;g.openAppStore=appApi.openAppStore;",
  'T14b');

// ---- T15: deviceApi flashlight/torch ----
js = replaceOnce(js,
  "isWifi:function(){return _dv('isWifi');}};",
  "isWifi:function(){return _dv('isWifi');},setFlashlight:function(on){return _dv('flashlight',on===false?false:true,'value');},torch:function(on){return deviceApi.setFlashlight(on);},flashlight:function(on){return deviceApi.setFlashlight(on);}};",
  'T15');

// ---- T16: flashlight exports ----
js = replaceOnce(js,
  "g.openAppSetting=appApi.openSettings;g.openAppStore=appApi.openAppStore;",
  "g.openAppSetting=appApi.openSettings;g.openAppStore=appApi.openAppStore;g.setFlashlight=deviceApi.setFlashlight;g.torch=deviceApi.setFlashlight;g.flashlight=deviceApi.setFlashlight;",
  'T16');

// ---- T17: appApi getAppScheme / launchByScheme ----
js = replaceOnce(js,
  "openAppStore:function(appId){return _av('openAppStore',String(appId||''),'appId');},",
  "openAppStore:function(appId){return _av('openAppStore',String(appId||''),'appId');},getAppScheme:function(name){return _av('getAppScheme',String(name||''),'name');},launchByScheme:function(name){return _av('launchByScheme',String(name||''),'name');},",
  'T17');

// ---- T18: scheme exports ----
js = replaceOnce(js,
  "g.openAppStore=appApi.openAppStore;",
  "g.openAppStore=appApi.openAppStore;g.getAppScheme=appApi.getAppScheme;g.launchByScheme=appApi.launchByScheme;",
  'T18');

// ---- T19: compress stringsApi (reclaim bootstrap budget) ----
{
  const startMark = 'var stringsApi={';
  const p = js.indexOf(startMark);
  if (p < 0) throw new Error('T19: stringsApi not found');
  let depth = 0, ii = p + startMark.length - 1, inStr = false;
  for (; ii < js.length; ii++) {
    const ch = js[ii];
    if (inStr) { if (ch === '\\') ii++; else if (ch === "'") inStr = false; continue; }
    if (ch === "'") { inStr = true; continue; }
    if (ch === '{') depth++;
    else if (ch === '}') { depth--; if (depth === 0) { ii++; break; } }
  }
  if (depth !== 0) throw new Error('T19: unbalanced stringsApi');
  js = js.slice(0, p) + "function SS(v){return v==null?'':String(v);}var stringsApi={trim:function(s){s=SS(s);var i=0,j=s.length;while(i<j&&s.charCodeAt(i)<=32)i++;while(j>i&&s.charCodeAt(j-1)<=32)j--;return s.substring(i,j);},ltrim:function(s){s=SS(s);var i=0;while(i<s.length&&s.charCodeAt(i)<=32)i++;return s.substring(i);},rtrim:function(s){s=SS(s);var i=s.length;while(i>0&&s.charCodeAt(i-1)<=32)i--;return s.substring(0,i);},split:function(s,sep){return SS(s).split(sep==null?',':sep);},chars:function(s){return SS(s).split('');},toHex:function(s){s=SS(s);var out='',i,c;for(i=0;i<s.length;i++){c=s.charCodeAt(i).toString(16);out+=c.length<2?'0'+c:c;}return out;},fromHex:function(h){var hex=String(h||''),out='',i;for(i=0;i+1<hex.length;i+=2){out+=String.fromCharCode(parseInt(hex.substr(i,2),16));}return out;},isUpper:function(s){return /^[A-Z]+$/.test(SS(s));},isLower:function(s){return /^[a-z]+$/.test(SS(s));},isNumber:function(s){return /^\\d+$/.test(SS(s));},isIntrger:function(s){return /^-?\\d+$/.test(SS(s));},isLetter:function(s){return /^[A-Za-z]+$/.test(SS(s));},isChinese:function(s){return /^[一-龥]+$/.test(SS(s));},isEmail:function(s){s=SS(s);var at=s.indexOf('@');return at>0&&at<s.length-1&&s.indexOf(' ')<0&&s.indexOf('.',at+1)>at+1;},isLink:function(s){s=SS(s);return s.indexOf('http://')===0||s.indexOf('https://')===0;},md5:function(s){return _nn('md5',[SS(s)]);},sha1:function(s){return _nn('sha1',[SS(s)]);},sha256:function(s){return _nn('sha256',[SS(s)]);},sha512:function(s){return _nn('sha512',[SS(s)]);},base64Encode:function(s){return base64Api.encode(SS(s));},base64Decode:function(s){return base64Api.decode(SS(s));},aes128Encrypt:function(s,k){return _nn('aes128Encrypt',[SS(s),String(k==null?'':k)]);},aes128Decrypt:function(s,k){return _nn('aes128Decrypt',[SS(s),String(k==null?'':k)]);},toPinYin:function(s){return _nn('toPinYin',[SS(s)]);},stripUtf8Bom:function(s){s=SS(s);return s.charCodeAt(0)===0xFEFF?s.substring(1):s;},fromUnicode:function(s){return SS(s).replace(/\\\\u([0-9a-fA-F]{4})/g,function(m,h){return String.fromCharCode(parseInt(h,16));});},startWith:function(s,p){s=SS(s);p=String(p==null?'':p);return s.indexOf(p)===0;},endWith:function(s,f){s=SS(s);f=String(f==null?'':f);return f.length===0||s.slice(-f.length)===f;},contains:function(s,sub){return SS(s).indexOf(String(sub==null?'':sub))>=0;},indexOf:function(s,sub,from){return SS(s).indexOf(String(sub==null?'':sub),from==null?0:Number(from));},lastIndexOf:function(s,sub){return SS(s).lastIndexOf(String(sub==null?'':sub));},substring:function(s,a,b){s=SS(s);a=Number(a)||0;return b==null?s.substring(a):s.substring(a,Number(b));},replaceAll:function(s,a,b){return SS(s).split(String(a==null?'':a)).join(String(b==null?'':b));},toUpperCase:function(s){return SS(s).toUpperCase();},toLowerCase:function(s){return SS(s).toLowerCase();},join:function(arr,sep){return (arr||[]).map(String).join(sep==null?',':String(sep));},repeat:function(s,n){s=SS(s);n=Math.max(0,Math.floor(Number(n)||0));var out='';while(n>0){out+=s;n--;}return out;},length:function(s){return SS(s).length;},padZero:function(s,n){s=SS(s);n=Number(n)||0;while(s.length<n)s='0'+s;return s;},padStart:function(s,n,p){s=SS(s);n=Number(n)||0;p=String(p==null?' ':p);while(s.length<n)s=p+s;return s;},padEnd:function(s,n,p){s=SS(s);n=Number(n)||0;p=String(p==null?' ':p);while(s.length<n)s+=p;return s;},format:function(){var args=Array.prototype.slice.call(arguments),pattern=String(args.length?args[0]:''),i=1;return pattern.replace(/%[sdf]/g,function(){var v=args[i++];return v==null?'':String(v);});},formatDate:function(ts,p){if(ts==null)ts=Date.now();var d=new Date(Number(ts));if(isNaN(d.getTime()))return String(ts);p=p||'yyyy-MM-dd HH:mm:ss';var P=function(v,n){return('000'+v).slice(-n);},W=['日','一','二','三','四','五','六'],M={'yyyy':String(d.getFullYear()),'MM':P(d.getMonth()+1,2),'dd':P(d.getDate(),2),'HH':P(d.getHours(),2),'mm':P(d.getMinutes(),2),'ss':P(d.getSeconds(),2),'SSS':P(d.getMilliseconds(),3),'E':W[d.getDay()]};return p.replace(/yyyy|MM|dd|HH|mm|ss|SSS|E/g,function(k){return M[k];});}}" + js.slice(ii);
}

// ---- T20: appApi.getFrontmostApp (EasyClick/AScript get_frontmost_app parity) ----
js = replaceOnce(js,
  "currentApp:function(){return _av('current');},",
  "currentApp:function(){return _av('current');},getFrontmostApp:function(){return _av('current');},",
  'T20a');
js = replaceOnce(js,
  "g.currentApp=appApi.currentApp;",
  "g.currentApp=appApi.currentApp;g.getFrontmostApp=appApi.getFrontmostApp;",
  'T20b');

// ---- T21: Baidu OCR wrapper (third-party OCR parity) ----
js = replaceOnce(js,
  "ocrText(text,timeoutMs){return ocrFind(text,timeoutMs,false);}base.getChild=function",
  "ocrText(text,timeoutMs){return ocrFind(text,timeoutMs,false);}function ocrBaidu(image,apiKey,secretKey,o){o=o||{};var b64=String(image==null?'':image);if(b64.indexOf('base64,')>=0)b64=b64.split('base64,')[1];if(!b64||!apiKey||!secretKey)return null;var t=o.timeoutMs==null?30000:o.timeoutMs;var tr=httpApi.post('https://aip.baidubce.com/oauth/2.0/token',null,{params:{grant_type:'client_credentials',client_id:String(apiKey),client_secret:String(secretKey)},parseJson:true,timeout:t});if(!tr||!tr.ok||!tr.json||!tr.json.access_token)return null;var r=httpApi.post('https://aip.baidubce.com/rest/2.0/ocr/v1/general_basic?access_token='+encodeURIComponent(String(tr.json.access_token)),'image='+b64.replace(/\\+/g,'%2B'),{headers:{'Content-Type':'application/x-www-form-urlencoded'},parseJson:true,timeout:t});if(!r||!r.ok||!r.json)return null;var wr=r.json.words_result;if(!Array.isArray(wr))return null;var lines=[],i;for(i=0;i<wr.length;i++){if(wr[i]&&wr[i].words)lines.push(String(wr[i].words));}return {text:lines.join('\\n'),lines:lines};}function ocrBaiduText(image,apiKey,secretKey,o){var res=ocrBaidu(image,apiKey,secretKey,o);return res?res.text:null;}base.getChild=function",
  'T21a');
js = replaceOnce(js,
  "g.ocr=base.ocr;g.ocrClick=ocrClick;g.ocrText=ocrText;",
  "g.ocr=base.ocr;g.ocrClick=ocrClick;g.ocrText=ocrText;g.ocrBaidu=ocrBaidu;g.ocrBaiduText=ocrBaiduText;",
  'T21b');

// ---- T22: compress httpApi method wrappers (Object.assign skips null/undefined sources) ----
js = replaceOnce(js,
  "httpApi.get=function(url,options){options=Object.assign({},options||{}, {method:'GET'});return httpApi(url,options);};httpApi.httpGet=httpApi.get;httpApi.httpGetDefault=httpApi.get;httpApi.post=function(url,body,options){options=Object.assign({},options||{}, {method:'POST',body:body});return httpApi(url,options);};httpApi.httpPost=httpApi.post;httpApi.postJSON=httpApi.post;httpApi.downloadFile=function(url,path,options){options=Object.assign({},options||{}, {method:'GET',downloadPath:String(path)});return Boolean(httpApi(url,options));};httpApi.downloadFileDefault=httpApi.downloadFile;httpApi.getJSON=function(url,options){options=Object.assign({},options||{}, {method:'GET',parseJson:true});return httpApi(url,options);};",
  "httpApi.get=function(url,options){return httpApi(url,Object.assign({},options,{method:'GET'}));};httpApi.httpGet=httpApi.get;httpApi.httpGetDefault=httpApi.get;httpApi.post=function(url,body,options){return httpApi(url,Object.assign({},options,{method:'POST',body:body}));};httpApi.httpPost=httpApi.post;httpApi.postJSON=httpApi.post;httpApi.downloadFile=function(url,path,options){return Boolean(httpApi(url,Object.assign({},options,{method:'GET',downloadPath:String(path)})));};httpApi.downloadFileDefault=httpApi.downloadFile;httpApi.getJSON=function(url,options){return httpApi(url,Object.assign({},options,{method:'GET',parseJson:true}));};",
  'T22');

// ---- T24: alias String/Number to Str/Num (reclaims ~600B bootstrap budget) ----
{
  const before = js.length;
  const strCount = js.split('String(').length - 1;
  const numCount = js.split('Number(').length - 1;
  // negative lookbehind: skip identifiers like toString( / instanceof patterns
  js = 'var Str=String,Num=Number;' + js.replace(/(?<![A-Za-z0-9_$.])String\(/g, 'Str(').replace(/(?<![A-Za-z0-9_$.])Number\(/g, 'Num(');
  console.log('T24 aliased String x' + strCount + ' Number x' + numCount + ' (saved', before - js.length, 'chars)');
}

// ---- T23: scanCode bridge (barcode/QR detection parity with AScript CodeScanner) ----
js = replaceOnce(js,
  "var screenApi={getColor:function(x,y){return bridge.invokePixelColor({x:x,y:y});},",
  "var screenApi={scanCode:function(p){return _nn('scanCode',[String(p||'')]);},getColor:function(x,y){return bridge.invokePixelColor({x:x,y:y});},",
  'T23a');
js = replaceOnce(js,
  "g.screen=screenApi;g.string=stringsApi;return drainTimers;",
  "g.screen=screenApi;g.scanCode=screenApi.scanCode;g.string=stringsApi;return drainTimers;",
  'T23b');

// ---- T25: WebSocket client (AScript WebSocket / kuaijs cloud parity) ----
js = replaceOnce(js,
  "var screenApi={scanCode:function(p){return _nn('scanCode',[String(p||'')]);},",
  "var wsApi={connect:function(u){return _nn('wsConnect',[String(u||'')]);},poll:function(h){return _nn('wsPoll',[Number(h)]);},send:function(h,t){return _nn('wsSend',[Number(h),String(t==null?'':t)]);},close:function(h){return _nn('wsClose',[Number(h)]);}};var screenApi={scanCode:function(p){return _nn('scanCode',[String(p||'')]);},",
  'T25a');
js = replaceOnce(js,
  "g.screen=screenApi;g.scanCode=screenApi.scanCode;g.string=stringsApi;return drainTimers;",
  "g.screen=screenApi;g.scanCode=screenApi.scanCode;g.ws=wsApi;g.string=stringsApi;return drainTimers;",
  'T25b');

// ---- T26: global shorthand exports for deviceApi members (EasyClick/AScript style) ----
js = replaceOnce(js,
  "g.getScreenWidthHeightText=deviceApi.getScreenWidthHeightText;",
  "g.getScreenWidthHeightText=deviceApi.getScreenWidthHeightText;g.getDeviceInfo=deviceApi.getDeviceInfo;g.getScreenWidth=deviceApi.getScreenWidth;g.getScreenHeight=deviceApi.getScreenHeight;g.getScale=deviceApi.getScale;g.getModel=deviceApi.getModel;g.getOSVersion=deviceApi.getOSVersion;g.getDeviceName=deviceApi.getDeviceName;g.getBattery=deviceApi.getBattery;g.isCharging=deviceApi.isCharging;g.getOrientation=deviceApi.getOrientation;g.getDeviceId=deviceApi.getDeviceId;g.getDeviceAlias=deviceApi.getDeviceAlias;g.getSerialNo=deviceApi.getSerialNo;g.volumeUp=deviceApi.volumeUp;g.volumeDown=deviceApi.volumeDown;g.getMemoryInfo=deviceApi.getMemoryInfo;",
  'T26');

// ---- T27: high-value shorthand globals (isRunning / isDir / isFile) ----
js = replaceOnce(js,
  "g.getScreenWidthHeightText=deviceApi.getScreenWidthHeightText;",
  "g.getScreenWidthHeightText=deviceApi.getScreenWidthHeightText;g.isRunning=appApi.isRunning;g.isDir=fileApi.isDir;g.isFile=fileApi.isFile;",
  'T27');

// ---- validation ----
console.log('new length:', js.length, 'limit:', 60 * 1024);
new vm.Script(js, { filename: 'bootstrap.js' });
const devLeft = js.match(/bridge\.invokeDevice\(\{/g) || [];
if (devLeft.length) { const lp = js.indexOf('bridge.invokeDevice({'); console.log('LEFT device@' + lp + ': ' + js.slice(lp - 90, lp + 90)); throw new Error('leftover invokeDevice({ x' + devLeft.length); }
if (/bridge\.invokeMedia\(\{/.test(js)) throw new Error('leftover invokeMedia({');
const natLeft = js.match(/bridge\.invokeNative\(\{/g) || [];
if (natLeft.length !== 1) throw new Error('invokeNative({ leftovers: ' + natLeft.length);
for (const req of ["g.ocrClick=ocrClick", "keepScreenOn:function(value)", "loadHTML:function(token,html)", "_nn('webViewLoadHTML'", "g.keepScreenOn=deviceApi.keepScreenOn","setFlashlight:function(on){return _dv('flashlight'","g.torch=deviceApi.setFlashlight","launchByScheme:function(name){return _av('launchByScheme'","g.getAppScheme=appApi.getAppScheme","getFrontmostApp:function(){return _av('current')","g.getFrontmostApp=appApi.getFrontmostApp","function ocrBaidu(","g.ocrBaidu=ocrBaidu"]) {
  if (!js.includes(req)) throw new Error('missing: ' + req);
}

// ---- write back: escape and chunk ----
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

// verify round-trip
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

