#!/usr/bin/env node
// Generates the single canonical offline developer site at docs/index.html.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { APIS, CATEGORIES } from './generate-api-reference.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const rootPackage = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
const extensionPackage = JSON.parse(readFileSync(join(root, 'vscode-extension', 'package.json'), 'utf8'));
const template = readFileSync(join(root, 'tools', 'devdocs-template.html'), 'utf8');

function esc(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

let snippetIndex = 0;
function codeBlock(source) {
  const id = 'example-' + (++snippetIndex);
  return `<div class="code-block"><button class="copy-button" type="button" data-copy="${id}">复制</button><pre><code id="${id}">${esc(source.trim())}</code></pre></div>`;
}

function page(id, group, title, lead, body, eyebrow = group) {
  return `<article class="page" id="page-${id}" data-group="${esc(group)}" data-title="${esc(title)}">
  <header class="page-head">
    <p class="eyebrow">${esc(eyebrow)}</p>
    <h1>${esc(title)}</h1>
    <p class="lead">${esc(lead)}</p>
  </header>
  ${body}
</article>`;
}

const firstScript = `function main() {
  toastLog("AutoSDK 已连接");
  logd(JSON.stringify(device.getDeviceInfo()));
  const caps = auto.capabilities();
  logd(JSON.stringify(caps));

  if (caps.automation && caps.automation.screenshot === true) {
    const image = screenshot();
    if (typeof image === "string") {
      logd("截图 Base64 长度: " + image.length);
    } else {
      const error = lastError();
      logw("截图失败: " + (error ? error.message : "未知原因"));
    }
  } else {
    logw("当前签名或适配器不支持截图");
  }
}
main();`;

const selectorScript = `function main() {
  const query = Selector()
    .text("登录")
    .type("Button")
    .visible(true);

  if (!query.waitFor(3000)) {
    logw("未找到登录按钮");
    return;
  }

  const login = query.findOne();
  if (!login) return;

  logd(JSON.stringify(login.bounds));
  login.click();
}
main();`;

const guides = [
  {
    id: 'quickstart',
    group: '入门',
    title: '5 分钟上手',
    lead: '从安装插件到在真机运行第一段 JavaScript，只保留最短的成功路径。',
    search: '安装 插件 VSIX 真机 连接 运行 JavaScript 快速开始 入门',
    body: `
      <div class="callout success"><strong>当前版本</strong>SDK v${esc(rootPackage.version)} · VS Code 插件 v${esc(extensionPackage.version)} · 完整文档和 API 均可离线使用。</div>
      <div class="steps">
        <div class="step"><strong>安装并签名宿主 App</strong><p>从 GitHub Releases 下载最新 IPA 或构建产物，用自己的 Apple ID 签名安装。启动后保持 App 在前台。</p></div>
        <div class="step"><strong>安装 VS Code 插件</strong><p>下载 <code>autosdk-vscode-${esc(extensionPackage.version)}.vsix</code>，在 VS Code 的“扩展 → … → 从 VSIX 安装”中选择它。</p></div>
        <div class="step"><strong>点击手机图标，添加手机</strong><p>电脑和手机使用同一 Wi-Fi，手机开启 Wi-Fi 调试。点 VS Code 左侧 AutoSDK 手机图标 → 搜索 Wi-Fi 手机 → 添加并连接。首次填写手机显示的配对码，不需要写连接代码。</p></div>
        <div class="step"><strong>点按钮开始运行</strong><p>侧栏显示“已连接”后，点“新建示例脚本”→“运行整个脚本”。无需先保存文件；也可以在编辑区右键运行，或点右上角 ▶。</p></div>
      </div>
      <h2>第一段脚本</h2>
      ${codeBlock(firstScript)}
      <div class="callout warning"><strong>先看能力，再写脚本</strong><code>auto.capabilities()</code> 返回当前签名和适配器真正可用的能力。跨 App 控制、截图或节点能力不可用时，不要用死循环重试。</div>
      <h2>接下来做什么</h2>
      <div class="card-grid">
        <div class="info-card"><strong>看不见控件？</strong><p>打开“可视化检查器”，直接点选截图节点并生成选择器。</p></div>
        <div class="info-card"><strong>已经知道函数名？</strong><p>按 <code>/</code> 聚焦全局搜索，输入函数或模块名，回车直达。</p></div>
        <div class="info-card"><strong>想复制现成代码？</strong><p>从“常用实战”开始，HTTP、图色、存储和线程都给出完整示例。</p></div>
        <div class="info-card"><strong>遇到失败？</strong><p>先看“排错清单”，再通过 <code>lastError()</code> 获取最近错误。</p></div>
      </div>`
  },
  {
    id: 'connect',
    group: '入门',
    title: '连接与运行',
    lead: '打开左侧手机图标 → 搜索手机 → 添加并连接 → 运行。正常流程不用输入命令、IP 或配置 JSON。',
    search: 'Bonjour mDNS 局域网 广播 USB WiFi iproxy idevice_id 搜索 添加 iPhone websocket ws token 连接 运行 停止 部署',
    body: `
      <h2>在「设备与调试」侧栏连接</h2>
      <ol>
        <li>电脑与手机进入同一可信局域网，宿主 App 开启 Wi-Fi 调试并允许 iOS“本地网络”权限。</li>
        <li>点击 VS Code 左侧 <strong>AutoSDK 手机图标</strong>，或底部“AutoSDK: 连接手机”。</li>
        <li>点 <strong>搜索 Wi-Fi 手机</strong>，在手机卡片上点 <strong>添加并连接</strong>。首次输入手机 App 显示的配对码（Debug Token）；这是安全凭证，不是代码。</li>
        <li>出现 <strong>已连接</strong> 后，点 <strong>新建示例脚本 → 运行整个脚本</strong>。点 <strong>截图与节点</strong> 即可打开可视化采集工具。</li>
      </ol>
      <p>再次打开 VS Code，点击侧栏“连接”即可。手机地址变化时重新搜索，选择同一手机会自动更新地址并复用当前工作区的配对信息。切换其他手机或工作区需要重新配对。空白窗口也能添加手机，不要求先建立项目。</p>
      <p>扫描可以点“取消搜索”。连接失败时侧栏会提示下一步：重试连接、重新配对或重新搜索。不要关闭认证来省略首次配对。</p>
      <h2>常用按钮</h2>
      <table>
        <thead><tr><th>按钮</th><th>用途</th></tr></thead>
        <tbody>
          <tr><td>搜索 Wi-Fi 手机</td><td>自动扫描局域网，手机卡片上点“添加并连接”。</td></tr>
          <tr><td>运行整个脚本</td><td>执行侧栏显示的脚本文件，支持未保存内容；右键与标题栏 ▶ 也能运行。</td></tr>
          <tr><td>只运行选中代码</td><td>只发送单个非空 JS/TS 选区；不继承上次运行的变量。</td></tr>
          <tr><td>停止脚本</td><td>发送协作停止请求；纯 JavaScript 无限循环暂不能保证强制中断。</td></tr>
          <tr><td>截图与节点</td><td>画面点选、节点查看、颜色/OCR/图像测试和代码生成。</td></tr>
          <tr><td>运行日志 / 使用指南</td><td>查看执行结果、详细错误和插件内置离线操作说明。</td></tr>
        </tbody>
      </table>
      <h2>找不到手机时再看这里</h2>
      <p>先确认 App 前台运行、Wi-Fi 调试开启、本地网络权限允许，以及手机和电脑不在隔离的访客网络。只有广播被屏蔽时，展开侧栏“更多连接方式”，点“手动填写手机地址”。USB 备用需要额外安装 idevice_id / iproxy；正常 Wi-Fi 不需要。</p>
      <div class="callout"><strong>配对码不参与广播</strong>token 保存在 VS Code SecretStorage，不放入侧栏或设置 JSON。广播身份不是密码学认证，只连接可信局域网。未信任工作区禁止运行脚本。</div>
      <div class="callout warning"><strong>调试范围</strong>当前支持运行、停止、日志、截图与节点采集，不支持断点单步调试；真实 iPhone Wi-Fi 和跨 App 私有能力仍需真机验收。</div>`
  },
  {
    id: 'scope',
    group: '核心指南',
    title: '能力与签名',
    lead: 'iOS 自动化能力由宿主、签名和当前适配器共同决定；文档只承诺运行时报告为可用的能力。',
    search: '能力 capabilities 签名 越狱 非越狱 跨应用 权限 安全 限制',
    body: `
      <h2>先读取能力</h2>
      ${codeBlock(`function main() {
  const caps = auto.capabilities();
  logd(JSON.stringify(caps, null, 2));
}
main();`)}
      <table>
        <thead><tr><th>场景</th><th>通常可用</th><th>需要确认</th></tr></thead>
        <tbody>
          <tr><td>宿主 App 内</td><td>JavaScript、文件、存储、HTTP、日志、定时器</td><td>相册、通知、麦克风等系统权限</td></tr>
          <tr><td>内置无 WDA 适配器</td><td>由 <code>auto.capabilities()</code> 明确报告的触摸、截图和节点能力</td><td>签名 entitlement、设备系统版本与宿主集成</td></tr>
          <tr><td>网络调试</td><td>USB 回环或可信 Wi-Fi 上的实时运行</td><td>调试服务器开关、端口、token 和局域网权限</td></tr>
        </tbody>
      </table>
      <div class="callout warning"><strong>失败必须可见</strong>交互 API 返回 <code>false</code> 或 <code>null</code> 时，读取 <code>lastError()</code>；不要把“调用完成”当作“操作成功”。</div>
      <h2>安全建议</h2>
      <ul>
        <li>发布构建默认关闭调试服务器，开发时才显式启用。</li>
        <li>Wi-Fi 模式使用随机长 token，只连接可信局域网。</li>
        <li>HTTP 白名单和 TLS 校验按宿主需求配置，不在脚本中绕过。</li>
        <li>脚本退出前关闭定时器、线程、音频和截图缓存。</li>
      </ul>`
  },
  {
    id: 'inspector',
    group: '核心指南',
    title: '可视化检查器',
    lead: '把截图、节点树、选择器验证和代码生成放在一个面板里，减少来回猜坐标。',
    search: 'Visual Inspector 可视化检查器 截图 节点树 选择器 图片 颜色 OCR 调试',
    body: `
      <h2>推荐流程</h2>
      <div class="steps">
        <div class="step"><strong>打开目标页面</strong><p>UIKit 模式请让宿主 App 保持前台；特签内置适配器仅在运行时能力可用且宿主进程仍在运行时检查其他 App。然后点侧栏“截图与节点”。</p></div>
        <div class="step"><strong>采集关联快照</strong><p>检查器会把截图和节点树作为同一轮采集结果处理，避免节点位置与画面错位；采集可取消。</p></div>
        <div class="step"><strong>点选并验证</strong><p>点击截图或节点，查看属性、范围和层级；使用选择器测试确认唯一匹配。</p></div>
        <div class="step"><strong>生成最小选择器</strong><p>优先保留稳定且能唯一定位的属性，再复制 JavaScript 到脚本。</p></div>
      </div>
      <div class="callout warning"><strong>跨 App 不是普通签名默认能力</strong>免费签名的 TemplateApp 退到后台后可能被 iOS 挂起。只有启用内置 no-WDA、签名环境允许私有能力，并且 <code>auto.capabilities().automation</code> 中的 <code>nodes</code>、<code>screenshot</code>、<code>click</code> 对应能力为真时，才可使用跨 App Inspector；UIKit 适配器只检查宿主 App。</div>
      <h2>面板能做什么</h2>
      <div class="card-grid">
        <div class="info-card"><strong>节点模式</strong><p>树与截图联动、高亮匹配区域、节点动作后自动刷新。</p></div>
        <div class="info-card"><strong>选择器模式</strong><p>验证匹配数量，生成链式 Selector 或对象选择器代码。</p></div>
        <div class="info-card"><strong>图像模式</strong><p>框选区域、导出截图、生成找图或区域截图参数。</p></div>
        <div class="info-card"><strong>颜色模式</strong><p>读取像素、生成颜色值与区域参数，适合图色调试。</p></div>
      </div>
      <div class="callout"><strong>节点太多时</strong>通过 <code>autosdk.inspectorMaxNodes</code> 控制 1–2000 个节点；动作后的刷新延迟可通过 <code>autosdk.inspectorActionRefreshDelay</code> 调整为 0–5000ms。</div>
      <h2>稳定选择器原则</h2>
      <p>切换模式、节点或选区后，旧的异步结果不会覆盖新代码；快照失去选中节点时自动清空代码。代码为空时不能复制或插入。每次运行选区都会新建脚本上下文，不会继承上一次运行的变量，请选中完整、可独立执行的代码。</p>
      <ol>
        <li>优先使用业务稳定的 <code>id</code>、<code>name</code> 或明确文本。</li>
        <li>属性不唯一时再组合 <code>type</code>、<code>visible</code> 和层级关系。</li>
        <li>动态列表避免绝对坐标和完整 XPath；先缩小父容器，再找子节点。</li>
        <li>操作前验证匹配数，页面变化后重新采集快照。</li>
      </ol>`
  },
  {
    id: 'selectors',
    group: '核心指南',
    title: '选择器与节点',
    lead: '链式 Selector 负责查找，节点对象负责读取属性、遍历关系和执行动作。',
    search: 'Selector node 节点 选择器 XPath text id name type bounds findOne findAll',
    body: `
      <h2>链式查找</h2>
      ${codeBlock(selectorScript)}
      <h2>常用条件</h2>
      <table>
        <thead><tr><th>条件</th><th>适合场景</th></tr></thead>
        <tbody>
          <tr><td><code>text(value)</code></td><td>稳定、完整的可见文字。</td></tr>
          <tr><td><code>id(value)</code> / <code>name(value)</code></td><td>开发者提供的稳定标识。</td></tr>
          <tr><td><code>type(value)</code></td><td>Button、TextField 等控件类型。</td></tr>
          <tr><td><code>visible(true)</code> / <code>enabled(true)</code></td><td>排除不可交互节点。</td></tr>
          <tr><td><code>contains(value)</code> / 正则条件</td><td>文字包含动态部分。</td></tr>
        </tbody>
      </table>
      <h2>节点关系</h2>
      ${codeBlock(`function main() {
  const item = Selector().text("设置").findOne(2000);
  if (!item) return;

  const parent = item.parent();
  const children = parent ? parent.children() : [];
  logd("同级数量: " + item.siblings().length);
  logd("子节点数量: " + children.length);
}
main();`)}
      <h2>XPath</h2>
      <p>XPath 适合迁移已有脚本或表达复杂层级。移动端页面结构容易变化，新脚本优先使用链式条件和关系查找。</p>
      ${codeBlock(`function main() {
  const result = Selector()
    .xpath('//*[@type="Button" and @text="继续"]')
    .findAll();
  if (result && result.length) result[0].click();
}
main();`)}
      <div class="callout warning"><strong>超时单位是毫秒</strong><code>waitFor(3000)</code> 最多等待 3 秒；超时返回 <code>false</code>，随后再用 <code>findOne()</code> 获取节点。</div>`
  },
  {
    id: 'recipes',
    group: '核心指南',
    title: '常用实战',
    lead: '可直接复制的完整片段，覆盖图色、HTTP、SQLite 和后台任务。',
    search: '实战 示例 图色 OCR HTTP JSON SQLite 线程 execAsync cache',
    body: `
      <h2>同一画面做多次图色识别</h2>
      ${codeBlock(`function main() {
  screen.cache(true);
  try {
    const logo = screen.findImage("images/logo.png", { threshold: 0.9 });
    const warning = screen.findColor("#ff3b30", { x: 0, y: 0, width: 390, height: 300 });
    const words = screen.ocr({ x: 0, y: 0, width: 390, height: 400 });
    logd(JSON.stringify({ logo, warning, words }));
  } finally {
    screen.cache(false);
  }
}
main();`)}
      <h2>获取 JSON</h2>
      ${codeBlock(`function main() {
  const response = http.getJSON("https://api.example.com/status", {
    timeout: 10000,
    headers: { Accept: "application/json" }
  });
  logd("HTTP " + response.status);
  logd(JSON.stringify(response.json));
}
main();`)}
      <h2>SQLite 持久化</h2>
      ${codeBlock(`function main() {
  const db = sqlite.open("data/tasks.sqlite");
  try {
    sqlite.exec(db, "CREATE TABLE IF NOT EXISTS tasks (id INTEGER PRIMARY KEY, title TEXT)");
    sqlite.exec(db, "INSERT INTO tasks(title) VALUES (?)", ["同步"]);
    logd(JSON.stringify(sqlite.query(db, "SELECT * FROM tasks ORDER BY id DESC")));
  } finally {
    sqlite.close(db);
  }
}
main();`)}
      <h2>后台执行并等待结果</h2>
      ${codeBlock(`function main() {
  const worker = execAsync(function (a, b) {
    sleep(200);
    return a + b;
  }, 20, 22);

  logd("结果: " + worker.join());
}
main();`)}
      <div class="callout"><strong>先复制，再按实际环境替换</strong>URL、文件路径、图片模板和选择器只是示例值；API 的精确参数以对应模块页为准。</div>`
  },
  {
    id: 'troubleshooting',
    group: '帮助',
    title: '排错清单',
    lead: '按连接、能力、选择器和脚本生命周期的顺序排查，通常能最快定位问题。',
    search: '排错 故障 连接失败 token 点击 false 找不到 节点 HTTP lastError 超时 死循环',
    body: `
      <div class="faq"><h3>插件搜不到 Wi-Fi 手机或连不上</h3><ol><li>保持宿主 App 在前台，确认 Wi-Fi 调试已开启并允许 iOS“本地网络”权限。</li><li>电脑和手机必须在同一局域网；访客网络/AP 隔离会阻止互访。</li><li>放行 mDNS UDP 5353 后重新运行 <code>Scan Wi-Fi and Add iPhone</code>；仍搜不到就选择手动输入 App 显示的 IP。</li><li>确认 token 来自当前安装，端口为 9001。</li></ol></div>
      <div class="faq"><h3>点击返回 false</h3><p>打印 <code>auto.capabilities()</code> 与 <code>lastError()</code>。确认当前适配器支持触摸、坐标在屏幕范围内，节点仍然可见且可交互。</p></div>
      <div class="faq"><h3>选择器找不到节点</h3><p>重新采集检查器快照，先测试单个稳定条件，再逐步增加限制。注意页面切换、动画、WebView 和动态文本会让旧节点失效。</p></div>
      <div class="faq"><h3>HTTP 请求被拒绝</h3><p>检查宿主的 HTTP 开关、域名白名单、ATS/TLS 配置和超时。<code>http.getJSON()</code> 返回完整响应，解析结果在 <code>response.json</code>。</p></div>
      <div class="faq"><h3>脚本一直不结束</h3><p>检查未清理的 <code>setInterval</code>、后台线程、音频或持续任务。用 <code>Stop Active Script</code> 停止，并在 <code>finally</code> 中释放资源。</p></div>
      <h2>最小诊断脚本</h2>
      ${codeBlock(`function main() {
  logd(JSON.stringify(auto.capabilities(), null, 2));
  logd(JSON.stringify(device.getDeviceInfo(), null, 2));
  logd("最近错误: " + JSON.stringify(lastError()));
}
main();`)}
      <p>仍无法判断时，把插件输出面板日志、宿主日志、最小脚本和能力结果一起提交到 GitHub Issues。</p>`
  }
];

const apiCategories = CATEGORIES
  .map(category => ({ ...category, items: APIS.filter(api => api.cat === category.id) }))
  .filter(category => category.items.length > 0);

function apiEntry(api, index) {
  const exampleId = 'api-example-' + index;
  const filter = [api.sig, api.title, api.desc, ...(api.params || []).flat(), api.returns].join(' ').toLowerCase();
  const params = api.params?.length
    ? `<table class="param-table"><thead><tr><th>参数</th><th>类型</th><th>说明</th></tr></thead><tbody>${api.params.map(([name, type, desc]) =>
      `<tr><td><code>${esc(name)}</code></td><td><code>${esc(type)}</code></td><td>${esc(desc)}</td></tr>`).join('')}</tbody></table>`
    : '<p class="return-value">无参数</p>';
  return `<details class="api-entry" id="fn-${index}" data-filter="${esc(filter)}">
    <summary><span class="api-signature">${esc(api.sig)}</span><span class="api-name">${esc(api.title)}</span></summary>
    <div class="api-body">
      <p class="api-description">${esc(api.desc)}</p>
      <p class="meta-label">参数</p>
      ${params}
      <p class="meta-label">返回值</p>
      <p class="return-value"><code>${esc(api.returns)}</code></p>
      <p class="meta-label">示例</p>
      <div class="code-block"><button class="copy-button" type="button" data-copy="${exampleId}">复制</button><pre><code id="${exampleId}">${esc(api.example)}</code></pre></div>
    </div>
  </details>`;
}

const apiPages = apiCategories.map(category => {
  const indexedItems = category.items.map(api => ({ api, index: APIS.indexOf(api) }));
  const jump = indexedItems.map(({ api, index }) => {
    const filter = (api.sig + ' ' + api.title).toLowerCase();
    return `<a href="#/api-${category.id}/fn-${index}" data-filter="${esc(filter)}">${esc(api.sig)}</a>`;
  }).join('');
  const body = `
    <div class="api-toolbar">
      <input class="api-filter" type="search" placeholder="在本模块过滤…" aria-label="过滤${esc(category.name)} API">
      <button class="secondary-button" type="button" data-expand>全部展开</button>
      <span><span class="api-visible-count">${indexedItems.length}</span> / ${indexedItems.length}</span>
    </div>
    <nav class="api-jump" aria-label="${esc(category.name)}函数索引">${jump}</nav>
    <div class="api-empty">本模块没有匹配的 API</div>
    ${indexedItems.map(({ api, index }) => apiEntry(api, index)).join('')}
  `;
  return page(
    'api-' + category.id,
    'API 参考',
    category.name,
    `本模块共 ${indexedItems.length} 个 API 条目。点击函数展开参数、返回值和完整示例。`,
    body,
    'API Reference'
  );
});

function navGroup(title, links) {
  return `<section class="nav-group"><div class="nav-title">${esc(title)}</div>${links.join('')}</section>`;
}

function navLink(id, title, count = '') {
  return `<a class="nav-link" href="#/${id}" data-page="${id}"><span>${esc(title)}</span>${count === '' ? '' : `<span class="nav-count">${count}</span>`}</a>`;
}

const sidebar = [
  navGroup('入门', guides.filter(item => item.group === '入门').map(item => navLink(item.id, item.title))),
  navGroup('核心指南', guides.filter(item => item.group === '核心指南').map(item => navLink(item.id, item.title))),
  navGroup('API 参考', apiCategories.map(category => navLink('api-' + category.id, category.name, category.items.length))),
  navGroup('帮助', guides.filter(item => item.group === '帮助').map(item => navLink(item.id, item.title)))
].join('');

const searchIndex = [
  ...guides.map(item => ({
    title: item.title,
    meta: item.group,
    href: '#/' + item.id,
    search: [item.title, item.lead, item.search].join(' ')
  })),
  ...apiCategories.map(category => ({
    title: category.name,
    meta: 'API 模块 · ' + category.items.length + ' 项',
    href: '#/api-' + category.id,
    search: category.name + ' API 模块 ' + category.items.map(item => item.sig).join(' ')
  })),
  ...APIS.map((api, index) => ({
    title: api.sig,
    meta: CATEGORIES.find(category => category.id === api.cat)?.name || 'API',
    href: '#/api-' + api.cat + '/fn-' + index,
    search: [api.sig, api.title, api.desc, ...(api.params || []).flat(), api.returns].join(' ')
  }))
];

const content = [
  ...guides.map(item => page(item.id, item.group, item.title, item.lead, item.body)),
  ...apiPages
].join('');

const html = template
  .replaceAll('{{VERSION}}', esc(rootPackage.version))
  .replaceAll('{{API_COUNT}}', String(APIS.length))
  .replace('{{SIDEBAR}}', sidebar)
  .replace('{{CONTENT}}', content)
  .replace('{{SEARCH_INDEX}}', JSON.stringify(searchIndex).replace(/</g, '\\u003c'))
  .replace(/[ \t]+(?=\r?$)/gm, '');

writeFileSync(join(root, 'docs', 'index.html'), html, 'utf8');
console.log(`Generated docs/index.html with ${guides.length} guide pages / ${apiCategories.length} API categories / ${APIS.length} functions.`);
