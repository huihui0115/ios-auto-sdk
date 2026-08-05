// Generates docs/api-reference.html (offline, EasyClick-style API reference).
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const APIS = [];

function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

const CATEGORIES = [
  { id: 'start',    name: '快速开始', color: '#2563eb' },
  { id: 'logs',     name: '日志与调试', color: '#0891b2' },
  { id: 'touch',    name: '触摸与节点', color: '#7c3aed' },
  { id: 'vision',   name: '图色与OCR', color: '#ea580c' },
  { id: 'app',      name: 'App与应用控制', color: '#16a34a' },
  { id: 'device',   name: '设备与系统', color: '#dc2626' },
  { id: 'metrics',  name: '坐标与屏幕', color: '#0ea5e9' },
  { id: 'file',     name: '文件', color: '#4f46e5' },
  { id: 'storage',  name: '存储', color: '#0d9488' },
  { id: 'http',     name: '网络HTTP', color: '#9333ea' },
  { id: 'media',    name: '相册媒体', color: '#db2777' },
  { id: 'timer',    name: '定时器与工具', color: '#64748b' }
];

const REFS = {
  'logd(message)': 'EasyClick logd() · AutoJS log()',
  'console.log': 'EasyClick logi()/logw()/loge() · AutoJS console.*',
  'toast(message)': 'EasyClick toast() · AutoJS toast()',
  'toastLog(message)': 'EasyClick toastLog() · AutoJS toast()',
  'sleep(milliseconds)': 'EasyClick sleep() · AutoJS sleep()',
  'click(selector)': 'EasyClick click() · AutoJS click()',
  'clickPoint(x, y)': 'EasyClick clickPoint() · AutoJS click(x, y)',
  'doubleClickPoint(x, y, interval?)': 'EasyClick doubleClickPoint() · AutoJS click(x, y, true)',
  'longClick(selector, duration?)': 'EasyClick longClick() · AutoJS longClick()',
  'swipe(x1, y1, x2, y2, duration?)': 'EasyClick swipe() · AutoJS swipe()',
  'input(selector, text)': 'EasyClick inputText() · AutoJS setText()',
  'setText(selector, text)': 'EasyClick inputText() 别名',
  'getText(selector)': 'EasyClick getText() · AutoJS text()',
  'exists(selector)': 'EasyClick exists() · AutoJS exists()',
  'findElement(selector)': 'EasyClick getNode() · AutoJS findOne()',
  'findElements(selector)': 'EasyClick getNodes() · AutoJS findOnce()',
  'waitFor(selector, timeoutMs?)': 'EasyClick waitNode() · AutoJS waitFor()',
  'getAttribute(selector, name)': 'EasyClick getAttribute() · AutoJS attr()',
  'getBounds(selector)': 'EasyClick getBounds() · AutoJS bounds()',
  'getChildren(selector)': 'EasyClick getChildren() · AutoJS children()',
  'getParent(selector)': 'EasyClick getParent() · AutoJS parent()',
  'scrollIntoView(selector)': 'EasyClick scrollTo() · AutoJS scrollForward()',
  'screenshot()': 'EasyClick screenshot() · AutoJS captureScreen()',
  'findImage(templatePath, options?)': 'EasyClick findImage() · AutoJS findImage()',
  'findColor(color, region?, options?)': 'EasyClick findColor() · AutoJS findColor()',
  'findMultiColor(color, offsets, region?, options?)': 'EasyClick findMultiColor() · AutoJS findMultiColor()',
  'getPixelColor(x, y)': 'EasyClick getPixelColor() · AutoJS images.pixel()',
  'ocr(options?)': 'EasyClick ocr() · AutoJS OCR（MLKit）',
  'launchApp(bundleId)': 'EasyClick launchApp() · AutoJS launchApp()',
  'activateApp(bundleId)': 'EasyClick activateApp() · AutoJS app.launch()',
  'terminateApp(bundleId)': 'EasyClick closeApp() · AutoJS app.close()',
  'appState(bundleId)': 'EasyClick getAppState()',
  'openURL(url)': 'EasyClick openUrl() · AutoJS app.openUrl()',
  'app.homeScreen()': 'EasyClick home()/lock()/unlock() · AutoJS home()',
  'device.getDeviceInfo()': 'EasyClick getDeviceInfo()',
  'device.getScreenWidth()': 'EasyClick getScreenWidth()/getScreenHeight() · AutoJS device.width/height',
  'device.getBattery()': 'EasyClick getBattery()/isCharging()',
  'device.getOrientation()': 'EasyClick getScreenOrientation()',
  'device.getClipboard()': 'EasyClick getClipboard()/setClipboard() · AutoJS setClip()',
  'device.getBrightness()': 'EasyClick getScreenBrightness()/setScreenBrightness()',
  'device.getVolume()': 'EasyClick getVolume()',
  'device.vibrate(durationMs?)': 'EasyClick vibrate()',
  'file.sandboxDir()': 'EasyClick 沙盒根目录',
  'file.readFile(path)': 'EasyClick readFile() · AutoJS files.read()',
  'file.writeFile(path, text)': 'EasyClick writeFile() · AutoJS files.write()',
  'file.exists(path)': 'EasyClick exists() · AutoJS files.exists()',
  'file.list(path)': 'EasyClick list() · AutoJS files.listDir()',
  'file.remove(path)': 'EasyClick remove() · AutoJS files.remove()',
  'file.copy(src, dest, overwrite?)': 'EasyClick copy() · AutoJS files.copy()',
  'file.move(src, dest, overwrite?)': 'EasyClick move() · AutoJS files.move()',
  'storages.create(name)': 'EasyClick storage() · AutoJS storages.create()',
  'store.putString': 'EasyClick putString()/putInt() · AutoJS put()',
  'store.getString': 'EasyClick getString()/getInt() · AutoJS get()',
  'http.get(url, options?)': 'EasyClick httpGet() · AutoJS http.get()',
  'http.post(url, body?, options?)': 'EasyClick httpPost() · AutoJS http.post()',
  'http.postJSON(url, body?, options?)': 'EasyClick httpPostJson() · AutoJS http.post()',
  'http.downloadFile(url, path, options?)': 'EasyClick downloadFile() · AutoJS http.download()',
  'http.request(url, options?)': 'EasyClick 通用请求',
  'media.saveImage(path)': 'EasyClick 保存图片到相册',
  'media.saveScreenshot()': 'EasyClick 截图存相册',
  'setTimeout(fn, ms, ...args)': 'EasyClick setTimeout()/clearTimeout()',
  'setInterval(fn, ms)': 'EasyClick setInterval()/clearInterval()',
  'time()': 'EasyClick time()/random() · AutoJS Date.now()/random()',
  'console.time(label)': 'AutoJS console.time()/timeEnd()',
  'setScreenMetrics(width, height)': 'EasyClick setScreenMetrics() · AutoJS setScreenMetrics()',
  'getScreenMetrics()': 'EasyClick getScreenMetrics() · AutoJS getScreenMetrics()',
  'metrics.point(x, y)': 'EasyClick 分辨率坐标适配',
  'device.width': 'AutoJS device.width/height',
  'auto.getChild(selector, index)': 'EasyClick getChild() · AutoJS child()',
  'auto.getSiblings(selector)': 'AutoJS siblings()',
  'auto.clickCenter(selector)': 'AutoJS 点击控件中心',
  'auto.clickRandom(selector)': '随机点击（防检测）',
  'swipeToPoint(x1, y1, x2, y2, duration?)': 'EasyClick swipeToPoint()',
  'swipeUp(percent?, durationMs?)': 'EasyClick swipe() 方向封装',
  'swipeDown(percent?, durationMs?)': 'EasyClick swipe() 方向封装',
  'swipeLeft(percent?, durationMs?)': 'EasyClick swipe() 方向封装',
  'swipeRight(percent?, durationMs?)': 'EasyClick swipe() 方向封装',
  'app.appList()': 'EasyClick getInstalledApps() · AutoJS app.getInstalledApps()',
  'screenshotRegion(x, y, width, height)': 'EasyClick image.clip() 区域截图',
  'childCount(selector)': 'EasyClick childcount()',
  'drag(x1, y1, x2, y2, durationMs?)': 'EasyClick drag()',
  'randomString(length?, chars?)': 'EasyClick utils.randomCharNumber()',
  'randomCharNumber(length?)': 'EasyClick utils.randomCharNumber()',
  'launchAppByPrefix(bundleIdPrefix)': 'EasyClick appLaunchByPrefix()',
  'app.launchByPrefix(bundleIdPrefix)': 'EasyClick appLaunchByPrefix()',
  'device.getScreenWidthHeightText()': 'EasyClick getScreenWidthHeightText()',
  'md5(text) / sha1(text)': 'EasyClick utils.dataMd5()',
  'file.md5(path) / file.md5File(path)': 'EasyClick utils.fileMd5()',
  'file.imageSize(path)': 'EasyClick image.getWidth()/getHeight()',
  'image.getSize(path)': 'EasyClick image.getWidth()/getHeight()',
  'findColorEx(colors, threshold?, x?, y?, ex?, ey?, limit?, direction?)': 'EasyClick image.findColorEx()',
  'playMp3(path, volume?, queue?, stopWhenScriptEnd?)': 'EasyClick utils.playMp3()',
  'stopMp3()': 'EasyClick utils.stopMp3()',
  'media.requestPhotoAuthorization()': 'EasyClick utils.requestPhotoAuthorization()',
  'media.getPhotoAuthorizationStatus()': 'EasyClick utils.requestPhotoAuthorization()',
  'findNotColor(colors, threshold?, x?, y?, ex?, ey?, limit?, direction?)': 'EasyClick image.findNotColor()',
  'image.clip(src, x, y, ex, ey, dest)': 'EasyClick image.clip()',
  'image.scale(src, width, height, dest)': 'EasyClick image.scaleBitmap()',
  'image.gray(src, dest)': 'EasyClick image.gray()',
  'image.binaryzation(src, dest, threshold?)': 'EasyClick image.binaryzation()',
  'image.rotate(src, degrees, dest)': 'EasyClick image.rotateImage()',
  'image.pixelAt(src, x, y)': 'EasyClick image.pixelInImage()',
  'image.getWidth(path) / image.getHeight(path)': 'EasyClick image.getWidth()/getHeight()',  'http.getJSON(url, options?)': 'EasyClick httpGetJson() · AutoJS http.get()+JSON',
  'uuid()': 'EasyClick uuid()',
  'base64.encode(str)': 'EasyClick base64.encode()/decode()',
  'file.zip(dest, sources, passwd?)': 'EasyClick utils.zip()',
  'file.unzip(zipPath, dest, passwd?)': 'EasyClick utils.unzip()/unzipWithEncode()',
  'file.readFileInZip(zipPath, entry, passwd?)': 'EasyClick utils.readFileInZip()',
  'file.readExcelAllRow(path, sheetIndex?)': 'EasyClick file.readExcelAllRow()',
  'file.readExcelRow(path, sheetIndex?, row?)': 'EasyClick file.readExcelRow()',
  'device.getDeviceId()': 'EasyClick getDeviceId()',
  'device.getDeviceAlias() / getSerialNo()': 'EasyClick getDeviceAlias()/getSerialNo()',
  'app.getAppVersion() / getPackageName()': 'EasyClick version/ipaVersion/getPackageName()'
};
function card(api) {
  const ref = REFS[api.sig.split(' / ')[0].trim()];
  const refLine = ref ? `<div class="ref"><b>对标</b> ${esc(ref)}</div>` : '';
  const params = (api.params || []).map(([n, t, d]) =>
    `<div class="param"><code class="pname">${esc(n)}</code><span class="ptype">${esc(t)}</span><span class="pdesc">${esc(d)}</span></div>`).join('');
  return `<article class="card" data-search="${esc(api.sig + ' ' + api.title)}">
  <header class="card-head">
    <h4><code>${esc(api.sig)}</code> <span class="cname">${esc(api.title)}</span></h4>
    <button class="copy" data-copy>复制</button>
  </header>
  <p class="desc">${esc(api.desc)}</p>
  ${refLine}
  ${params ? `<div class="params"><b>参数</b>${params}</div>` : ''}
  <div class="ret"><b>返回值</b> <span>${esc(api.returns)}</span></div>
  <pre><code>${esc(api.example)}</code></pre>
</article>`;
}


// ==== 补齐：设备与系统 ====
APIS.push({ cat:'device', sig:'device.getOSVersion()', title:'系统版本', desc:'返回 iOS 系统版本号，如 "17.5"。', params:[], returns:'string', example:`function main(){
  logd("iOS: " + device.getOSVersion());
}
main();` });
APIS.push({ cat:'device', sig:'device.getDeviceName()', title:'设备名称', desc:'返回设备显示名称（设置 → 通用 → 关于本机里的名称）。', params:[], returns:'string', example:`function main(){
  toast("设备: " + device.getDeviceName());
}
main();` });
APIS.push({ cat:'device', sig:'device.isCharging()', title:'是否充电中', desc:'返回当前是否正在充电。', params:[], returns:'boolean', example:`function main(){
  if (device.isCharging()) toastLog("正在充电");
  else toastLog("未充电");
}
main();` });
APIS.push({ cat:'device', sig:'device.getScreenWidth() / device.getScreenHeight()', title:'屏幕宽高（点）', desc:'返回屏幕逻辑尺寸，单位是点（pt），不是像素。', params:[], returns:'number', example:`function main(){
  const w = device.getScreenWidth();
  const h = device.getScreenHeight();
  toastLog("屏幕: " + w + " x " + h);
}
main();` });
APIS.push({ cat:'device', sig:'device.width() / device.height() / device.scale() / device.getScale() / device.info()', title:'屏幕尺寸与信息简写', desc:'width/height 返回屏幕宽高（点），scale/getScale 返回缩放比，info 等价 getDeviceInfo。', params:[], returns:'number | object', example:`function main(){
  logd("宽=" + device.width() + " 高=" + device.height());
  logd("缩放=" + device.scale());
  logd(JSON.stringify(device.info()));
}
main();` });APIS.push({ cat:'device', sig:'device.setBrightness(value)', title:'设置屏幕亮度', desc:'设置屏幕亮度，value 范围 0～1。', params:[['value','number','0～1 的亮度值']], returns:'boolean', example:`function main(){
  device.setBrightness(0.5);
  auto.sleep(500);
  device.setBrightness(device.getBrightness());
}
main();` });

// ==== 补齐：App 与应用控制 ====
APIS.push({ cat:'app', sig:'app.launch(bundleId)', title:'启动应用', desc:'按 bundle id 启动应用。', params:[['bundleId','string','如 com.apple.mobilesafari']], returns:'boolean', example:`function main(){
  app.launch("com.apple.mobilesafari");
  auto.sleep(1500);
}
main();` });
APIS.push({ cat:'app', sig:'app.activate(bundleId)', title:'激活应用', desc:'把已安装的应用带到前台。', params:[['bundleId','string','应用 bundle id']], returns:'boolean', example:`function main(){
  app.activate("com.apple.Preferences");
}
main();` });
APIS.push({ cat:'app', sig:'app.terminate(bundleId)', title:'结束应用', desc:'终止指定应用进程。', params:[['bundleId','string','应用 bundle id']], returns:'boolean', example:`function main(){
  app.terminate("com.apple.mobilesafari");
}
main();` });
APIS.push({ cat:'app', sig:'app.state(bundleId)', title:'应用状态', desc:'返回应用运行状态（0 未知 / 1 未运行 / 2 前台 / 3 后台）。', params:[['bundleId','string','应用 bundle id']], returns:'number', example:`function main(){
  const state = app.state("com.apple.mobilesafari");
  toastLog("状态码: " + state);
}
main();` });
APIS.push({ cat:'app', sig:'app.lock() / app.unlock()', title:'锁屏 / 解锁', desc:'锁屏或解锁设备（需 WDA systemActions 能力）。', params:[], returns:'boolean', example:`function main(){
  app.lock();
  auto.sleep(1000);
  app.unlock();
}
main();` });

// ==== 补齐：控制台 ====
APIS.push({ cat:'logs', sig:'console.log / debug / info / warn / error', title:'分级日志', desc:'console 系列分级日志；调试服务器实时转发到 VS Code 输出面板。', params:[['values','any[]','可打印任意值']], returns:'void', example:`function main(){
  console.debug("调试");
  console.info("信息");
  console.warn("警告");
  console.error("错误");
}
main();` });
APIS.push({ cat:'logs', sig:'console.time(label) / console.timeEnd(label)', title:'计时', desc:'对一段代码计时，timeEnd 返回耗时毫秒。', params:[['label','string','计时标签']], returns:'number | null', example:`function main(){
  console.time("task");
  auto.sleep(100);
  const ms = console.timeEnd("task");
  logd("耗时: " + ms + "ms");
}
main();` });
APIS.push({ cat:'logs', sig:'logi(message) / logw(message) / loge(message)', title:'日志简写', desc:'EasyClick 风格日志简写：信息 / 警告 / 错误。', params:[['message','any','内容']], returns:'void', example:`function main(){
  logi("信息");
  logw("警告");
  loge("错误");
}
main();` });

// ==== 补齐：文件常用操作 ====
APIS.push({ cat:'file', sig:'file.writeText(path, text)', title:'写文本', desc:'把文本写入沙盒文件（自动建目录）。', params:[['path','string','沙盒内路径'],['text','string','文本内容']], returns:'boolean', example:`function main(){
  file.writeText("data/note.txt", "hello");
  logd(file.readText("data/note.txt"));
}
main();` });
APIS.push({ cat:'file', sig:'file.getSandBoxDir() / file.getSandBoxFilePath(path) / file.resolvePath(path)', title:'沙盒路径查询', desc:'返回沙盒根目录、指定路径的完整沙盒路径。', params:[['path','string','沙盒内路径']], returns:'string', example:`function main(){
  logd("沙盒根: " + file.getSandBoxDir());
  logd("完整路径: " + file.getSandBoxFilePath("data/a.txt"));
}
main();` });APIS.push({ cat:'file', sig:'file.mkdirs(path)', title:'递归建目录', desc:'递归创建目录，父目录不存在也会创建。', params:[['path','string','沙盒内目录路径']], returns:'boolean', example:`function main(){
  file.mkdirs("logs/2026/08");
  logd("created");
}
main();` });
APIS.push({ cat:'file', sig:'file.deleteAllFile(path)', title:'删除文件/目录', desc:'删除文件或整个目录（含子内容）。', params:[['path','string','沙盒内路径']], returns:'boolean', example:`function main(){
  file.deleteAllFile("data/note.txt");
}
main();` });
APIS.push({ cat:'file', sig:'file.readAllLines(path)', title:'读取所有行', desc:'按行读取整个文件，返回字符串数组。', params:[['path','string','沙盒内路径']], returns:'string[]', example:`function main(){
  const lines = file.readAllLines("data/list.txt");
  for (const line of lines) logd(line);
}
main();` });

// ==== 补齐：命名存储 ====
APIS.push({ cat:'storage', sig:'auto.storage(name)', title:'storage 别名', desc:'等价于 storages.create(name)，方便链式调用。', params:[['name','string','存储空间名']], returns:'AutoStorage', example:`function main(){
  const store = auto.storage("cfg");
  store.put("key", 1);
}
main();` });APIS.push({ cat:'storage', sig:'storages.create(name).put(key, value)', title:'写入键值', desc:'把任意 JSON 可序列化值写入命名存储。', params:[['name','string','存储空间名'],['key','string','键'],['value','any','值']], returns:'boolean', example:`function main(){
  const store = storages.create("cfg");
  store.put("count", 3);
  store.put("name", "AutoSDK");
}
main();` });
APIS.push({ cat:'storage', sig:'storages.create(name).get(key, default?)', title:'读取键值', desc:'读取存储值，key 不存在时返回默认值。', params:[['key','string','键'],['default','any','可选的默认值']], returns:'any', example:`function main(){
  const store = storages.create("cfg");
  const count = store.get("count", 0);
  toastLog("count=" + count);
}
main();` });
APIS.push({ cat:'storage', sig:'putString / putInt / putBoolean / putFloat / getString / getInt / getBoolean / getFloat', title:'类型化存取', desc:'带类型的读写，避免 JSON 序列化歧义。', params:[['key','string','键'],['value','string|number|boolean','对应类型的值']], returns:'any', example:`function main(){
  const store = storages.create("cfg");
  store.putInt("retry", 3);
  store.putBoolean("enabled", true);
  logd("retry=" + store.getInt("retry", 0));
  logd("enabled=" + store.getBoolean("enabled", false));
}
main();` });
APIS.push({ cat:'storage', sig:'storages.create(name).keys() / all() / contains(key) / clear()', title:'遍历与清空', desc:'列出所有键、导出全部键值、判断键是否存在、清空存储。', params:[['key','string','键（contains 需要）']], returns:'string[] | object | boolean | void', example:`function main(){
  const store = storages.create("cfg");
  logd("keys=" + JSON.stringify(store.keys()));
  logd("all=" + JSON.stringify(store.all()));
  logd("has=" + store.contains("retry"));
  store.clear();
}
main();` });

// ==== 补齐：HTTP 别名 ====
APIS.push({ cat:'http', sig:'httpGet(url, options?) / httpPost(url, body?, options?)', title:'HTTP 全局简写', desc:'AutoJS 风格全局简写，等价于 http.get / http.post。', params:[['url','string','请求地址'],['body','any','POST 请求体'],['options','object','可选配置']], returns:'AutoHTTPResponse', example:`function main(){
  if (auto.capabilities().http !== true) return;
  const r = httpGet("https://example.com", { timeout: 5000 });
  logd("status=" + r.status);
}
main();` });
APIS.push({ cat:'http', sig:'httpGetDefault(url, options?) / httpPostDefault(url, body?, options?)', title:'HTTP 默认值简写', desc:'带默认请求头/超时的简写，等价于默认参数版。', params:[['url','string','请求地址'],['body','any','POST 请求体']], returns:'AutoHTTPResponse', example:`function main(){
  if (auto.capabilities().http !== true) return;
  const r = httpGetDefault("https://example.com");
  logd("ok=" + r.ok);
}
main();` });
APIS.push({ cat:'http', sig:'http.downloadFileDefault(url, path, options?)', title:'下载文件（默认参数）', desc:'把 URL 下载到沙盒文件，使用默认参数。', params:[['url','string','文件地址'],['path','string','沙盒保存路径'],['options','object','可选配置']], returns:'boolean', example:`function main(){
  if (auto.capabilities().http !== true) return;
  const ok = http.downloadFileDefault("https://example.com/a.png", "tmp/a.png");
  toastLog("下载: " + ok);
}
main();` });

// ==== 补齐：相册别名 ====
APIS.push({ cat:'media', sig:'saveImageToAlbum(path) / saveImageBase64ToAlbum(base64) / saveScreenshotToAlbum() / saveVideoToAlbum(path)', title:'相册全局简写', desc:'全局函数简写，等价于 media.saveImage / saveImageBase64 / saveScreenshot / saveVideo。', params:[['path','string','沙盒文件路径'],['base64','string','图片 Base64']], returns:'boolean', example:`function main(){
  if (auto.capabilities().mediaLibraryWrite !== true) return;
  saveScreenshotToAlbum();
  saveImageBase64ToAlbum("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==");
}
main();` });
APIS.push({ cat:'media', sig:'image 对象（findImage / findColor / pixel / screenshot / saveToAlbum）', title:'image 别名对象', desc:'image.* 提供图色与相册的集中入口，等价于 auto 上的同名方法。', params:[], returns:'见具体方法', example:`function main(){
  const p = image.pixel(100, 200);
  logd("颜色: " + p.hex);
  image.saveScreenshotToAlbum();
}
main();` });

// ==== 补齐：工具与全局别名 ====
APIS.push({ cat:'timer', sig:'clearTimeout(id) / cancelTimeout(id) / clearInterval(id) / cancelInterval(id)', title:'取消定时器', desc:'取消已创建的定时器；两种命名都可用。', params:[['id','number','定时器 ID']], returns:'void', example:`function main(){
  const timer = setTimeout(function () { logd("tick"); }, 1000);
  clearTimeout(timer);
  logd("cancelled");
}
main();` });
APIS.push({ cat:'timer', sig:'random(min, max?) / randomInt(min, max?)', title:'随机数', desc:'返回 [min, max] 闭区间随机整数。', params:[['min','number','最小值'],['max','number','最大值（可选）']], returns:'number', example:`function main(){
  const x = random(0, 100);
  const y = randomInt(0, 100);
  toastLog("随机: " + x + ", " + y);
}
main();` });
APIS.push({ cat:'timer', sig:'randomString(length?, chars?)', title:'随机字符串', desc:'生成指定长度的随机字符串，默认 8 位字母+数字；chars 可自定义字符集。', params:[['length','number','可选，长度，默认 8'],['chars','string','可选，字符集']], returns:'string', example:`function main(){
  logd(randomString(6));            // 例如 aB3xYz
  logd(randomString(4, "0123456789")); // 4 位数字
}
main();` });
APIS.push({ cat:'timer', sig:'randomCharNumber(length?)', title:'随机字母数字串', desc:'EasyClick 兼容别名：生成字母+数字混合随机串，默认 8 位。', params:[['length','number','可选，长度，默认 8']], returns:'string', example:`function main(){
  const code = randomCharNumber(6);
  logd("验证码: " + code);
}
main();` });
APIS.push({ cat:'media', sig:'playMp3(path, volume?, queue?, stopWhenScriptEnd?) / stopMp3()', title:'播放 MP3 音频', desc:'用系统音频播放沙盒内 mp3 文件；volume 为 0-100 音量（默认 100），queue=true 时排队到当前曲目结束后播放，stopWhenScriptEnd=true 时脚本结束自动停止。', params:[['path','string','沙盒内音频文件路径'],['volume','number','音量 0-100，默认 100'],['queue','boolean','是否排队播放，默认 false'],['stopWhenScriptEnd','boolean','脚本结束时停止，默认 false']], returns:'boolean', example:`function main(){
  const ok = playMp3("sounds/alert.mp3", 80, false, true);
  logd("播放: " + ok);
  auto.sleep(5000);
  stopMp3();
}
main();` });
APIS.push({ cat:'media', sig:'media.requestPhotoAuthorization() / media.getPhotoAuthorizationStatus()', title:'相册权限', desc:'requestPhotoAuthorization 在首次调用时弹出系统授权（异步返回当前状态）；getPhotoAuthorizationStatus 只读取当前权限状态，不会弹窗。返回值为 notDetermined/restricted/denied/authorized/limited。', params:[], returns:'string 权限状态', example:`function main(){
  logd("相册权限: " + getPhotoAuthorizationStatus());
  const status = media.requestPhotoAuthorization();
  logd("请求后: " + status);
  if (status === "authorized" || status === "limited") saveImageToAlbum("images/a.png");
}
main();` });APIS.push({ cat:'timer', sig:'md5(text) / sha1(text)', title:'哈希', desc:'对字符串计算 MD5 或 SHA1 十六进制摘要，可用于请求签名、文件去重。', params:[['text','string','任意字符串']], returns:'string', example:`function main(){
  logd("md5: " + md5("hello"));
  logd("sha1: " + sha1("hello"));
}
main();` });APIS.push({ cat:'timer', sig:'uuid() / uniqueId()', title:'唯一 ID', desc:'生成 UUID 字符串。', params:[], returns:'string', example:`function main(){
  logd(uuid());
  logd(uniqueId());
}
main();` });
APIS.push({ cat:'timer', sig:'setClipboard(text) / setBrightness(value)', title:'系统全局简写', desc:'全局函数简写，等价于 device.setClipboard / device.setBrightness。', params:[['text','string','剪贴板文本'],['value','number','亮度 0～1']], returns:'boolean', example:`function main(){
  setClipboard("hello");
  logd(getClipboard());
}
main();` });
APIS.push({ cat:'metrics', sig:'metrics.get() / metrics.set(w, h) / metrics.x(v) / metrics.y(v)', title:'屏幕坐标换算', desc:'读取/设置屏幕逻辑尺寸，把坐标按缩放换算。', params:[['w','number','宽'],['h','number','高'],['v','number','坐标值']], returns:'AutoMetrics | boolean | number', example:`function main(){
  const m = metrics.get();
  logd("屏幕: " + m.width + " x " + m.height);
  const px = metrics.x(50);
  logd("x(50)=" + px);
}
main();` });
APIS.push({ cat:'base64', sig:'base64.encode(text) / base64.decode(base64)', title:'Base64 编解码', desc:'文本与 Base64 互转。', params:[['text','string','原文'],['base64','string','Base64 串']], returns:'string', example:`function main(){
  const enc = base64.encode("hello");
  logd(enc);
  logd(base64.decode(enc));
}
main();` });
function render() {
  const sidebar = CATEGORIES.map(c => `<a href="#${c.id}" style="--c:${c.color}">${esc(c.name)}<span>${APIS.filter(a => a.cat === c.id).length}</span></a>`).join('');
  const sections = CATEGORIES.map(c => {
    const items = APIS.filter(a => a.cat === c.id).map(card).join('\n');
    return `<section id="${c.id}" class="cat" style="--c:${c.color}">
  <h2><span class="tag">${esc(c.name)}</span><i>${items ? APIS.filter(a => a.cat === c.id).length : ''}</i></h2>
  ${items || '<p class="empty">（暂无）</p>'}
</section>`;
  }).join('\n');

  return `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AutoSDK 脚本函数参考</title>
<style>
:root{--bg:#0f172a;--panel:#1e293b;--card:#1e293b;--line:#334155;--text:#e2e8f0;--muted:#94a3b8;--code:#0b1220;--accent:#38bdf8;}
*{box-sizing:border-box}
body{margin:0;font:15px/1.65 -apple-system,"PingFang SC","Microsoft YaHei",sans-serif;background:var(--bg);color:var(--text)}
header.top{position:sticky;top:0;z-index:20;background:rgba(15,23,42,.92);backdrop-filter:blur(6px);border-bottom:1px solid var(--line);padding:14px 22px;display:flex;align-items:center;gap:14px;flex-wrap:wrap}
header.top h1{font-size:18px;margin:0;white-space:nowrap}
header.top h1 span{color:var(--accent)}
.search{flex:1;min-width:220px}
.search input{width:100%;padding:8px 12px;border-radius:8px;border:1px solid var(--line);background:var(--code);color:var(--text);font-size:14px;outline:none}
.search input:focus{border-color:var(--accent)}
.hint{font-size:12px;color:var(--muted)}
.layout{display:flex;gap:0;max-width:1400px;margin:0 auto}
nav.side{position:sticky;top:64px;align-self:flex-start;width:200px;flex:0 0 200px;padding:18px 14px;border-right:1px solid var(--line);height:calc(100vh - 64px);overflow:auto}
nav.side a{display:flex;justify-content:space-between;align-items:center;padding:7px 10px;border-radius:8px;color:var(--text);text-decoration:none;font-size:14px;border-left:3px solid transparent;margin-bottom:2px}
nav.side a:hover{background:var(--panel)}
nav.side a span{font-size:11px;background:var(--code);border:1px solid var(--line);border-radius:999px;padding:0 7px;color:var(--muted)}
main{flex:1;min-width:0;padding:20px 26px 80px}
section.cat{margin-bottom:34px}
section.cat>h2{display:flex;align-items:center;gap:10px;font-size:20px;border-bottom:2px solid var(--line);padding-bottom:8px;margin:26px 0 16px}
section.cat>h2 .tag{color:#fff;background:var(--c);padding:3px 12px;border-radius:999px;font-size:15px}
section.cat>h2 i{font-style:normal;font-size:12px;color:var(--muted)}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 16px;margin:0 0 14px}
.card-head{display:flex;justify-content:space-between;align-items:flex-start;gap:10px}
.card h4{margin:0;font-size:15px;font-family:ui-monospace,Consolas,monospace;word-break:break-all}
.card h4 .cname{font-family:inherit;color:var(--muted);font-weight:500;font-size:13px}
button.copy{flex:0 0 auto;background:var(--c,var(--accent));border:0;color:#fff;border-radius:6px;padding:4px 12px;font-size:12px;cursor:pointer}
button.copy.done{background:#16a34a}
.desc{margin:10px 0 8px;color:var(--text)}
.params{margin:6px 0;display:flex;flex-direction:column;gap:3px}
.params b,.ret b{color:var(--accent);font-size:12px;margin-right:8px}
.param{display:flex;gap:10px;font-size:13px;align-items:baseline;padding-left:10px}
.pname{color:#fbbf24}
.ptype{color:#67e8f9;font-size:12px}
.pdesc{color:var(--muted)}
.ret{font-size:13px;color:var(--text)}
.ref{font-size:12px;color:var(--muted);margin:8px 0 4px}
.ref b{color:#fbbf24;font-weight:600;margin-right:6px}
pre{background:var(--code);border:1px solid var(--line);border-radius:8px;padding:12px;overflow:auto;margin:10px 0 0}
pre code{font:12.5px/1.6 ui-monospace,Consolas,monospace;color:#a5f3fc;white-space:pre}
.empty{color:var(--muted)}
#toast-copy{position:fixed;bottom:26px;left:50%;transform:translateX(-50%) translateY(20px);background:#16a34a;color:#fff;padding:8px 18px;border-radius:999px;font-size:13px;opacity:0;pointer-events:none;transition:.25s}
#toast-copy.show{opacity:1;transform:translateX(-50%)}
footer{color:var(--muted);font-size:12px;text-align:center;padding:18px}
@media(max-width:900px){nav.side{display:none}.layout{display:block}}
</style>
</head>
<body>
<header class="top">
  <h1>AutoSDK <span>脚本函数参考</span></h1>
  <div class="search"><input id="q" type="search" placeholder="搜索函数，例如 readFile / click / saveImage …"><div class="hint">离线文档 · 点击每个示例的“复制”即可直接粘贴到脚本</div></div>
</header>
<div class="layout">
<nav class="side">${sidebar}</nav>
<main>
<section id="start" class="cat" style="--c:#2563eb">
<h2><span class="tag">快速开始</span><i>连接与运行</i></h2>
<div class="card">
<header class="card-head"><h4>最小可运行脚本</h4><button class="copy" data-copy>复制</button></header>
<p class="desc">连上手机后（USB：<code>iproxy 9001:9001</code> + <code>ws://127.0.0.1:9001</code>；Wi-Fi：<code>ws://手机IP:9001</code> + token），把下面代码粘到 VS Code，按 <b>AutoSDK: Run Current Script</b>。</p>
<div class="params"><b>参数</b><span class="pdesc">无需参数</span></div>
<div class="ret"><b>返回值</b> <span>控制台实时输出日志</span></div>
<pre><code>function main(){
  toastLog("脚本已启动");
  logd("设备: " + device.getModel() + " / iOS " + device.getOSVersion());
  logd("屏幕: " + device.getScreenWidth() + "x" + device.getScreenHeight());
  logd("能力: " + JSON.stringify(auto.capabilities()));
  const png = screenshot();
  logd("截屏成功，PNG base64 长度 = " + png.length);
  toastLog("全部调试输出完成");
}
main();</code></pre>
</div>
</section>
${sections}
</main>
</div>
<footer>AutoSDK 离线函数参考 · 共 ${APIS.length} 个函数 · 对标 EasyClick/AutoScript · 生成于 ${new Date().getFullYear()}-${String(new Date().getMonth()+1).padStart(2,"0")}-${String(new Date().getDate()).padStart(2,"0")} · 浏览器双击即开</footer>
<div id="toast-copy">已复制到剪贴板</div>
<script>
const q = document.getElementById('q');
const cards = Array.from(document.querySelectorAll('.card'));
q.addEventListener('input', () => {
  const text = q.value.trim().toLowerCase();
  for (const card of cards) {
    card.style.display = (!text || card.dataset.search.toLowerCase().includes(text)) ? '' : 'none';
  }
});
async function copyText(text) {
  try { await navigator.clipboard.writeText(text); return true; }
  catch (_) {
    const ta = document.createElement('textarea');
    ta.value = text; document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); } finally { ta.remove(); }
    return true;
  }
}
const toast = document.getElementById('toast-copy');
document.addEventListener('click', async ev => {
  const btn = ev.target.closest('button[data-copy]');
  if (!btn) return;
  const code = btn.closest('.card').querySelector('pre code');
  if (!code) return;
  await copyText(code.textContent);
  const old = btn.textContent;
  btn.textContent = '已复制';
  btn.classList.add('done');
  toast.classList.add('show');
  setTimeout(() => { btn.textContent = old; btn.classList.remove('done'); toast.classList.remove('show'); }, 1200);
});
document.addEventListener('keydown', ev => {
  if (ev.key === '/' && document.activeElement !== q) { ev.preventDefault(); q.focus(); }
  if (ev.key === 'Escape' && document.activeElement === q) { q.value = ''; q.dispatchEvent(new Event('input')); }
});
</script>
</body>
</html>`;
}

APIS.push({ cat:'logs', sig:'logd(message)', title:'调试日志（debug）', desc:'打印调试日志，等价于 console.log。', params:[['message','any','要打印的内容']], returns:'void', example:`function main(){
  const name = "AutoSDK";
  logd("开始运行: " + name);
  logi("普通信息");
  logw("警告");
  loge("错误");
}
main();` });
APIS.push({ cat:'logs', sig:'console.log / console.info(message)', title:'控制台日志', desc:'console 系列输出日志；调试服务器会把它们实时发到 VS Code 输出面板。', params:[['message','any','内容']], returns:'void', example:`function main(){
  console.log("普通日志");
  console.info("信息");
  console.warn("警告");
  console.error("错误");
}
main();` });
APIS.push({ cat:'logs', sig:'toast(message)', title:'悬浮提示', desc:'在手机上显示短暂悬浮提示（宿主 App 主窗口）。', params:[['message','string','提示文字']], returns:'boolean 是否成功显示', example:`function main(){
  toast("脚本运行中");
  toastLog("提示并写入日志");
}
main();` });
APIS.push({ cat:'logs', sig:'toastLog(message)', title:'提示并记录日志', desc:'toast 提示的同时写入一条日志。', params:[['message','string','提示文字']], returns:'void', example:`function main(){
  toastLog("任务开始");
  auto.sleep(1000);
  toastLog("任务结束");
}
main();` });
APIS.push({ cat:'logs', sig:'sleep(milliseconds)', title:'暂停', desc:'协作式暂停毫秒数，可被停止按钮中断，不会死循环占满 CPU。', params:[['milliseconds','number','毫秒']], returns:'boolean', example:`function main(){
  logd("等待 1 秒…");
  sleep(1000);
  logd("继续执行");
}
main();` });

APIS.push({ cat:'touch', sig:'click(selector)', title:'点击节点', desc:'点击第一个匹配的控件节点。', params:[['selector','object|string','节点选择器或节点句柄']], returns:'boolean', example:`function main(){
  const ok = click({text: "确定"});
  logd("点击结果: " + ok);
}
main();` });
APIS.push({ cat:'touch', sig:'clickPoint(x, y)', title:'坐标点击', desc:'在屏幕坐标 (x, y) 处点击。', params:[['x','number','横坐标'],['y','number','纵坐标']], returns:'boolean', example:`function main(){
  const ok = clickPoint(190, 400);
  logd("坐标点击: " + ok);
}
main();` });
APIS.push({ cat:'touch', sig:'doubleClickPoint(x, y, interval?)', title:'双击', desc:'在坐标处双击，interval 为两次点击间隔秒数。', params:[['x','number','横坐标'],['y','number','纵坐标'],['interval','number','可选，间隔秒数']], returns:'boolean', example:`function main(){
  const ok = doubleClickPoint(190, 400, 0.05);
  logd("双击: " + ok);
}
main();` });
APIS.push({ cat:'touch', sig:'longClick(selector, duration?)', title:'长按', desc:'长按匹配节点；需要适配器支持真实触摸注入。', params:[['selector','object|string','选择器'],['duration','number','可选，按住秒数']], returns:'boolean', example:`function main(){
  const ok = longClick({text: "图标"}, 1.0);
  logd("长按: " + ok);
}
main();` });
APIS.push({ cat:'touch', sig:'gesture(actions)', title:'单指手势', desc:'按 W3C 指针动作序列执行单指手势：down/move/up/wait 会自动归一化为 pointerDown/pointerMove/pointerUp/pause。需要 WDA 适配器支持真实触摸注入（capabilities.multiTouch）。', params:[['actions','Array<{type,x,y,duration}>','动作序列：{type:"down",x,y} 按下、{type:"move",x,y,duration} 移动、{type:"up"} 抬起、{type:"wait",duration} 等待']], returns:'boolean', example:`function main(){
  const ok = auto.gesture([
    {type: "down", x: 100, y: 200},
    {type: "move", x: 300, y: 400, duration: 500},
    {type: "up"}
  ]);
  logd("手势: " + ok);
}
main();` });
APIS.push({ cat:'touch', sig:'multiGesture(fingers)', title:'多指手势', desc:'并行执行多根手指的触摸序列，每根手指一个动作数组；常用于双指缩放、旋转等复杂手势。需要 WDA 适配器支持真实触摸注入。', params:[['fingers','Array<Array<{type,x,y,duration}>>','每根手指的 down/move/up/wait 动作序列']], returns:'boolean', example:`function main(){
  const ok = auto.multiGesture([
    [{type: "down", x: 100, y: 300}, {type: "move", x: 100, y: 100, duration: 300}, {type: "up"}],
    [{type: "down", x: 300, y: 300}, {type: "move", x: 300, y: 100, duration: 300}, {type: "up"}]
  ]);
  logd("双指上滑: " + ok);
}
main();` });
APIS.push({ cat:'touch', sig:'pinch(x, y, scale, duration?)', title:'双指缩放', desc:'以 (x,y) 为中心双指缩放，scale>1 放大、scale<1 缩小；duration 为毫秒。需要 WDA 适配器支持真实触摸注入。', params:[['x','number','中心横坐标'],['y','number','中心纵坐标'],['scale','number','缩放倍率（>1 放大，<1 缩小）'],['duration','number','毫秒，默认 300']], returns:'boolean', example:`function main(){
  const ok = auto.pinch(200, 400, 1.5, 400);
  logd("放大: " + ok);
}
main();` });APIS.push({ cat:'touch', sig:'swipe(x1, y1, x2, y2, duration?)', title:'滑动', desc:'从 (x1,y1) 滑动到 (x2,y2)，duration 为秒数。', params:[['x1','number','起点横坐标'],['y1','number','起点纵坐标'],['x2','number','终点横坐标'],['y2','number','终点纵坐标'],['duration','number','可选，秒数']], returns:'boolean', example:`function main(){
  const ok = swipe(190, 600, 190, 200, 0.4);
  logd("上滑: " + ok);
}
main();` });
APIS.push({ cat:'touch', sig:'swipeUp(percent?, durationMs?)', title:'上滑', desc:'从屏幕下方 72% 处向上滑动，默认滑动 30% 屏高。percent 为滑动距离占比（0～1，默认 0.5，实际滑动 0.6×percent 屏高），durationMs 为毫秒（默认 300）。', params:[['percent','number','可选，0～1，滑动距离占比'],['durationMs','number','可选，毫秒']], returns:'boolean', example:`function main(){
  const ok = swipeUp(0.5, 300);   // 上滑半屏
  logd("上滑: " + ok);
  auto.sleep(500);
  swipeDown(0.5);                 // 回滑
}
main();` });
APIS.push({ cat:'touch', sig:'swipeDown(percent?, durationMs?)', title:'下滑', desc:'从屏幕上方 28% 处向下滑动，默认滑动 30% 屏高。percent 为滑动距离占比，durationMs 为毫秒（默认 300）。', params:[['percent','number','可选，0～1，滑动距离占比'],['durationMs','number','可选，毫秒']], returns:'boolean', example:`function main(){
  swipeDown(0.4, 250);
  logd("下滑完成");
}
main();` });
APIS.push({ cat:'touch', sig:'swipeLeft(percent?, durationMs?)', title:'左滑', desc:'从屏幕右侧 72% 处向左滑动，默认滑动 30% 屏宽。percent 为滑动距离占比，durationMs 为毫秒（默认 300）。', params:[['percent','number','可选，0～1，滑动距离占比'],['durationMs','number','可选，毫秒']], returns:'boolean', example:`function main(){
  swipeLeft(0.5);
  logd("左滑完成");
}
main();` });
APIS.push({ cat:'touch', sig:'swipeRight(percent?, durationMs?)', title:'右滑', desc:'从屏幕左侧 28% 处向右滑动，默认滑动 30% 屏宽。percent 为滑动距离占比，durationMs 为毫秒（默认 300）。', params:[['percent','number','可选，0～1，滑动距离占比'],['durationMs','number','可选，毫秒']], returns:'boolean', example:`function main(){
  swipeRight(0.5);
  logd("右滑完成");
}
main();` });APIS.push({ cat:'touch', sig:'drag(x1, y1, x2, y2, durationMs?)', title:'拖拽', desc:'从起点按下并按住，再移动到终点松开（长按拖拽），durationMs 为总毫秒数（默认 600）。需要 WDA 真实触摸注入。', params:[['x1','number','起点 X'],['y1','number','起点 Y'],['x2','number','终点 X'],['y2','number','终点 Y'],['durationMs','number','可选，毫秒']], returns:'boolean', example:`function main(){
  drag(190, 400, 190, 200, 800);   // 按住列表项向下拖动
}
main();` });
APIS.push({ cat:'touch', sig:'childCount(selector)', title:'子节点数量', desc:'返回第一个匹配节点的直接子节点数量。', params:[['selector','object|string','节点选择器']], returns:'number', example:`function main(){
  const count = childCount({text: "列表"});
  logd("子节点数: " + count);
}
main();` });APIS.push({ cat:'touch', sig:'input(selector, text)', title:'输入文字', desc:'向匹配的输入框填入文字（替换原内容）。', params:[['selector','object|string','输入框选择器'],['text','string','要输入的文字']], returns:'boolean', example:`function main(){
  const ok = input({type: "TextField"}, "hello");
  logd("输入结果: " + ok);
}
main();` });
APIS.push({ cat:'touch', sig:'setText(selector, text)', title:'输入文字（别名）', desc:'EasyClick 兼容别名，等价于 input()。', params:[['selector','object|string','输入框选择器'],['text','string','文字']], returns:'boolean', example:`function main(){
  setText({id: "input"}, "123456");
  logd("完成");
}
main();` });
APIS.push({ cat:'touch', sig:'getText(selector)', title:'读取节点文字', desc:'读取第一个匹配节点的文本。', params:[['selector','object|string','选择器']], returns:'string|null', example:`function main(){
  const text = getText({type: "Label"});
  logd("文字: " + text);
}
main();` });
APIS.push({ cat:'touch', sig:'exists(selector)', title:'节点是否存在', desc:'判断是否有匹配的节点。', params:[['selector','object|string','选择器']], returns:'boolean', example:`function main(){
  if (exists({text: "开始"})) {
    logd("找到“开始”按钮");
  } else {
    logd("未找到");
  }
}
main();` });
APIS.push({ cat:'touch', sig:'findElement(selector)', title:'查找单个节点', desc:'返回第一个匹配的稳定节点描述（含句柄、文本、类型、坐标）。', params:[['selector','object|string','选择器']], returns:'AutoNode|null', example:`function main(){
  const node = findElement({text: "登录"});
  if (node) {
    logd("节点: " + JSON.stringify(node));
    logd("中心点: " + node.bounds.centerX + "," + node.bounds.centerY);
  } else {
    logd("没找到");
  }
}
main();` });
APIS.push({ cat:'touch', sig:'findElements(selector)', title:'查找全部节点', desc:'返回所有匹配的节点描述数组。', params:[['selector','object|string','选择器']], returns:'AutoNode[]', example:`function main(){
  const nodes = findElements({type: "Button"});
  logd("按钮数量: " + nodes.length);
  for (const n of nodes) {
    logd(n.text + " @ " + JSON.stringify(n.bounds));
  }
}
main();` });
APIS.push({ cat:'touch', sig:'waitFor(selector, timeoutMs?)', title:'等待节点出现', desc:'轮询等待匹配节点，默认 10 秒超时。', params:[['selector','object|string','选择器'],['timeoutMs','number','可选，毫秒']], returns:'boolean', example:`function main(){
  const ok = waitFor({text: "加载完成"}, 15000);
  logd("等待结果: " + ok);
  if (ok) click({text: "加载完成"});
}
main();` });
APIS.push({ cat:'touch', sig:'getAttribute(selector, name)', title:'读取节点属性', desc:'读取节点的属性，如 type、label、enabled。', params:[['selector','object|string','选择器'],['name','string','属性名']], returns:'any', example:`function main(){
  const type = getAttribute({id: "btn"}, "type");
  logd("类型: " + type);
}
main();` });
APIS.push({ cat:'touch', sig:'getBounds(selector)', title:'读取节点坐标', desc:'返回节点的 {x, y, width, height} 点坐标系矩形。', params:[['selector','object|string','选择器']], returns:'AutoRect|null', example:`function main(){
  const rect = getBounds({text: "购买"});
  if (rect) logd(JSON.stringify(rect));
}
main();` });
APIS.push({ cat:'touch', sig:'getChildren(selector)', title:'子节点列表', desc:'返回节点的直接子节点描述数组。', params:[['selector','object|string','选择器']], returns:'AutoNode[]', example:`function main(){
  const children = getChildren({type: "Window"});
  logd("子节点数: " + children.length);
}
main();` });
APIS.push({ cat:'touch', sig:'getParent(selector)', title:'父节点', desc:'返回节点的父节点描述。', params:[['selector','object|string','选择器']], returns:'AutoNode|null', example:`function main(){
  const parent = getParent({id: "child"});
  logd(parent ? parent.type : "无父节点");
}
main();` });
APIS.push({ cat:'touch', sig:'scrollIntoView(selector)', title:'滚动到可见', desc:'将匹配节点滚动到可见区域。', params:[['selector','object|string','选择器']], returns:'boolean', example:`function main(){
  const ok = scrollIntoView({text: "底部按钮"});
  logd("滚动: " + ok);
  if (ok) click({text: "底部按钮"});
}
main();` });
APIS.push({ cat:'vision', sig:'screenshot()', title:'截屏', desc:'截取当前屏幕，返回 PNG 的 Base64 字符串。', params:[], returns:'string PNG base64', example:`function main(){
  const png = screenshot();
  logd("截图长度: " + png.length);
}
main();` });
APIS.push({ cat:'vision', sig:'screenshotRegion(x, y, width, height)', title:'区域截图', desc:'截取屏幕指定矩形区域，返回该区域 PNG 的 Base64 字符串；区域超出屏幕会自动裁剪到边界，完全不重叠时返回 null。', params:[['x','number','区域左上角 X'],['y','number','区域左上角 Y'],['width','number','区域宽度'],['height','number','区域高度']], returns:'string|null PNG base64', example:`function main(){
  // 只截取屏幕上方状态栏区域
  const png = screenshotRegion(0, 0, 390, 60);
  if (png) logd("区域截图长度: " + png.length);
}
main();` });APIS.push({ cat:'vision', sig:'image.getSize(path)', title:'图片尺寸（图像对象）', desc:'image 命名空间下的图片尺寸查询，等价 file.imageSize。', params:[['path','string','图片路径']], returns:'object {width, height, pixelWidth, pixelHeight, scale}', example:`function main(){
  const size = image.getSize("images/start.png");
  logd(size.width + " x " + size.height);
}
main();` });APIS.push({ cat:'vision', sig:'findImage(templatePath, options?)', title:'找图', desc:'在屏幕截图中查找模板图片，返回匹配位置与相似度。', params:[['templatePath','string','模板图片路径（沙盒内，支持 png/jpg）'],['options','object','可选，region/threshold 等']], returns:'AutoMatch {found, x, y, similarity}', example:`function main(){
  const match = findImage("images/start.png", {threshold: 0.9});
  if (match.found) {
    logd("找到，中心: " + match.centerX + "," + match.centerY);
    clickPoint(match.centerX, match.centerY);
  } else {
    logd("未找到");
  }
}
main();` });
APIS.push({ cat:'vision', sig:'findColor(color, region?, options?)', title:'找色', desc:'在指定区域内查找第一个匹配的颜色点。', params:[['color','string|[r,g,b]','颜色，如 "#ff0000"'],['region','object','可选，{x,y,width,height}'],['options','object','可选，tolerance 等']], returns:'AutoMatch {found, x, y}', example:`function main(){
  const match = findColor("#ff3b30", {x: 0, y: 0, width: 390, height: 844});
  if (match.found) logd("颜色点: " + match.x + "," + match.y);
}
main();` });
APIS.push({ cat:'vision', sig:'findColorEx(colors, threshold?, x?, y?, ex?, ey?, limit?, direction?)', title:'区域多点找色', desc:'在当前屏幕指定区域内查找所有匹配的颜色点，返回坐标数组（找不到返回 null）。colors 支持 EasyClick 风格字符串如 "0xCDD7E9-0x101010,0xFF0000"，也支持数组 ["#00FF00", [255,0,0], [255,0,0,16]]；threshold 为 0-1 相似度（默认 0.9），x/y/ex/ey 全为 0 表示全屏，limit 限制返回个数（默认 10），direction 1-8 控制扫描方向。', params:[['colors','string|array','颜色目标列表'],['threshold','number','0-1 相似度，默认 0.9'],['x','number','区域起点 X'],['y','number','区域起点 Y'],['ex','number','区域终点 X'],['ey','number','区域终点 Y'],['limit','number','最大返回点数，默认 10'],['direction','number','扫描方向 1-8，默认 1']], returns:'AutoPoint[] | null', example:`function main(){
  const points = findColorEx("0xCDD7E9-0x101010", 0.9, 0, 0, 0, 0, 10, 1);
  logd(JSON.stringify(points));
  if (points && points.length > 0) clickPoint(points[0].x, points[0].y);
}
main();` });APIS.push({ cat:'vision', sig:'findNotColor(colors, threshold?, x?, y?, ex?, ey?, limit?, direction?)', title:'区域找非色', desc:'在当前屏幕指定区域内查找所有"不匹配"给定颜色的点（用于检测画面变化、异色干扰），参数与 findColorEx 一致，找不到返回 null。', params:[['colors','string|array','颜色目标列表'],['threshold','number','0-1 相似度，默认 0.9'],['x','number','区域起点 X'],['y','number','区域起点 Y'],['ex','number','区域终点 X'],['ey','number','区域终点 Y'],['limit','number','最大返回点数，默认 10'],['direction','number','扫描方向 1-8，默认 1']], returns:'AutoPoint[] | null', example:`function main(){
  const points = findNotColor("0xFFFFFF-0x101010", 0.9, 0, 0, 0, 0, 10, 1);
  logd(JSON.stringify(points));
}
main();` });
APIS.push({ cat:'vision', sig:'image.clip(src, x, y, ex, ey, dest) / image.scale(src, width, height, dest) / image.gray(src, dest) / image.binaryzation(src, dest, threshold?) / image.rotate(src, degrees, dest)', title:'图像处理管线', desc:'路径式图像处理：clip 按区域裁剪，scale 缩放到指定宽高，gray 灰度化，binaryzation 二值化（threshold 0-255，默认 128），rotate 旋转 90 的倍数。坐标与尺寸沿用 image.getSize 的逻辑坐标空间；源文件受 maxFileReadBytes 限制，输出受 maxFileWriteBytes 限制，成功返回目标路径，失败返回 null。', params:[['src','string','源图片路径'],['dest','string','输出图片路径（.png/.jpg 决定编码）'],['x/y/ex/ey','number','裁剪区域（clip）'],['width/height','number','目标尺寸（scale）'],['threshold','number','二值化阈值（binaryzation）'],['degrees','number','旋转角度（rotate）']], returns:'string | null 目标路径', example:`function main(){
  const clipped = image.clip("shots/s.png", 0, 0, 390, 60, "shots/head.png");
  const scaled = image.scale("shots/s.png", 200, 400, "shots/small.png");
  const gray = image.gray("shots/s.png", "shots/gray.png");
  const bw = image.binaryzation("shots/s.png", "shots/bw.png", 128);
  const rotated = image.rotate("shots/s.png", 90, "shots/rot.png");
  logd(clipped, scaled, gray, bw, rotated);
}
main();` });
APIS.push({ cat:'vision', sig:'image.pixelAt(src, x, y) / image.getWidth(path) / image.getHeight(path)', title:'图像取色与尺寸', desc:'pixelAt 读取图片文件指定坐标（逻辑坐标）的颜色，返回 {r,g,b,a,hex}；getWidth/getHeight 是 file.imageSize 的简写，返回逻辑宽高。', params:[['src','string','图片路径'],['x/y','number','逻辑坐标']], returns:'object | number | null', example:`function main(){
  const color = image.pixelAt("shots/s.png", 100, 200);
  logd(color ? color.hex : "null");
  logd(image.getWidth("shots/s.png"), image.getHeight("shots/s.png"));
}
main();` });APIS.push({ cat:'vision', sig:'findMultiColor(color, offsets, region?, options?)', title:'多点找色', desc:'按基准色 + 相对偏移点组合查找，比单点更稳。', params:[['color','string','基准颜色'],['offsets','array','偏移点数组 [{dx,dy,color}]'],['region','object','可选'],['options','object','可选']], returns:'AutoMatch', example:`function main(){
  const match = findMultiColor("#3b3b3b", [
    {dx: 20, dy: 0, color: "#ffffff"},
    {dx: 0, dy: 20, color: "#000000"}
  ], {x: 0, y: 0, width: 390, height: 844}, {tolerance: 10});
  if (match.found) clickPoint(match.centerX, match.centerY);
}
main();` });
APIS.push({ cat:'vision', sig:'getPixelColor(x, y)', title:'读取像素颜色', desc:'读取截图上某一点的像素颜色。', params:[['x','number','横坐标'],['y','number','纵坐标']], returns:'AutoPixelColor {hex, r, g, b, a}', example:`function main(){
  const p = getPixelColor(100, 200);
  logd("颜色: " + p.hex);
}
main();` });
APIS.push({ cat:'vision', sig:'compareColors(points, options?)', title:'多点颜色比对', desc:'一次截图内比对多个点的颜色是否全部匹配。', params:[['points','array','[{x,y,color,tolerance?}]'],['options','object','可选']], returns:'boolean', example:`function main(){
  const ok = compareColors([
    {x: 10, y: 10, color: "#ffffff"},
    {x: 20, y: 20, color: "#000000"}
  ]);
  logd("比对结果: " + ok);
}
main();` });
APIS.push({ cat:'vision', sig:'cmpColor(points, options?)', title:'多点颜色比对（别名）', desc:'EasyClick 兼容别名，等价于 compareColors()。', params:[['points','array','颜色点数组'],['options','object','可选']], returns:'boolean', example:`function main(){
  const ok = cmpColor([{x: 5, y: 5, color: "#ff0000"}]);
  logd("结果: " + ok);
}
main();` });
APIS.push({ cat:'vision', sig:'ocr(options?)', title:'文字识别（OCR）', desc:'用设备端 Vision 识别屏幕文字，返回带坐标的文本项。', params:[['options','object','可选，{x,y,width,height,mode}']], returns:'AutoOCRItem[]', example:`function main(){
  const items = ocr({mode: "fast"});
  for (const item of items) {
    logd(item.text + " @ " + JSON.stringify(item.bounds));
  }
}
main();` });
APIS.push({ cat:'vision', sig:'image.findImage / findColor / pixel / screenshot', title:'图色模块别名', desc:'image 命名空间提供图色函数别名，便于移植。', params:[], returns:'同对应函数', example:`function main(){
  const png = image.screenshot();
  const m = image.findColor("#ffffff", {x: 0, y: 0, width: 100, height: 100});
  const p = image.pixel(10, 10);
  logd("截图长度=" + png.length + " 颜色点=" + m.found + " 像素=" + p.hex);
}
main();` });

APIS.push({ cat:'app', sig:'launchApp(bundleId)', title:'启动应用', desc:'通过支持生命周期能力的适配器启动 App。', params:[['bundleId','string','App 的 Bundle ID']], returns:'boolean', example:`function main(){
  const ok = launchApp("com.apple.Preferences");
  logd("启动: " + ok);
}
main();` });
APIS.push({ cat:'app', sig:'activateApp(bundleId)', title:'切换到前台', desc:'把已安装的 App 带到前台。', params:[['bundleId','string','Bundle ID']], returns:'boolean', example:`function main(){
  const ok = activateApp("com.apple.Preferences");
  logd("激活: " + ok);
}
main();` });
APIS.push({ cat:'app', sig:'terminateApp(bundleId)', title:'结束应用', desc:'结束指定 App 的进程。', params:[['bundleId','string','Bundle ID']], returns:'boolean', example:`function main(){
  const ok = terminateApp("com.example.demo");
  logd("结束: " + ok);
}
main();` });
APIS.push({ cat:'app', sig:'appState(bundleId)', title:'应用状态', desc:'读取 WDA 应用状态码（4 表示前台运行）。', params:[['bundleId','string','Bundle ID']], returns:'number', example:`function main(){
  const state = appState("com.apple.Preferences");
  logd("状态码: " + state);
}
main();` });
APIS.push({ cat:'app', sig:'openURL(url)', title:'打开链接', desc:'打开 http(s) 链接或安全的自定义 URL Scheme。', params:[['url','string','链接']], returns:'boolean', example:`function main(){
  const ok = openURL("myapp://open?id=42");
  logd("打开: " + ok);
}
main();` });
APIS.push({ cat:'app', sig:'app.homeScreen() / lock() / unlock()', title:'主屏幕 / 锁屏 / 解锁', desc:'WDA 适配器支持的系统级操作。', params:[], returns:'boolean', example:`function main(){
  logd("回主屏幕: " + app.homeScreen());
  logd("锁屏: " + app.lock());
  logd("解锁: " + app.unlock());
}
main();` });
APIS.push({ cat:'app', sig:'app.current() / currentApp()', title:'当前前台应用', desc:'返回当前前台 App 的 Bundle ID（WDA /wda/activeAppInfo）；宿主适配器不支持时返回错误。', params:[], returns:'string|null', example:`function main(){
  const current = app.current();
  logd("当前前台: " + current);
}
main();` });
APIS.push({ cat:'app', sig:'app.appList() / installedApps()', title:'已安装应用列表', desc:'返回已安装应用的 {bundleId, name} 数组（WDA /wda/apps）。支持宿主注入的适配器也可实现；不支持时返回错误。', params:[], returns:'Array<{bundleId, name}>', example:`function main(){
  const apps = app.appList();
  logd("已安装: " + apps.length + " 个应用");
  for (const item of apps.slice(0, 10)) logd(item.bundleId + " → " + item.name);
}
main();` });APIS.push({ cat:'app', sig:'launchAppByPrefix(bundleIdPrefix) / app.launchByPrefix(bundleIdPrefix)', title:'按前缀启动应用', desc:'先列出已安装应用，找到 bundleId 以指定前缀开头的第一个应用并启动；找不到返回 false。', params:[['bundleIdPrefix','string','Bundle ID 前缀，如 "com.apple.mobile"']], returns:'boolean', example:`function main(){
  const ok = launchAppByPrefix("com.apple.mobile");
  logd("启动结果: " + ok);
}
main();` });APIS.push({ cat:'device', sig:'device.getDeviceInfo()', title:'设备信息', desc:'返回设备/屏幕/电池/系统等完整信息字典。', params:[], returns:'object {model, systemVersion, screenWidth, batteryLevel, ...}', example:`function main(){
  const info = device.getDeviceInfo();
  logd("型号: " + info.model);
  logd("系统: " + info.systemVersion);
  logd("屏幕: " + info.screenWidth + "x" + info.screenHeight + " scale=" + info.scale);
  logd("电量: " + info.batteryLevel + " 充电中=" + info.isCharging);
}
main();` });
APIS.push({ cat:'device', sig:'device.getScreenWidth() / getScreenHeight()', title:'屏幕尺寸', desc:'读取屏幕逻辑宽高（点）。', params:[], returns:'number', example:`function main(){
  logd("宽: " + device.getScreenWidth());
  logd("高: " + device.getScreenHeight());
  logd("缩放: " + device.getScale());
}
main();` });
APIS.push({ cat:'device', sig:'device.getScreenWidthHeightText()', title:'屏幕宽高文本', desc:'EasyClick 兼容别名：返回 "宽x高" 字符串，如 "390x844"。', params:[], returns:'string', example:`function main(){
  logd("屏幕: " + device.getScreenWidthHeightText());
}
main();` });
APIS.push({ cat:'device', sig:'device.getScale()', title:'屏幕缩放', desc:'读取屏幕像素密度 scale。', params:[], returns:'number', example:`function main(){
  const s = device.getScale();
  logd("scale: " + s + " 物理宽: " + device.getScreenWidth() * s);
}
main();` });
APIS.push({ cat:'device', sig:'device.getModel() / getOSVersion() / getDeviceName()', title:'型号 / 系统 / 设备名', desc:'读取公开的 iOS 设备信息。', params:[], returns:'string', example:`function main(){
  logd(device.getModel() + " iOS " + device.getOSVersion());
  logd("设备名: " + device.getDeviceName());
}
main();` });
APIS.push({ cat:'device', sig:'device.getBattery() / isCharging()', title:'电量 / 充电状态', desc:'读取电量百分比与是否充电。', params:[], returns:'number|boolean', example:`function main(){
  const battery = device.getBattery();
  logd("电量: " + battery + "% 充电中: " + device.isCharging());
}
main();` });
APIS.push({ cat:'device', sig:'device.getOrientation()', title:'屏幕方向', desc:'读取当前界面方向。', params:[], returns:'string', example:`function main(){
  logd("方向: " + device.getOrientation());
}
main();` });
APIS.push({ cat:'device', sig:'device.getMemoryInfo()', title:'内存信息', desc:'读取进程可见的内存总量/空闲/已用（字节）。', params:[], returns:'object {totalBytes, freeBytes, appUsedBytes}', example:`function main(){
  const m = device.getMemoryInfo();
  logd("内存 总=" + m.totalBytes + " 空闲=" + m.freeBytes + " App=" + m.appUsedBytes);
}
main();` });
APIS.push({ cat:'device', sig:'device.getClipboard() / setClipboard(text)', title:'剪贴板', desc:'读取或写入系统剪贴板（文本上限 1 MiB）。', params:[['text','string','写入的文字（set 时）']], returns:'string|null / boolean', example:`function main(){
  const before = device.getClipboard();
  logd("原来: " + before);
  device.setClipboard("复制内容");
  logd("现在: " + device.getClipboard());
}
main();` });
APIS.push({ cat:'device', sig:'device.getBrightness() / setBrightness(v)', title:'屏幕亮度', desc:'读取或设置亮度（0~1）。', params:[['v','number','亮度 0~1（set 时）']], returns:'number / boolean', example:`function main(){
  logd("当前亮度: " + device.getBrightness());
  device.setBrightness(0.5);
  logd("设置后: " + device.getBrightness());
}
main();` });
APIS.push({ cat:'device', sig:'device.getVolume()', title:'系统音量', desc:'读取系统音量（0~1，只读）。', params:[], returns:'number', example:`function main(){
  logd("音量: " + device.getVolume());
}
main();` });
APIS.push({ cat:'device', sig:'device.vibrate(durationMs?)', title:'振动', desc:'触发系统振动（时长是建议值，系统会封顶）。', params:[['durationMs','number','可选，毫秒']], returns:'boolean', example:`function main(){
  device.vibrate(300);
  logd("已振动");
}
main();` });
APIS.push({ cat:'device', sig:'device.volumeUp() / device.volumeDown()', title:'音量加/减键', desc:'模拟按下系统音量加/减键（WDA 真机按键注入）；宿主适配器不支持时返回错误，可用 capabilities() 判断。', params:[], returns:'boolean', example:`function main(){
  const ok = device.volumeUp();
  logd("音量+ " + ok);
}
main();` });
APIS.push({ cat:'device', sig:'device.isScreenOn()', title:'屏幕状态', desc:'查询屏幕是否点亮（未锁屏），WDA 真机支持；宿主适配器不支持时返回错误。', params:[], returns:'boolean', example:`function main(){
  if (device.isScreenOn()) logd("屏幕已点亮");
  else logd("屏幕已熄灭");
}
main();` });APIS.push({ cat:'device', sig:'auto.capabilities()', title:'运行时能力', desc:'查看当前适配器与各模块开关状态，常用于脚本内判断。', params:[], returns:'object', example:`function main(){
  const cap = auto.capabilities();
  logd("HTTP: " + cap.http + " 文件: " + cap.fileRead + "/" + cap.fileWrite);
  logd("相册写入: " + cap.mediaLibraryWrite + " 系统控制: " + cap.systemControl);
  if (cap.http) logd("网络已启用");
}
main();` });
APIS.push({ cat:'file', sig:'file.sandboxDir()', title:'沙盒根目录', desc:'返回当前配置的 AutoSDK 文件沙盒绝对路径。', params:[], returns:'string', example:`function main(){
  logd("沙盒: " + file.sandboxDir());
}
main();` });
APIS.push({ cat:'file', sig:'file.resolvePath(path)', title:'解析沙盒路径', desc:'把相对路径拼接成沙盒内绝对路径。', params:[['path','string','相对路径，如 data/1.txt']], returns:'string', example:`function main(){
  logd(file.resolvePath("data/1.txt"));
}
main();` });
APIS.push({ cat:'file', sig:'file.exists(path)', title:'是否存在', desc:'判断文件或文件夹是否存在。', params:[['path','string','路径']], returns:'boolean', example:`function main(){
  logd("存在: " + file.exists("data/1.txt"));
}
main();` });
APIS.push({ cat:'file', sig:'file.readFile(path)', title:'读取文本', desc:'把沙盒文件读取为 UTF-8 字符串（别名 readText）。', params:[['path','string','路径']], returns:'string', example:`function main(){
  if (file.exists("data/1.txt")) {
    logd(file.readFile("data/1.txt"));
  } else {
    logd("文件不存在");
  }
}
main();` });
APIS.push({ cat:'file', sig:'file.readBase64(path)', title:'读取为 Base64', desc:'读取文件并以 Base64 字符串返回（可用于图片等二进制）。', params:[['path','string','路径']], returns:'string', example:`function main(){
  const b64 = file.readBase64("images/1.png");
  logd("长度: " + b64.length);
}
main();` });
APIS.push({ cat:'file', sig:'file.writeFile(path, text)', title:'写入文本', desc:'原子写入 UTF-8 文本（覆盖，别名 writeText）。', params:[['path','string','路径'],['text','string','内容']], returns:'boolean', example:`function main(){
  const ok = file.writeFile("data/1.txt", "hello\nworld");
  logd("写入: " + ok);
}
main();` });
APIS.push({ cat:'file', sig:'file.writeBase64(path, base64)', title:'写入 Base64', desc:'把 Base64 解码后写入文件。', params:[['path','string','路径'],['base64','string','Base64 内容']], returns:'boolean', example:`function main(){
  const png = screenshot();
  const ok = file.writeBase64("shots/now.png", png);
  logd("保存截图: " + ok);
}
main();` });
APIS.push({ cat:'file', sig:'file.appendText(path, text)', title:'追加文本', desc:'在文件末尾追加文本（不换行）。', params:[['path','string','路径'],['text','string','内容']], returns:'boolean', example:`function main(){
  file.appendText("data/log.txt", "start ");
  file.appendLine("data/log.txt", "done");
}
main();` });
APIS.push({ cat:'file', sig:'file.appendLine(path, line)', title:'追加一行', desc:'在文件末尾追加一行（自动换行）。', params:[['path','string','路径'],['line','string','行内容']], returns:'boolean', example:`function main(){
  for (let i = 0; i < 3; i++) file.appendLine("data/log.txt", "第" + i + "行");
}
main();` });
APIS.push({ cat:'file', sig:'file.writeLines(path, lines)', title:'写入多行', desc:'把字符串数组按行写入文件。', params:[['path','string','路径'],['lines','array','行数组']], returns:'boolean', example:`function main(){
  file.writeLines("data/points.txt", ["1,2", "3,4", "5,6"]);
}
main();` });
APIS.push({ cat:'file', sig:'file.readLines(path)', title:'读取所有行', desc:'把文件按行读取为数组（别名 readAllLines）。', params:[['path','string','路径']], returns:'string[]', example:`function main(){
  const lines = file.readLines("data/points.txt");
  for (const line of lines) logd(line);
}
main();` });
APIS.push({ cat:'file', sig:'file.readLine(path, index)', title:'读取某一行', desc:'按下标读取一行（从 0 开始），越界返回 null。', params:[['path','string','路径'],['index','number','行下标']], returns:'string|null', example:`function main(){
  const line = file.readLine("data/points.txt", 0);
  logd("第一行: " + line);
}
main();` });
APIS.push({ cat:'file', sig:'file.imageSize(path)', title:'图片尺寸', desc:'读取图片文件的逻辑宽高（点）、像素宽高与 scale。', params:[['path','string','图片路径（png/jpg 等）']], returns:'object {width, height, pixelWidth, pixelHeight, scale}', example:`function main(){
  const size = file.imageSize("images/banner.png");
  logd("宽: " + size.width + " 高: " + size.height + " 像素: " + size.pixelWidth + "x" + size.pixelHeight);
}
main();` });
APIS.push({ cat:'file', sig:'file.md5(path) / file.md5File(path) / file.sha1(path) / file.sha1File(path)', title:'文件哈希', desc:'计算沙盒文件的 MD5 或 SHA1 十六进制摘要（受 maxFileReadBytes 限制）。', params:[['path','string','文件路径']], returns:'string', example:`function main(){
  const md5 = file.md5("data/payload.json");
  logd("文件 md5: " + md5);
}
main();` });APIS.push({ cat:'file', sig:'file.deleteLine(path, index)', title:'删除某一行', desc:'删除指定下标的一行。', params:[['path','string','路径'],['index','number','行下标']], returns:'boolean', example:`function main(){
  const ok = file.deleteLine("data/points.txt", 0);
  logd("删除: " + ok);
}
main();` });
APIS.push({ cat:'file', sig:'file.create(path)', title:'创建文件', desc:'创建空文件（已存在则清空）。', params:[['path','string','路径']], returns:'boolean', example:`function main(){
  const ok = file.create("data/new.txt");
  logd("创建: " + ok);
}
main();` });
APIS.push({ cat:'file', sig:'file.mkdir(path) / mkdirs(path)', title:'创建文件夹', desc:'递归创建目录（可多级）。', params:[['path','string','目录路径']], returns:'boolean', example:`function main(){
  const ok = file.mkdirs("a/b/c");
  logd("创建目录: " + ok);
}
main();` });
APIS.push({ cat:'file', sig:'file.list(path)', title:'列出目录详情', desc:'返回目录项数组（名字、大小、是否目录、修改时间）。', params:[['path','string','目录路径，可空=沙盒根']], returns:'AutoFileEntry[]', example:`function main(){
  const entries = file.list("");
  for (const e of entries) {
    logd((e.isDirectory ? "[目录] " : "[文件] ") + e.name + " " + e.size);
  }
}
main();` });
APIS.push({ cat:'file', sig:'file.listDir(path)', title:'列出文件名', desc:'只返回目录下的名字数组（EasyClick 风格）。', params:[['path','string','目录路径']], returns:'string[]', example:`function main(){
  const names = file.listDir("data");
  logd(names.join(", "));
}
main();` });
APIS.push({ cat:'file', sig:'file.remove(path) / deleteAllFile(path)', title:'删除', desc:'删除文件或目录（含递归目录树，别名 deleteAllFile）。', params:[['path','string','路径']], returns:'boolean', example:`function main(){
  file.writeFile("tmp.txt", "x");
  const ok = file.deleteAllFile("tmp.txt");
  logd("删除: " + ok);
}
main();` });
APIS.push({ cat:'file', sig:'file.copy(src, dest, overwrite?)', title:'复制', desc:'复制文件或目录，overwrite 控制是否覆盖。', params:[['src','string','源路径'],['dest','string','目标路径'],['overwrite','boolean','可选，默认 false']], returns:'boolean', example:`function main(){
  const ok = file.copy("data/1.txt", "data/1-copy.txt", true);
  logd("复制: " + ok);
}
main();` });
APIS.push({ cat:'file', sig:'file.move(src, dest, overwrite?)', title:'移动', desc:'移动文件或目录（跨目录改名）。', params:[['src','string','源路径'],['dest','string','目标路径'],['overwrite','boolean','可选']], returns:'boolean', example:`function main(){
  const ok = file.move("data/1.txt", "data/archive/1.txt", false);
  logd("移动: " + ok);
}
main();` });
APIS.push({ cat:'file', sig:'file.rename(path, newName)', title:'重命名', desc:'把文件/目录改成新名字（同一目录内）。', params:[['path','string','原路径'],['newName','string','新名字']], returns:'boolean', example:`function main(){
  const ok = file.rename("data/1.txt", "renamed.txt");
  logd("重命名: " + ok);
}
main();` });

APIS.push({ cat:'file', sig:'file.zip(dest, sources, passwd?)', title:'?? ZIP', desc:'???/??????? ZIP???????passwd ???????????????', params:[['dest','string','?? zip ??'],['sources','string[]','??????/??????'],['passwd','string','????????']], returns:'string', example:`function main(){
  const zipPath = file.zip("backup/scripts.zip", ["data/1.txt", "logs"]);
  logd("????: " + zipPath);
}
main();` });
APIS.push({ cat:'file', sig:'file.unzip(zipPath, dest, passwd?)', title:'?? ZIP', desc:'? ZIP ??????????????????????????????', params:[['zipPath','string','zip ??'],['dest','string','??????'],['passwd','string','????????']], returns:'boolean', example:`function main(){
  const ok = file.unzip("backup/scripts.zip", "backup/out");
  logd("??: " + ok);
}
main();` });
APIS.push({ cat:'file', sig:'file.readFileInZip(zipPath, entry, passwd?)', title:'?? ZIP ???', desc:'?????????? zip ??????UTF-8 ????????????? Base64????? null?', params:[['zipPath','string','zip ??'],['entry','string','????? data/1.txt'],['passwd','string','????????']], returns:'string|null', example:`function main(){
  const text = file.readFileInZip("backup/scripts.zip", "data/1.txt");
  logd(text);
}
main();` });
APIS.push({ cat:'file', sig:'file.readExcelAllRow(path, sheetIndex?)', title:'?? Excel ????', desc:'?? xlsx??? ZIP+XML ???? UTF-8 CSV???????????????????????????????????????', params:[['path','string','xlsx ? csv ??'],['sheetIndex','number','????????? 0 ????? 0?CSV ???']], returns:'Array<object>', example:`function main(){
  const rows = file.readExcelAllRow("data/books.xlsx");
  for (const r of rows) logd(r.name, r.age);
}
main();` });
APIS.push({ cat:'file', sig:'file.readExcelRow(path, sheetIndex?, row?)', title:'?? Excel ??', desc:'???????? row ??0 ?????????????? null?', params:[['path','string','xlsx ? csv ??'],['sheetIndex','number','????? 0'],['row','number','??? 0 ??']], returns:'Array<string|number>|null', example:`function main(){
  const cells = file.readExcelRow("data/books.xlsx", 0, 2);
  logd(JSON.stringify(cells));
}
main();` });
APIS.push({ cat:'file', sig:'file.stat(path) / getSize / getModifiedTime / isDir / isFile', title:'文件状态查询', desc:'查询文件大小（字节）、修改时间（毫秒时间戳）、是否为目录/文件；路径不存在时 stat 返回 null。', params:[['path','string','路径']], returns:'object|null / number|null / boolean', example:`function main(){
  const s = file.stat("data/a.txt");
  if (s) logd("大小: " + s.size + " 修改: " + s.modifiedAtMs);
  logd("是目录: " + file.isDir("data"));
}
main();` });
APIS.push({ cat:'storage', sig:'storages.create(name)', title:'创建命名存储', desc:'打开一个命名 JSON 存储（不存在则创建），返回存储对象。', params:[['name','string','存储名']], returns:'AutoStorage', example:`function main(){
  const store = storages.create("settings");
  store.putString("endpoint", "https://example.com");
  logd("读取: " + store.getString("endpoint"));
}
main();` });
APIS.push({ cat:'storage', sig:'store.putString / putInt / putFloat / putBoolean(key, value)', title:'写入数据', desc:'按类型写入键值（JSON 安全）。', params:[['key','string','键'],['value','any','值']], returns:'boolean', example:`function main(){
  const s = storages.create("settings");
  s.putString("name", "demo");
  s.putInt("count", 10);
  s.putBoolean("enabled", true);
  s.putFloat("ratio", 0.5);
  logd("写入完成");
}
main();` });
APIS.push({ cat:'storage', sig:'store.getString / getInt / getFloat / getBoolean(key, default?)', title:'读取数据', desc:'按类型读取，可给默认值；不存在返回 null/默认值。', params:[['key','string','键'],['default','any','可选默认值']], returns:'any', example:`function main(){
  const s = storages.create("settings");
  logd(s.getString("name", "未设置"));
  logd(s.getInt("count", 0));
  logd(s.getBoolean("enabled", false));
}
main();` });
APIS.push({ cat:'storage', sig:'store.all() / keys()', title:'列出数据', desc:'返回全部键值或全部键名。', params:[], returns:'object | string[]', example:`function main(){
  const s = storages.create("settings");
  logd("键: " + JSON.stringify(s.keys()));
  logd("全部: " + JSON.stringify(s.all()));
}
main();` });
APIS.push({ cat:'storage', sig:'store.contains(key) / remove(key) / clear()', title:'判断 / 删除 / 清空', desc:'判断键是否存在、删除单个键、清空整个存储。', params:[['key','string','键']], returns:'boolean', example:`function main(){
  const s = storages.create("settings");
  logd("存在: " + s.contains("name"));
  s.remove("name");
  s.clear();
  logd("已清空");
}
main();` });
APIS.push({ cat:'http', sig:'http.get(url, options?)', title:'GET 请求', desc:'发送同步 GET 请求（需宿主配置 allowNetwork）。', params:[['url','string','http(s) 地址'],['options','object','可选，headers/timeout 等']], returns:'AutoHTTPResponse {status, body, json, headers}', example:`function main(){
  const cap = auto.capabilities();
  if (!cap.http) { loge("网络未启用，需要 allowNetwork=YES"); return; }
  const res = http.get("https://example.com/api");
  logd("状态: " + res.status);
  logd("响应: " + res.body);
}
main();` });
APIS.push({ cat:'http', sig:'http.post(url, body?, options?)', title:'POST 请求', desc:'发送同步 POST 请求（body 可为字符串或对象）。', params:[['url','string','地址'],['body','any','可选请求体'],['options','object','可选']], returns:'AutoHTTPResponse', example:`function main(){
  if (!auto.capabilities().http) { loge("网络未启用"); return; }
  const res = http.post("https://example.com/api", {a: 1}, {headers: {"Content-Type": "application/json"}});
  logd("状态: " + res.status + " 内容: " + res.body);
}
main();` });
APIS.push({ cat:'http', sig:'http.postJSON(url, body?, options?)', title:'JSON POST（别名）', desc:'EasyClick 兼容别名，等价于 http.post。', params:[['url','string','地址'],['body','any','对象'],['options','object','可选']], returns:'AutoHTTPResponse', example:`function main(){
  if (!auto.capabilities().http) return;
  const res = http.postJSON("https://example.com/api", {name: "demo"});
  logd(res.status);
}
main();` });
APIS.push({ cat:'http', sig:'http.downloadFile(url, path, options?)', title:'下载文件', desc:'把响应下载到沙盒文件；requireSuccess 可要求 2xx。', params:[['url','string','地址'],['path','string','沙盒目标路径'],['options','object','可选']], returns:'boolean', example:`function main(){
  if (!auto.capabilities().http) return;
  const ok = http.downloadFile("https://example.com/a.png", "images/a.png", {requireSuccess: true});
  logd("下载: " + ok);
}
main();` });
APIS.push({ cat:'http', sig:'http.request(url, options?) / httpGet / httpPost', title:'通用请求与别名', desc:'http 本体可调用，另有 httpGet/httpPost/httpGetDefault/httpPostJSON/downloadFileDefault 等别名。', params:[['url','string','地址'],['options','object','method/headers/body 等']], returns:'AutoHTTPResponse', example:`function main(){
  if (!auto.capabilities().http) return;
  const res = http.request("https://example.com", {method: "GET", timeout: 5000});
  logd("状态: " + res.status);
}
main();` });

APIS.push({ cat:'media', sig:'media.saveImage(path)', title:'保存图片到相册', desc:'把沙盒内图片写入系统相册；首次调用会弹 iOS 授权。', params:[['path','string','沙盒内图片路径，png/jpg']], returns:'boolean', example:`function main(){
  const ok = media.saveImage("images/result.png");
  logd("保存图片: " + ok);
}
main();` });
APIS.push({ cat:'media', sig:'media.saveImageBase64(base64)', title:'Base64 图片存相册', desc:'直接把 Base64 图片写入相册，可配合截图。', params:[['base64','string','PNG/JPEG 的 Base64']], returns:'boolean', example:`function main(){
  const png = screenshot();
  const ok = media.saveImageBase64(png);
  logd("保存截图到相册: " + ok);
}
main();` });
APIS.push({ cat:'media', sig:'media.saveVideo(path)', title:'保存视频到相册', desc:'把沙盒内视频文件写入系统相册。', params:[['path','string','沙盒内视频路径']], returns:'boolean', example:`function main(){
  const ok = media.saveVideo("videos/record.mp4");
  logd("保存视频: " + ok);
}
main();` });
APIS.push({ cat:'media', sig:'media.saveScreenshot()', title:'截图存相册', desc:'截图并直接保存到相册（一步完成）。', params:[], returns:'boolean', example:`function main(){
  const ok = media.saveScreenshot();
  logd("截图已存相册: " + ok);
}
main();` });
APIS.push({ cat:'media', sig:'auto.saveImageToAlbum / image.saveToAlbum 等别名', title:'相册别名', desc:'saveImageToAlbum、saveImageBase64ToAlbum、saveVideoToAlbum、saveScreenshotToAlbum 全局可用；image 模块另有 saveToAlbum/saveBase64ToAlbum/saveScreenshotToAlbum。', params:[], returns:'同对应函数', example:`function main(){
  const ok = saveScreenshotToAlbum();
  logd("别名调用: " + ok);
}
main();` });

APIS.push({ cat:'timer', sig:'setTimeout(fn, ms, ...args) / clearTimeout(id)', title:'延时执行', desc:'延时后执行一次回调；脚本结束前会排空定时器。', params:[['fn','function','回调'],['ms','number','毫秒'],['id','number','定时器 id']], returns:'number / void', example:`function main(){
  const id = setTimeout(() => { logd("延时执行"); }, 500);
  clearTimeout(id);
  logd("已取消");
}
main();` });
APIS.push({ cat:'timer', sig:'setInterval(fn, ms) / clearInterval(id)', title:'定时循环', desc:'周期性执行回调，可取消；脚本停止时自动清空。', params:[['fn','function','回调'],['ms','number','间隔毫秒'],['id','number','定时器 id']], returns:'number / void', example:`function main(){
  let count = 0;
  const id = setInterval(() => {
    count++;
    logd("第 " + count + " 次");
    if (count >= 3) clearInterval(id);
  }, 200);
}
main();` });
APIS.push({ cat:'timer', sig:'cancelTimeout(id) / cancelInterval(id)', title:'取消定时器（别名）', desc:'EasyClick 兼容别名。', params:[['id','number','定时器 id']], returns:'void', example:`function main(){
  const id = setTimeout(() => logd("不会执行"), 100);
  cancelTimeout(id);
}
main();` });
APIS.push({ cat:'timer', sig:'time() / random(min, max) / randomInt(min, max)', title:'时间与随机数', desc:'time 返回毫秒时间戳；random/randomInt 返回闭区间随机整数，只传一个参数时按 random(0, max) 处理。', params:[['min','number','可选，最小值，默认 0'],['max','number','最大值']], returns:'number', example:`function main(){
  logd("时间: " + time());
  logd("随机 1~6: " + randomInt(1, 6));
}
main();` });
APIS.push({ cat:'timer', sig:'console.time(label) / console.timeEnd(label)', title:'计时', desc:'console 风格计时，timeEnd 打印并返回耗时毫秒。', params:[['label','string','可选标签']], returns:'number|null', example:`function main(){
  console.time("run");
  sleep(200);
  const ms = console.timeEnd("run");
  logd("耗时: " + ms + "ms");
}
main();` });

APIS.push({ cat:'metrics', sig:'setScreenMetrics(width, height)', title:'设置设计分辨率', desc:'按设计稿宽高设置坐标基准（EasyClick/AutoJS 同款），之后用 metrics.point 把设计坐标换算为真机坐标；设置时固定一次真机尺寸，坐标换算不再每次查询设备，旋转屏幕后请重新调用；未设置时按 1:1。', params:[['width','number','设计稿宽度（px）'],['height','number','设计稿高度（px）']], returns:'boolean 是否设置成功', example:`function main(){
  const ok = setScreenMetrics(390, 844);
  logd("已设置设计分辨率: " + ok);
  const m = getScreenMetrics();
  logd("缩放比例: " + m.scaleX.toFixed(2) + "x" + m.scaleY.toFixed(2));
}
main();` });
APIS.push({ cat:'metrics', sig:'getScreenMetrics()', title:'获取屏幕与缩放信息', desc:'返回设计分辨率、真机分辨率与 X/Y 缩放比例；未调用 setScreenMetrics 时按 1:1。', params:[], returns:'{width,height,screenWidth,screenHeight,scaleX,scaleY}', example:`function main(){
  setScreenMetrics(390, 844);
  const m = getScreenMetrics();
  logd("真机: " + m.screenWidth + "x" + m.screenHeight);
  logd("缩放: " + m.scaleX + "x" + m.scaleY);
}
main();` });
APIS.push({ cat:'metrics', sig:'metrics.point(x, y) / metrics.x(v) / metrics.y(v)', title:'设计坐标转真机坐标', desc:'把设计稿坐标换算成当前真机坐标，适合多机型分辨率适配；也可直接读取 device.width/height/scale。', params:[['x','number','设计横坐标'],['y','number','设计纵坐标'],['v','number','设计值']], returns:'{x,y} 或 number', example:`function main(){
  setScreenMetrics(390, 844);
  const p = metrics.point(195, 100);
  logd("真机坐标: " + p.x + "," + p.y);
  logd("真机X: " + metrics.x(195));
}
main();` });
APIS.push({ cat:'metrics', sig:'device.width / device.height / device.scale', title:'设备尺寸快捷属性', desc:'等效 device.getScreenWidth()/getScreenHeight()/getScale() 的函数式属性。', params:[], returns:'number', example:`function main(){
  logd("宽: " + device.width() + " 高: " + device.height() + " 缩放: " + device.scale());
}
main();` });

APIS.push({ cat:'touch', sig:'auto.getChild(selector, index)', title:'取第 N 个子节点', desc:'返回父节点的第 index 个子节点（从 0 开始），越界返回 null。', params:[['selector','object|string','父节点选择器'],['index','number','子节点索引']], returns:'object|null', example:`function main(){
  const parent = findElement({text: "列表"});
  const first = auto.getChild(parent, 0);
  logd("第一个子节点: " + (first ? JSON.stringify(first) : "null"));
}
main();` });
APIS.push({ cat:'touch', sig:'auto.getSiblings(selector) / getPreviousSiblings / getNextSiblings', title:'兄弟节点', desc:'getSiblings 返回全部兄弟；getPreviousSiblings/getNextSiblings 按文档顺序返回之前/之后的兄弟节点。', params:[['selector','object|string','节点']], returns:'object[]', example:`function main(){
  const node = findElement({text: "当前项"});
  logd("兄弟数量: " + auto.getSiblings(node).length);
  logd("前序兄弟: " + auto.getPreviousSiblings(node).length);
}
main();` });
APIS.push({ cat:'touch', sig:'auto.clickCenter(selector)', title:'点击节点中心', desc:'读取节点 bounds 后点击其中心点，比坐标点击更稳。', params:[['selector','object|string','节点']], returns:'boolean', example:`function main(){
  const ok = auto.clickCenter({text: "登录"});
  logd("点击中心: " + ok);
}
main();` });
APIS.push({ cat:'touch', sig:'auto.clickRandom(selector)', title:'随机点点击', desc:'在节点范围内随机取点点击，模拟真人操作、降低被风控识别概率；坐标已取整。', params:[['selector','object|string','节点']], returns:'boolean', example:`function main(){
  const ok = auto.clickRandom({text: "开始"});
  logd("随机点击: " + ok);
}
main();` });
APIS.push({ cat:'touch', sig:'swipeToPoint(x1, y1, x2, y2, duration?)', title:'滑动（别名）', desc:'swipe 的兼容别名，行为完全一致。', params:[['x1','number','起点X'],['y1','number','起点Y'],['x2','number','终点X'],['y2','number','终点Y'],['duration','number','毫秒']], returns:'boolean', example:`function main(){
  const ok = swipeToPoint(200, 600, 200, 200, 300);
  logd("滑动: " + ok);
}
main();` });

APIS.push({ cat:'device', sig:'device.getDeviceId()', title:'??????', desc:'??????????identifierForVendor???????????????????????', params:[], returns:'string', example:`function main(){
  logd("deviceId: " + device.getDeviceId());
}
main();` });
APIS.push({ cat:'device', sig:'device.getDeviceAlias() / getSerialNo()', title:'????/???', desc:'getDeviceAlias ???????getSerialNo ? iOS ????????????????? null?', params:[], returns:'string | null', example:`function main(){
  logd("alias: " + device.getDeviceAlias());
  logd("serial: " + device.getSerialNo());
}
main();` });
APIS.push({ cat:'app', sig:'app.getAppVersion() / getPackageName()', title:'??????/??', desc:'???? App ?????CFBundleShortVersionString?? bundle id??????? getAppVersion()/getPackageName()?', params:[], returns:'string', example:`function main(){
  logd("v" + getAppVersion() + " " + getPackageName());
}
main();` });
APIS.push({ cat:'http', sig:'http.getJSON(url, options?)', title:'GET 并解析 JSON', desc:'等价 http.get(url, {parseJson:true})，直接返回解析后的对象。', params:[['url','string','地址'],['options','object','可选 headers/timeout 等']], returns:'object|string|number', example:`function main(){
  const data = http.getJSON("https://api.example.com/v1/status");
  logd("status: " + JSON.stringify(data));
}
main();` });

APIS.push({ cat:'timer', sig:'uuid() / uniqueId()', title:'随机 UUID', desc:'返回随机 v4 UUID 字符串，可用于任务 ID、文件名等。', params:[], returns:'string', example:`function main(){
  const id = uuid();
  logd("任务ID: " + id);
}
main();` });
APIS.push({ cat:'timer', sig:'base64.encode(str) / base64.decode(str)', title:'Base64 编解码', desc:'UTF-8 安全的 Base64 编解码；可配合 http bodyBase64、media.saveImageBase64 使用。', params:[['str','string','文本或 Base64']], returns:'string', example:`function main(){
  const enc = base64.encode("你好 AutoSDK");
  logd("编码: " + enc);
  logd("解码: " + base64.decode(enc));
}
main();` });
writeFileSync(join(root, 'docs', 'api-reference.html'), render(), 'utf8');
console.log('Generated docs/api-reference.html with ' + APIS.length + ' functions.');
