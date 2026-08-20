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
  logd(JSON.stringify(auto.capabilities()));

  const image = screenshot();
  logd("截图 Base64 长度: " + image.length);
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
        <div class="step"><strong>搜索并添加手机</strong><p>点击状态栏的 <code>AutoSDK: add iPhone</code>，选择搜索到的 USB 手机并输入宿主 App 显示的 token；插件会自动保存、启动隧道并测试连接。</p></div>
        <div class="step"><strong>右键运行</strong><p>打开 JavaScript 或 TypeScript 文件，在编辑区右键选择 <code>AutoSDK: Run Current Script</code>；编辑器标题栏也提供播放按钮。</p></div>
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
    lead: 'USB 更稳定，Wi-Fi 更轻便；两种方式共用同一套插件命令。',
    search: 'USB WiFi iproxy idevice_id 搜索 添加 iPhone websocket ws token 连接 运行 停止 部署',
    body: `
      <h2>USB 连接（推荐）</h2>
      <ol>
        <li>安装包含 <code>iproxy</code>、<code>idevice_id</code> 和 <code>ideviceinfo</code> 的 libimobiledevice 工具，并确保它们在 PATH 或同一目录。</li>
        <li>手机通过 USB 连接电脑，保持宿主 App 在前台。</li>
        <li>点击状态栏 <code>AutoSDK: add iPhone</code>，或运行 <code>AutoSDK: Search and Add iPhone</code>。</li>
        <li>选择手机并输入 token；插件自动保存 UDID、启动隧道并测试连接。</li>
      </ol>
      <p>需要手工排查时，可在终端运行：</p>
      ${codeBlock('iproxy 9001 9001')}
      <h2>Wi-Fi 连接</h2>
      <ol>
        <li>电脑与手机进入同一可信局域网。</li>
        <li>宿主 App 必须启用 Wi-Fi 调试，并使用至少 16 个字符的随机 token。</li>
        <li>配置 App 显示的 <code>ws://手机IP:9001</code>，无需启动 USB 隧道。</li>
      </ol>
      <h2>常用命令</h2>
      <table>
        <thead><tr><th>命令</th><th>用途</th></tr></thead>
        <tbody>
          <tr><td><code>Search and Add iPhone</code></td><td>搜索 USB 手机，选中后自动保存、启动隧道并测试；也可回退到 Wi-Fi 添加。</td></tr>
          <tr><td><code>Run Current Script</code></td><td>立即执行当前编辑器内容，最适合迭代。</td></tr>
          <tr><td><code>Send Current Script to Device</code></td><td>把脚本保存到设备脚本列表。</td></tr>
          <tr><td><code>Stop Active Script</code></td><td>停止当前脚本、定时器和后台任务。</td></tr>
          <tr><td><code>Capture Device Screenshot</code></td><td>抓取当前设备画面。</td></tr>
          <tr><td><code>Open Visual Inspector</code></td><td>采集截图和节点树并进行交互调试。</td></tr>
        </tbody>
      </table>
      <div class="callout"><strong>token 不写入工作区配置</strong>插件把 token 放入 VS Code SecretStorage，并与连接地址、工作区绑定。</div>`
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
        <div class="step"><strong>打开目标页面</strong><p>让设备停在要调试的界面，执行 <code>AutoSDK: Open Visual Inspector</code>。</p></div>
        <div class="step"><strong>采集关联快照</strong><p>检查器会把截图和节点树作为同一轮采集结果处理，避免节点位置与画面错位；采集可取消。</p></div>
        <div class="step"><strong>点选并验证</strong><p>点击截图或节点，查看属性、范围和层级；使用选择器测试确认唯一匹配。</p></div>
        <div class="step"><strong>生成最小选择器</strong><p>优先保留稳定且能唯一定位的属性，再复制 JavaScript 到脚本。</p></div>
      </div>
      <h2>面板能做什么</h2>
      <div class="card-grid">
        <div class="info-card"><strong>节点模式</strong><p>树与截图联动、高亮匹配区域、节点动作后自动刷新。</p></div>
        <div class="info-card"><strong>选择器模式</strong><p>验证匹配数量，生成链式 Selector 或对象选择器代码。</p></div>
        <div class="info-card"><strong>图像模式</strong><p>框选区域、导出截图、生成找图或区域截图参数。</p></div>
        <div class="info-card"><strong>颜色模式</strong><p>读取像素、生成颜色值与区域参数，适合图色调试。</p></div>
      </div>
      <div class="callout"><strong>节点太多时</strong>通过 <code>autosdk.inspectorMaxNodes</code> 控制 1–2000 个节点；动作后的刷新延迟可通过 <code>autosdk.inspectorActionRefreshDelay</code> 调整为 0–5000ms。</div>
      <h2>稳定选择器原则</h2>
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
      <div class="faq"><h3>插件搜不到设备或连不上</h3><ol><li>解锁手机、确认已信任此电脑，并保持宿主 App 在前台。</li><li>确认 libimobiledevice 的 <code>idevice_id</code> 与 <code>iproxy</code> 在 PATH 或同一目录。</li><li>重新运行 <code>Search and Add iPhone</code>；搜不到时可直接选择 Wi-Fi 添加。</li><li>确认 token 来自当前安装，端口为 9001。</li></ol></div>
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
