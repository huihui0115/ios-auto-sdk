import fs from 'node:fs';
import { createHash } from 'node:crypto';

const dataUrl = new URL('./data/', import.meta.url);
export const manifest = JSON.parse(fs.readFileSync(new URL('manifest.json', dataUrl), 'utf8'));
// Fail closed if the package is incomplete or generated files were edited independently.
for (const name of ['catalog.json', 'autosdk.d.ts']) {
  const contents = fs.readFileSync(new URL(name, dataUrl), 'utf8').replace(/\r\n/g, '\n');
  if (createHash('sha256').update(contents).digest('hex') !== manifest.outputs[name]) throw new Error('AutoSDK MCP data integrity check failed');
}
export const catalog = JSON.parse(fs.readFileSync(new URL('catalog.json', dataUrl), 'utf8'));
export const instructions = `这是 AutoSDK ${catalog.sdkVersion} 的只读文档服务，不连接手机、不执行代码。写代码前先 search_api，再 get_api 核对声明、参数、返回值和限制，完成后 validate_script。查不到的 API 不要猜测；实例方法需要对应类型实例，不是全局对象。脚本运行于 iOS JavaScriptCore，不是 Node.js/浏览器，不支持 npm/import/require。TypeScript 必须经插件转译。能力、签名、权限和真实设备状态不能由静态检查证明；必须保留失败处理和能力检查。文档版本不是已连接手机版本。`;
export const caveats = [
  '数据是本包 SDK 版本的声明和文档，不是手机探测结果；首次引入版本未记录时不猜测。',
  '静态检查不能证明逻辑正确、设备权限、私有 API、后台保活或真机运行成功。',
  'any、动态属性和类型断言可能绕过类型检查；未知的宿主自定义 API 需要补充可信声明。'
];
const byName = new Map(), documents = new Map(catalog.documents.map(doc => [doc.id, doc]));
const types = new Map(catalog.types.map(type => [type.name, type]));
for (const item of catalog.callables) {
  const list = byName.get(item.name) || [];
  list.push(item); byName.set(item.name, list);
}
function relatedDocs(items) {
  return [...new Set(items.flatMap(item => item.docIds))].map(id => documents.get(id));
}
const index = [
  ...[...byName].map(([name, entries]) => {
    const docs = relatedDocs(entries);
    return { name, kind: entries[0].kind, title: docs[0]?.title || entries[0].notes || name,
      text: [name, ...entries.map(e => e.notes), ...docs.flatMap(d => [d.title, d.desc])].join(' ').toLowerCase() };
  }),
  ...catalog.types.map(t => ({ name: t.name, kind: 'type', title: t.name, text: `${t.name} ${t.declaration}`.toLowerCase() })),
  ...catalog.documents.map(d => ({ name: d.id, kind: 'documentation', title: d.title, text: `${d.sig} ${d.title} ${d.desc}`.toLowerCase() }))
];
export function searchApi(query, limit = 8, offset = 0) {
  const tokens = query.toLowerCase().trim().split(/\s+/u).filter(Boolean);
  const hits = !tokens.length ? [] : index.map(item => ({ item, score: tokens.reduce((score, token) => {
    if (!item.text.includes(token)) return -10000;
    return score + (item.name.toLowerCase() === token ? 100 : item.name.toLowerCase().includes(token) ? 40 : item.title.toLowerCase().includes(token) ? 20 : 1);
  }, 0) })).filter(hit => hit.score > 0).sort((a, b) => b.score - a.score || a.item.name.localeCompare(b.item.name, 'en'));
  return { sdkVersion: catalog.sdkVersion, total: hits.length, offset,
    nextOffset: offset + limit < hits.length ? offset + limit : null,
    results: hits.slice(offset, offset + limit).map(({ item: { text, ...item } }) => item),
    hint: '用结果 name 调 get_api；没有结果不代表允许猜测。instance 是类型实例的方法，不可当作全局模块调用。' };
}
export function getApi(name) {
  const entries = byName.get(name), type = types.get(name), document = documents.get(name);
  if (!entries && !type && !document) return { sdkVersion: catalog.sdkVersion, found: false, name,
    message: '此版本没有该精确名称的声明/文档；不要编造调用。请用 search_api 查找。' };
  const docs = document ? [document] : entries ? relatedDocs(entries) : [];
  const referencedNames = new Set((entries || []).flatMap(entry => [...`${entry.signature}`.matchAll(/\bAuto\w+\b/g)].map(m => m[0])));
  const references = [...referencedNames].filter(n => types.has(n)).map(n => ({ name: n, hint: 'get_api 可读取完整类型定义' }));
  return { sdkVersion: catalog.sdkVersion, found: true, name,
    kind: type ? 'type' : document ? 'documentation' : entries[0].kind,
    signatures: entries || [], type: type || null, documents: docs, referencedTypes: references,
    usage: entries?.[0].kind === 'instance' ? '这是类型成员；必须先获取该类型的实例，不能直接把类型名作为全局变量使用。' : null,
    examplePolicy: docs.length ? '示例属于整组原始文档，可能演示同组其他函数；请按精确签名选用，不自动改写。' : '此名称没有独立文档示例；只提供真实声明，不生成猜测示例。', caveats };
}
