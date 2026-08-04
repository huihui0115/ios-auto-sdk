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
  { id: 'file',     name: '文件', color: '#4f46e5' },
  { id: 'storage',  name: '存储', color: '#0d9488' },
  { id: 'http',     name: '网络HTTP', color: '#9333ea' },
  { id: 'media',    name: '相册媒体', color: '#db2777' },
  { id: 'timer',    name: '定时器与工具', color: '#64748b' }
];

function card(api) {
  const params = (api.params || []).map(([n, t, d]) =>
    `<div class="param"><code class="pname">${esc(n)}</code><span class="ptype">${esc(t)}</span><span class="pdesc">${esc(d)}</span></div>`).join('');
  return `<article class="card" data-search="${esc(api.sig + ' ' + api.title)}">
  <header class="card-head">
    <h4><code>${esc(api.sig)}</code> <span class="cname">${esc(api.title)}</span></h4>
    <button class="copy" data-copy>复制</button>
  </header>
  <p class="desc">${esc(api.desc)}</p>
  ${params ? `<div class="params"><b>参数</b>${params}</div>` : ''}
  <div class="ret"><b>返回值</b> <span>${esc(api.returns)}</span></div>
  <pre><code>${esc(api.example)}</code></pre>
</article>`;
}

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
<footer>AutoSDK 离线函数参考 · 与 EasyClick/AutoScript 风格对齐 · 双击 index.html 即可打开</footer>
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
APIS.push({ cat:'touch', sig:'swipe(x1, y1, x2, y2, duration?)', title:'滑动', desc:'从 (x1,y1) 滑动到 (x2,y2)，duration 为秒数。', params:[['x1','number','起点横坐标'],['y1','number','起点纵坐标'],['x2','number','终点横坐标'],['y2','number','终点纵坐标'],['duration','number','可选，秒数']], returns:'boolean', example:`function main(){
  const ok = swipe(190, 600, 190, 200, 0.4);
  logd("上滑: " + ok);
}
main();` });
APIS.push({ cat:'touch', sig:'input(selector, text)', title:'输入文字', desc:'向匹配的输入框填入文字（替换原内容）。', params:[['selector','object|string','输入框选择器'],['text','string','要输入的文字']], returns:'boolean', example:`function main(){
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
APIS.push({ cat:'vision', sig:'findImage(templatePath, options?)', title:'找图', desc:'在屏幕截图中查找模板图片，返回匹配位置与相似度。', params:[['templatePath','string','模板图片路径（沙盒内，支持 png/jpg）'],['options','object','可选，region/threshold 等']], returns:'AutoMatch {found, x, y, similarity}', example:`function main(){
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
APIS.push({ cat:'vision', sig:'findMultiColor(color, offsets, region?, options?)', title:'多点找色', desc:'按基准色 + 相对偏移点组合查找，比单点更稳。', params:[['color','string','基准颜色'],['offsets','array','偏移点数组 [{dx,dy,color}]'],['region','object','可选'],['options','object','可选']], returns:'AutoMatch', example:`function main(){
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
APIS.push({ cat:'device', sig:'device.getDeviceInfo()', title:'设备信息', desc:'返回设备/屏幕/电池/系统等完整信息字典。', params:[], returns:'object {model, systemVersion, screenWidth, batteryLevel, ...}', example:`function main(){
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
APIS.push({ cat:'device', sig:'auto.capabilities()', title:'运行时能力', desc:'查看当前适配器与各模块开关状态，常用于脚本内判断。', params:[], returns:'object', example:`function main(){
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
APIS.push({ cat:'file', sig:'file.deleteLine(path, index)', title:'删除某一行', desc:'删除指定下标的一行。', params:[['path','string','路径'],['index','number','行下标']], returns:'boolean', example:`function main(){
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
APIS.push({ cat:'timer', sig:'time() / random(min, max) / randomInt(min, max)', title:'时间与随机数', desc:'time 返回毫秒时间戳；random/randomInt 返回闭区间随机整数。', params:[['min','number','最小值'],['max','number','最大值']], returns:'number', example:`function main(){
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

writeFileSync(join(root, 'docs', 'api-reference.html'), render(), 'utf8');
console.log('Generated docs/api-reference.html with ' + APIS.length + ' functions.');
