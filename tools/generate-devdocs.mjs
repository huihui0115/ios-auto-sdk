// Generates docs/devdocs/index.html — an AScript/Docusaurus-style docs site
// (sidebar tree + prose topic pages + per-function pages with copyable examples
// and debug hints). Single offline file, no external dependencies.
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { APIS, CATEGORIES } from './generate-api-reference.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const DEBUG_HINTS = {
  logs: 'VS Code「Run Current Script」直接看日志面板；toast 会在设备屏幕弹浮层，不连电脑也能确认执行。',
  touch: '先在 VS Code 控件查找器（Visual Inspector）里「测试选择器」确认定位，再粘回脚本；跨 App 点击前用 auto.capabilities() 确认 realTouchInjection 为 true。',
  vision: 'Inspector 的找图/OCR 模式可先用本地 PNG 离线测试；真机用 screenshotRegion 保存截图核对区域是否框对。',
  app: '用 auto.capabilities() 确认 appLifecycle/systemActions/appList；launch 后用 app.current() 轮询等待前台切换。',
  device: '设备信息在宿主 App 内即可读取；音量键/锁屏等系统动作以 capabilities 报告为准（内置 no-WDA 适配器按运行时能力如实降级）。',
  metrics: 'setScreenMetrics 后用 metrics.point(x,y) 把设计稿坐标换算成设备坐标，适配不同机型。',
  file: '所有路径限制在沙盒根内；file.sandboxDir() 查看当前根目录；deleteAllFile 会递归清空目录，慎用。',
  storage: 'storages 按名字隔离命名空间；clear() 只清当前命名空间；getInt/getBoolean 带默认值兜底。',
  http: 'HTTP 默认关闭，需宿主配置 allowHTTP + 域名 allowlist；先用 http.get 小请求验证连通性再写业务。',
  media: '首次保存相册会触发 iOS 授权弹窗；deleteAllPhotos 等需要读写权限并返回删除条数，先在测试机验证。',
  timer: 'sleep 是一次性原生等待不占 JS 时间片；execAsync 返回线程对象，用 cancelThread/stopAllThreads 取消。',
  strings: '纯 JS 函数，直接 console.log 返回值即可验证；toPinYin/fromUnicode 等注意输入类型。',
  ui: '悬浮窗显示在宿主屏幕上层；不连电脑调试时用 floatLog 实时看日志最方便。',
  speech: '朗读是异步的，脚本里朗读后要 sleep 等待，否则脚本结束会停止朗读（可用 stopWhenScriptEnd 控制）。'
};

const PROSE = [
{ id: 'intro', group: '开始', title: '介绍', html: `
<h1>AutoSDK 介绍</h1>
<p>AutoSDK 是嵌入式 <b>iOS JavaScript 自动化引擎</b>：宿主 App 内嵌 JavaScriptCore，加载内置 bootstrap，
把 <b>258 个脚本函数</b>（触摸、控件、图色、OCR、YOLO、文件、存储、HTTP、SQLite、线程、定位、相册、悬浮窗、TTS…）
交给 JS 脚本，通过 bridge 调原生能力。对标 EasyClick iOS / AScript iOS / TrollAutoScript / kuaijs。</p>
<div class="note ok"><b>内置 no-WDA（v1.17.0+ 唯一跨 App 路线）</b>：不再依赖外部 WebDriverAgent Runner。
<code>AutoBuiltinAdapter</code> 用 IOHIDEvent 注入真实触摸、AXUIElement 系统级控件检索（毫秒级）、
SpringBoard/LSApplicationWorkspace 控制应用，全部私有符号运行时 dlopen/dlsym 解析、不链接私有框架，
能力缺失时 <code>auto.capabilities()</code> 如实降级报告。</div>
<h2>与同类产品对比</h2>
<table><tr><th>维度</th><th>AScript iOS</th><th>EasyClick iOS</th><th>AutoSDK</th></tr>
<tr><td>脚本语言</td><td>Python</td><td>JS（控制器侧）</td><td>JavaScript（设备内 JSCore）</td></tr>
<tr><td>跨 App 触摸</td><td>Agent no-WDA / ESP32 HID</td><td>需代理 IPA / WDA</td><td>内置 IOHIDEvent 注入（no-WDA）</td></tr>
<tr><td>控件检索</td><td>毫秒级 Agent 通道</td><td>WDA dump</td><td>系统级 AX 遍历（毫秒级）</td></tr>
<tr><td>OCR</td><td>PaddleOCR/Vision/MLKit</td><td>多引擎</td><td>Apple Vision 离线 + 百度 OCR 可选</td></tr>
<tr><td>YOLO</td><td>NCNN 自训模型</td><td>—</td><td>Vision 离线检测（yolo.detect）</td></tr>
<tr><td>开发体验</td><td>VS Code/Cursor + 云</td><td>PC 控制器</td><td>VS Code 扩展：Run/Send/Inspector/日志</td></tr>
<tr><td>签名要求</td><td>特签分发</td><td>代理签</td><td>宿主内免费签可用；跨 App 需特签（TrollStore/企业签）</td></tr></table>
<h2>怎么用这份文档</h2>
<ol><li><a href="#/install">安装与签名</a> 把模板 App 装到手机；</li>
<li><a href="#/connect">连接与调试</a> 接上 VS Code；</li>
<li><a href="#/first-script">第一行代码</a> 跑通 hello world；</li>
<li>左侧「API 参考」按分类查函数，每个函数都带<b>一键复制</b>的可运行示例和<b>调试提示</b>。</li></ol>` },
{ id: 'install', group: '开始', title: '安装与签名', html: `
<h1>安装与签名</h1>
<h2>路线 A：Xcode 直接构建（开发者）</h2>
<p>克隆仓库 → 用 CocoaPods 引入 <code>AutoSDK.podspec</code>（或把 <code>Sources/AutoSDK</code> 拖进工程）→
参考 <code>Examples/TemplateApp</code> 接线：<code>[AutoTemplateSettings applyEngineConfiguration]</code> 一行完成引擎+适配器配置。</p>
<h2>路线 B：GitHub Actions 出 unsigned IPA + Apple ID 免费签（免越狱）</h2>
<ol><li>推送提交触发 workflow，产出 <code>AutoSDKTemplate.ipa</code>；</li>
<li>Windows 侧用 AltStore/Sideloadly 等免费签名安装（7 天续签）；</li>
<li>此路线下<b>宿主 App 内自动化、图色、OCR、相册、文件、HTTP、悬浮窗全部可用</b>；
跨 App 系统级能力需要路线 C 的信任上下文。</li></ol>
<h2>路线 C：TrollStore / 企业签（跨 App 完整能力）</h2>
<p>内置 no-WDA 适配器的触摸注入与系统级 AX 依赖私有 API，需要允许私有 API 的构建
（TrollStore 或企业开发者证书）。App Store 正规分发请保持 <code>AutoSDKAdapter=UIKIT</code>（审核安全）。</p>
<h2>适配器选择（Info.plist / NSUserDefaults）</h2>
<table><tr><th>AutoSDKAdapter 值</th><th>适配器</th><th>范围</th></tr>
<tr><td>默认 / <code>BUILTIN</code></td><td>AutoBuiltinAdapter（内置 no-WDA）</td><td>全设备跨 App</td></tr>
<tr><td><code>UIKIT</code></td><td>AutoUIKitAdapter</td><td>仅宿主 App 视图（App Store 安全）</td></tr></table>
<p>可选键：<code>AutoSDKMaxSnapshotNodes</code>（默认 5000）、<code>AutoSDKMaxSnapshotDepth</code>（默认 30）、
<code>AutoSDKScreenshotCacheDuration</code>。App 设置页的「Built-in no-WDA adapter」开关即时切换。</p>
<div class="note warn">诚实说明：跨 App 能力在免费签环境下<b>不可用</b>，这是 iOS 平台红线，与 AScript/kuaijs 相同，均走特签分发。</div>` },
{ id: 'connect', group: '开始', title: '连接与调试', html: `
<h1>连接与调试（VS Code）</h1>
<h2>1. 装扩展</h2>
<p><code>vscode-extension/</code> 目录 F5 运行，或打包 vsix 安装。命令面板搜 <b>AutoSDK</b>。</p>
<h2>2. 拿 token</h2>
<p>App 设置页显示 <code>ws://地址:9001</code> 与安装 token（≥16 位）。Wi-Fi 开关默认开；
关闭则只允许 USB 回环：<code>iproxy 9001 9001</code> 后连 <code>ws://127.0.0.1:9001</code>。</p>
<h2>3. 常用命令</h2>
<table><tr><th>命令</th><th>作用</th></tr>
<tr><td>AutoSDK: Connect</td><td>输入 URL + token 建立 WebSocket</td></tr>
<tr><td>AutoSDK: Run Current Script</td><td>把当前打开的 JS/TS 直接推到手机执行（无需重装 IPA）</td></tr>
<tr><td>AutoSDK: Send Current Script to Device</td><td>存进 App 沙盒（部署脚本列表）</td></tr>
<tr><td>AutoSDK: Manage Device Scripts</td><td>列出/运行/删除已部署脚本</td></tr>
<tr><td>AutoSDK: Open Visual Inspector</td><td>控件查找器：左截图右节点树</td></tr></table>
<h2>4. 日志</h2>
<p>脚本里 <code>console.log/warn/error</code>、<code>toast/toastLog</code> 实时回传 VS Code 输出面板；
不连电脑时用 <code>floatLog</code> 悬浮日志窗在设备上看。</p>
<h2>5. 命令行调试</h2>
<pre><code>node tools/debug-client.mjs --token &lt;token&gt; --url ws://127.0.0.1:9001 --script-file .\\hello.js</code></pre>
<div class="note ok">调试提示：Wi-Fi 模式仅 token 认证未加密，只在可信网络使用；生产分发请关闭
<code>AutoSDKDebugAllowWiFi</code>。</div>` },
{ id: 'first-script', group: '开始', title: '第一行代码', html: `
<h1>第一行代码</h1>
<pre><code>function main() {
  console.log('hello, AutoSDK');          // VS Code 日志面板可见
  toast('脚本已运行');                      // 设备屏幕浮层
  const caps = auto.capabilities();        // 能力门控，先问再做
  console.log('crossApp =', caps.crossApp, 'touch =', caps.realTouchInjection);
  if (caps.click) clickPoint(500, 800);    // 坐标点击
  return 'done';
}
main();</code></pre>
<h2>运行步骤</h2>
<ol><li>VS Code 连接设备（见<a href="#/connect">连接与调试</a>）；</li>
<li>打开或新建 .js，命令面板 → <b>AutoSDK: Run Current Script</b>；</li>
<li>输出面板看 console 回传；设备上看到 toast 即成功。</li></ol>
<h2>常见错误速查</h2>
<table><tr><th>现象</th><th>原因 / 处理</th></tr>
<tr><td>capabilities.crossApp=false</td><td>当前是 UIKit 适配器或免费签环境；设置页开 Built-in no-WDA 且需特签构建</td></tr>
<tr><td>click 返回 false</td><td>触摸注入不可用（签名上下文不足），capabilities.realTouchInjection 会如实为 false</td></tr>
<tr><td>HTTP 报错 disabled</td><td>宿主未开 allowHTTP / 域名不在 allowlist</td></tr>
<tr><td>脚本超时</td><td>默认 300s；死循环纯 JS 目前协作式中断，sleep/原生调用可被打断</td></tr></table>` },
{ id: 'structure', group: '开始', title: '工程结构', html: `
<h1>工程结构（二次开发）</h1>
<pre><code>Sources/AutoSDK/            SDK 本体（CocoaPods 可直接引）
  AutoEngine.m              JS 桥接/调度/取消/调试入口
  AutoBuiltinAdapter.m      内置 no-WDA 适配器（IOHID/AX/SpringBoard 运行时解析）
  AutoUIKitAdapter.m        宿主 App 内公共 API 适配器
  AutoScriptSupport.m       文件沙盒/HTTP 安全/sqlite/yolo/HMAC
  AutoDebugServer.m         WebSocket 调试服务（VS Code 对接）
tools/bootstrap-source.js   bootstrap JS 唯一权威源（60KB 预算）
tools/generate-api-reference.mjs / generate-devdocs.mjs   文档生成器
types/autosdk.d.ts          TS 类型（VS Code 补全 + verify 闭环）
Examples/TemplateApp/       宿主模板 App（设置页/脚本示例/Info.plist）
vscode-extension/           VS Code 扩展（Run/Send/Inspector）
docs/                       本站 + 函数速查 + 教程 + 对标审计</code></pre>
<h2>加一个函数的闭环</h2>
<ol><li><code>tools/bootstrap-source.js</code> 定义并导出 → <code>npm run regenerate:bootstrap</code>；</li>
<li><code>types/autosdk.d.ts</code> 加声明；</li>
<li><code>tools/generate-api-reference.mjs</code> 加 APIS 卡片（sig 覆盖新名字，verify 强制）；</li>
<li><code>tools/bootstrap.test.mjs</code> 加行为测试；</li>
<li><code>npm run verify && npm test && npm run docs</code> 全绿后发版。</li></ol>` },
{ id: 'selector', group: '控件检索', title: '选择器快速上手', html: `
<h1>选择器快速上手</h1>
<p>所有节点 API 的选择器可以是字符串（按 label/text 精确匹配）或对象（字段 AND 组合）：</p>
<pre><code>auto.click({ id: "login", type: "Button" });          // 精确字段
auto.click({ textMatch: "^登\\\\s*录$" });                // 正则变体
const n = node.find({ label: "确认" }); if (n) n.click(); // Node 对象风格
Selector().label("确认").click().find(3000);            // AScript 链式风格</code></pre>
<h2>字段表</h2>
<table><tr><th>字段</th><th>含义</th><th>正则变体</th></tr>
<tr><td>id / label / name(text) / value / type</td><td>精确匹配</td><td>idMatch / labelMatch / textMatch / valueMatch / typeMatch</td></tr>
<tr><td>enabled / visible / selected / accessible</td><td>状态过滤</td><td>—</td></tr>
<tr><td>index / depth / childCount / bounds</td><td>结构过滤</td><td>—</td></tr></table>
<div class="note warn">内置 no-WDA 适配器暂不支持 <code>xpath</code>/<code>predicate</code>（返回清晰错误）；
用 text/label/id/type + Match 正则组合可覆盖绝大多数场景。先在<a href="#/inspector">控件查找器</a>里验证选择器再写进脚本。</div>` },
{ id: 'node-object', group: '控件检索', title: '控件对象', html: `
<h1>控件对象（Node）</h1>
<p><code>node.find(selector)</code> 返回带方法的 Node 对象，可链式操作：</p>
<pre><code>const n = node.find({ label: "用户名" });
if (n) {
  n.click();                 // 点击中心
  n.tap_hold(1.5);           // 长按 1.5 秒（秒为单位）
  n.setText("hello");        // 输入
  console.log(n.text, n.rect, n.boundsInfo());
  n.children().forEach(c => console.log(c.type, c.label));
  n.parent(); n.siblings(); n.allChildren();  // 关系遍历
}</code></pre>
<h2>常用方法</h2>
<table><tr><th>方法</th><th>说明</th></tr>
<tr><td>click() / click(dur) / tap_hold(sec) / longClick(sec)</td><td>激活节点（长按单位为秒）</td></tr>
<tr><td>setText(t) / clearText()（别名 set_text/clear_text）</td><td>输入/清空</td></tr>
<tr><td>attr(name) / .text / .rect / .center / .boundsInfo()</td><td>属性与坐标</td></tr>
<tr><td>children() / parent() / siblings() / nextSiblings() / previousSiblings() / allChildren()</td><td>关系遍历（返回包装节点）</td></tr>
<tr><td>keep() / unkeep()</td><td>保留句柄（对标 TrollAutoScript）</td></tr></table>` },
{ id: 'inspector', group: '控件检索', title: '控件查找器', html: `
<h1>控件查找器（Visual Inspector）</h1>
<ol><li>VS Code 命令面板 → <b>AutoSDK: Open Visual Inspector</b>；</li>
<li>左侧实时截图，右侧节点树；点节点高亮并<b>自动生成选择器代码</b>；</li>
<li>「测试选择器」立即在设备上执行验证；</li>
<li>找图/OCR 模式可先用本地 PNG 测试（自动上传到手机 debug-assets）；</li>
<li>生成的 <code>auto.click(...)</code> 直接粘回脚本。</li></ol>
<div class="note ok">工作流建议：Inspector 取选择器 → 本页面查函数示例 → Run Current Script 热跑 →
日志面板看回传，全程不用重装 IPA。</div>` },
{ id: 'guide-threads', group: '高级指南', title: '多线程', html: `
<h1>多线程</h1>
<p>脚本主体跑在 JSContext 主线程；耗时任务（HTTP、长循环、等待）用 <code>execAsync</code> 放到独立线程，
避免卡住触摸/控件操作。最多 8 个并发线程，线程函数参数必须是可 JSON 序列化的值。</p>
<pre><code>function main(){
  // 子线程跑耗时任务
  const t = execAsync(function (n) {
    sleep(2000);
    return n * 2;
  }, 21);

  // 主线程继续干活
  logd("子线程还没结束: " + !t.isFinished());
  const value = t.join();      // 阻塞等结果
  logd("结果: " + value);      // 42
  t.cancel();                  // 幂等，可随时调用
}
main();</code></pre>
<h2>定时器</h2>
<pre><code>function main(){
  setTimeout(function(){ logd("2 秒后执行一次"); }, 2000);
  const id = setInterval(function(){ logd("每 1 秒"); }, 1000);
  sleep(3500);
  clearInterval(id);
}
main();</code></pre>
<div class="note ok">经验：线程之间不要共享可变对象（每个线程是独立 JSContext），
用返回值/getResult 或存储（store/sqlite）传递数据。</div>` },

{ id: 'guide-db', group: '高级指南', title: '数据库', html: `
<h1>数据库（SQLite）</h1>
<p>内置 <code>sqlite</code> 模块（iOS 系统 libsqlite3），适合存任务队列、去重记录、运行统计。
参数用 <code>?</code> 占位绑定，天然防 SQL 注入。</p>
<pre><code>function main(){
  const db = sqlite.open("data/app.db");            // 沙盒内路径，自动建库
  sqlite.exec(db, "CREATE TABLE IF NOT EXISTS tasks(" +
    "id INTEGER PRIMARY KEY, name TEXT, done INTEGER DEFAULT 0)");
  const r = sqlite.exec(db, "INSERT INTO tasks(name) VALUES(?)", ["写周报"]);
  logd("新增 id=" + r.lastInsertRowId + " changes=" + r.changes);
  const rows = sqlite.query(db, "SELECT * FROM tasks WHERE done=?", [0]);
  for (const row of rows) logd(row.id + ": " + row.name);
  sqlite.close(db);                                 // 脚本停止时也会自动关闭
}
main();</code></pre>
<div class="note ok">大批量写入时把多条 INSERT 放进一个循环即可，单条语句都是同步执行、
无需事务封装；跨线程共享数据推荐用数据库而不是全局变量。</div>` },

{ id: 'guide-network', group: '高级指南', title: '网络通信', html: `
<h1>网络通信（HTTP）</h1>
<p><code>http</code> 模块支持 GET/POST/JSON/表单/文件下载，全局简写 <code>httpGet/httpPost</code>。
长请求建议放进 <code>execAsync</code> 线程，避免阻塞主流程。</p>
<pre><code>function main(){
  if (auto.capabilities().http !== true) { logd("宿主未开放 HTTP"); return; }
  // GET JSON
  const r = http.get("https://example.com/api/status", {
    headers: { "Authorization": "Bearer xxx" },
    timeout: 5000,
  });
  logd("status=" + r.status);
  const data = r.json;        // 已自动解析为对象
  // POST JSON
  const r2 = http.postJSON("https://example.com/api/report", { ok: true, ts: Date.now() });
  logd("上报: " + r2.status);
}
main();</code></pre>
<h2>下载文件</h2>
<pre><code>function main(){
  const ok = http.downloadFile("https://example.com/a.png", "res/a.png");
  logd("下载: " + ok);
}
main();</code></pre>
<div class="note ok">ATS 提示：宿主 App 若未放开 http:// 明文域名，请用 https；
请求失败时 r.status 为 0 且 body 为空，先判 status 再解析。</div>` },
];

function fnBlock(api, i) {
  const params = (api.params && api.params.length)
    ? `<table class="pt"><tr><th>参数</th><th>类型</th><th>说明</th></tr>${api.params.map(p => `<tr><td><code>${esc(p[0])}</code></td><td>${esc(p[1])}</td><td>${esc(p[2])}</td></tr>`).join('')}</table>`
    : '<p class="noparam">无参数</p>';
  const hint = DEBUG_HINTS[api.cat] || '';
  return `<section class="fn" id="fn-${i}">
<h3>${esc(api.title)}</h3>
<div class="sig"><code>${esc(api.sig)}</code><button class="copy" data-copy="sig-${i}">复制</button></div>
<p class="desc">${esc(api.desc)}</p>
${params}
<div class="ret"><b>返回值</b> <code>${esc(api.returns)}</code></div>
<div class="exhead"><span>示例（可直接复制运行）</span><button class="copy" data-copy="ex-${i}">复制</button></div>
<pre id="ex-${i}"><code>${esc(api.example)}</code></pre>
<pre id="sig-${i}" class="hidden">${esc(api.sig)}</pre>
${hint ? `<div class="hintbox">🔧 调试：${esc(hint)}</div>` : ''}
</section>`;
}

const catPages = CATEGORIES.filter(c => c.id !== 'start').map(c => {
  const items = APIS.map((a, i) => ({ a, i })).filter(x => x.a.cat === c.id);
  return { id: 'cat-' + c.id, group: 'API 参考', title: c.name, count: items.length,
    html: `<h1>${esc(c.name)}<span class="cnt">${items.length}</span></h1>` +
      (items.length ? items.map(x => fnBlock(x.a, x.i)).join('\n') : '<p>（暂无）</p>') };
});

const PAGES = [...PROSE.map(p => ({ ...p, count: 0 })), ...catPages];
const GROUPS = ['开始', '控件检索', '高级指南', 'API 参考'];

const sidebar = GROUPS.map(g => {
  const items = PAGES.filter(p => p.group === g);
  return `<div class="grp"><div class="grp-title">${esc(g)}</div>${items.map(p =>
    `<a class="side-link" data-page="${p.id}" href="#/${p.id}">${esc(p.title)}${p.count ? `<span>${p.count}</span>` : ''}</a>` +
    (p.id.startsWith('cat-') ? `<div class="fnlist" data-fnlist="${p.id}">${APIS.map((a, i) => a.cat === p.id.slice(4) ? `<a href="#/${p.id}/fn-${i}">${esc(a.title)}</a>` : '').join('')}</div>` : '')
  ).join('')}</div>`;
}).join('');

const content = PAGES.map(p => `<article class="page" id="page-${p.id}">${p.html}</article>`).join('\n');

const searchIndex = [];
APIS.forEach((a, i) => searchIndex.push({ t: a.title, s: a.sig, page: 'cat-' + a.cat, anchor: 'fn-' + i, cat: (CATEGORIES.find(c => c.id === a.cat) || {}).name || a.cat }));
PAGES.forEach(p => { if (!p.id.startsWith('cat-')) searchIndex.push({ t: p.title, s: '', page: p.id, anchor: '', cat: p.group }); });

const html = `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AutoSDK 开发文档</title>
<style>
:root{--bg:#17181a;--side:#1e2022;--panel:#202225;--line:#2e3134;--text:#e6e6e6;--muted:#9aa0a6;--accent:#25c2a0;--code:#101214;--warn:#f59e0b;--ok:#25c2a0}
*{box-sizing:border-box}html{scroll-behavior:smooth}
body{margin:0;font:15px/1.7 -apple-system,"PingFang SC","Microsoft YaHei",sans-serif;background:var(--bg);color:var(--text)}
a{color:var(--accent)}
.topbar{position:fixed;top:0;left:0;right:0;height:56px;background:rgba(23,24,26,.95);backdrop-filter:blur(8px);border-bottom:1px solid var(--line);display:flex;align-items:center;gap:16px;padding:0 20px;z-index:50}
.topbar .logo{font-weight:700;font-size:16px;white-space:nowrap}.topbar .logo b{color:var(--accent)}
.searchwrap{position:relative;flex:1;max-width:520px}
.searchwrap input{width:100%;padding:8px 14px;border-radius:20px;border:1px solid var(--line);background:var(--code);color:var(--text);outline:none;font-size:14px}
.searchwrap input:focus{border-color:var(--accent)}
#searchDrop{position:absolute;top:42px;left:0;right:0;background:var(--panel);border:1px solid var(--line);border-radius:10px;max-height:340px;overflow:auto;display:none;box-shadow:0 12px 32px rgba(0,0,0,.5)}
#searchDrop a{display:block;padding:8px 14px;color:var(--text);text-decoration:none;font-size:13px;border-bottom:1px solid var(--line)}
#searchDrop a:hover{background:var(--side)}#searchDrop a b{color:var(--accent);margin-right:8px}
.toplinks{margin-left:auto;display:flex;gap:14px;font-size:13px;white-space:nowrap}
.toplinks a{color:var(--muted);text-decoration:none}.toplinks a:hover{color:var(--accent)}
.layout{display:flex;padding-top:56px}
aside{width:280px;flex:0 0 280px;position:fixed;top:56px;bottom:0;overflow:auto;background:var(--side);border-right:1px solid var(--line);padding:14px 10px 40px}
.grp{margin-bottom:6px}
.grp-title{padding:10px 12px 4px;font-size:12px;color:var(--muted);letter-spacing:1px}
.side-link{display:flex;justify-content:space-between;align-items:center;padding:7px 12px;border-radius:8px;color:var(--text);text-decoration:none;font-size:14px;margin:1px 0}
.side-link:hover{background:var(--panel)}
.side-link.on{color:var(--accent);background:rgba(37,194,160,.12)}
.side-link span{font-size:11px;color:var(--muted);background:var(--code);border:1px solid var(--line);border-radius:10px;padding:0 7px}
.fnlist{display:none;margin:0 0 4px 14px;border-left:1px solid var(--line);padding-left:8px}
.fnlist.open{display:block}
.fnlist a{display:block;padding:3px 10px;font-size:12.5px;color:var(--muted);text-decoration:none;border-radius:6px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.fnlist a:hover{color:var(--accent);background:var(--panel)}
main{margin-left:280px;flex:1;min-width:0;padding:34px 44px 90px;max-width:1060px}
.page{display:none}.page.on{display:block}
h1{font-size:26px;margin:0 0 14px;border-bottom:1px solid var(--line);padding-bottom:12px}
h1 .cnt{font-size:12px;color:var(--muted);background:var(--code);border:1px solid var(--line);border-radius:10px;padding:2px 10px;vertical-align:middle;margin-left:10px}
h2{font-size:19px;margin:26px 0 10px}h3{font-size:16.5px;margin:0 0 8px}
table{border-collapse:collapse;width:100%;margin:10px 0;font-size:13.5px}
th,td{border:1px solid var(--line);padding:7px 10px;text-align:left;vertical-align:top}
th{background:var(--panel)}
code{background:var(--code);border:1px solid var(--line);border-radius:5px;padding:1px 6px;font-family:ui-monospace,Consolas,monospace;font-size:13px}
pre{background:var(--code);border:1px solid var(--line);border-radius:10px;padding:14px 16px;overflow:auto;font-family:ui-monospace,Consolas,monospace;font-size:13px;line-height:1.6;margin:8px 0}
pre code{background:none;border:none;padding:0}
pre.hidden{display:none}
.fn{border:1px solid var(--line);border-radius:12px;background:var(--panel);padding:18px 20px;margin:18px 0}
.fn:target{border-color:var(--accent);box-shadow:0 0 0 2px rgba(37,194,160,.25)}
.sig{display:flex;align-items:center;gap:10px;background:var(--code);border:1px solid var(--line);border-radius:8px;padding:8px 12px;margin:6px 0 10px}
.sig code{flex:1;border:none;background:none;word-break:break-all;color:#7dd3fc}
.desc{color:#cfd4d9}
.ret{margin:8px 0;color:var(--muted);font-size:13.5px}.ret code{color:#7dd3fc}
.exhead{display:flex;justify-content:space-between;align-items:center;margin:12px 0 4px;font-size:12.5px;color:var(--muted)}
.copy{background:var(--accent);color:#08251d;border:none;border-radius:6px;padding:4px 12px;font-size:12px;cursor:pointer;font-weight:600}
.copy:hover{filter:brightness(1.1)}
.hintbox{margin-top:10px;border-left:3px solid var(--accent);background:rgba(37,194,160,.08);border-radius:0 8px 8px 0;padding:8px 12px;font-size:13px;color:#bfe8dd}
.note{border-radius:10px;padding:12px 16px;margin:14px 0;font-size:14px}
.note.ok{background:rgba(37,194,160,.1);border:1px solid rgba(37,194,160,.35)}
.note.warn{background:rgba(245,158,11,.1);border:1px solid rgba(245,158,11,.4)}
.noparam{color:var(--muted);font-size:13px}
@media (max-width:900px){aside{display:none}main{margin-left:0;padding:20px}}
</style>
</head>
<body>
<div class="topbar">
  <div class="logo"><b>AutoSDK</b> 开发文档</div>
  <div class="searchwrap"><input id="q" placeholder="搜索函数 / 页面（如 click、找色、http）…" autocomplete="off"><div id="searchDrop"></div></div>
  <div class="toplinks"><a href="../api-reference.html">函数速查卡</a><a href="../guide/index.html">图文教程</a><a href="../index.html">文档门户</a></div>
</div>
<div class="layout">
<aside id="side">${sidebar}</aside>
<main>${content}</main>
</div>
<script>
const INDEX = ${JSON.stringify(searchIndex)};
const pages = [...document.querySelectorAll('.page')];
const sideLinks = [...document.querySelectorAll('.side-link')];
function show(id, anchor) {
  let ok = false;
  pages.forEach(p => { const on = p.id === 'page-' + id; p.classList.toggle('on', on); ok = ok || on; });
  if (!ok) { id = 'intro'; pages.forEach(p => p.classList.toggle('on', p.id === 'page-intro')); }
  sideLinks.forEach(a => {
    const on = a.dataset.page === id;
    a.classList.toggle('on', on);
    const fl = document.querySelector('.fnlist[data-fnlist="' + a.dataset.page + '"]');
    if (fl) fl.classList.toggle('open', on);
  });
  if (anchor) { const el = document.getElementById(anchor); if (el) setTimeout(() => el.scrollIntoView({ block: 'start' }), 30); }
  else window.scrollTo(0, 0);
}
function route() {
  const h = decodeURIComponent(location.hash.replace(/^#\\//, '')) || 'intro';
  const [id, anchor] = h.split('/');
  show(id, anchor);
}
window.addEventListener('hashchange', route);
route();
document.addEventListener('click', e => {
  const btn = e.target.closest('.copy');
  if (btn) {
    const src = document.getElementById(btn.dataset.copy);
    const text = src ? src.textContent : '';
    (navigator.clipboard ? navigator.clipboard.writeText(text) : Promise.reject()).then(() => {
      btn.textContent = '已复制'; setTimeout(() => btn.textContent = '复制', 1200);
    }).catch(() => { btn.textContent = '复制失败'; setTimeout(() => btn.textContent = '复制', 1200); });
  }
});
const q = document.getElementById('q'), drop = document.getElementById('searchDrop');
q.addEventListener('input', () => {
  const v = q.value.trim().toLowerCase();
  if (!v) { drop.style.display = 'none'; return; }
  const hits = INDEX.filter(x => (x.t + ' ' + x.s).toLowerCase().includes(v)).slice(0, 14);
  drop.innerHTML = hits.map(x => '<a href="#/' + x.page + (x.anchor ? '/' + x.anchor : '') + '"><b>' + x.cat + '</b>' + x.t.replace(/</g, '&lt;') + '</a>').join('') || '<a>无匹配</a>';
  drop.style.display = 'block';
});
drop.addEventListener('click', e => { if (e.target.closest('a')) { drop.style.display = 'none'; q.value = ''; } });
document.addEventListener('keydown', e => { if (e.key === '/' && document.activeElement !== q) { e.preventDefault(); q.focus(); } });
</script>
</body>
</html>`;

mkdirSync(join(root, 'docs', 'devdocs'), { recursive: true });
writeFileSync(join(root, 'docs', 'devdocs', 'index.html'), html, 'utf8');
console.log('Generated docs/devdocs/index.html with ' + PAGES.length + ' pages / ' + APIS.length + ' functions.');
