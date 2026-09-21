#!/usr/bin/env node
// Same authorities as the HTML and VS Code catalog. No handwritten second API list.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { APIS, CATEGORIES } from './generate-api-reference.mjs';

const root = path.resolve(import.meta.dirname, '..');
const out = path.join(root, 'mcp-server/data');
const inputs = ['types/autosdk.d.ts', 'tools/generate-api-reference.mjs',
  'tools/generate-mcp-data.mjs', 'package.json'];
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const hash = value => createHash('sha256').update(value).digest('hex');
const version = JSON.parse(read('package.json')).version;

export function checkMcpSources() {
  const manifest = JSON.parse(read('mcp-server/data/manifest.json'));
  if (manifest.sdkVersion !== version) throw new Error('MCP SDK version is stale');
  for (const file of inputs) {
    if (manifest.sources[file] !== hash(read(file))) throw new Error(`MCP source changed: ${file}; run npm run mcp:generate`);
  }
  for (const file of ['catalog.json', 'autosdk.d.ts']) {
    if (manifest.outputs[file] !== hash(read(`mcp-server/data/${file}`))) throw new Error(`MCP generated data changed: ${file}`);
  }
  const pkg = JSON.parse(read('mcp-server/package.json'));
  const lock = JSON.parse(read('mcp-server/npm-shrinkwrap.json'));
  if ([pkg.version, lock.version, lock.packages[''].version].some(v => v !== version)) throw new Error('MCP package/lock version mismatch');
}

async function generate() {
  const require = createRequire(path.join(root, 'mcp-server/package.json'));
  const ts = require('typescript');
  const file = path.join(root, 'types/autosdk.d.ts');
  const options = { noLib: true, skipLibCheck: true };
  const host = ts.createCompilerHost(options);
  // Type declaration text must produce identical data on Windows and Linux/macOS.
  const getSourceFile = host.getSourceFile.bind(host);
  host.getSourceFile = (name, target, ...args) => path.resolve(name) === file
    ? ts.createSourceFile(file, read('types/autosdk.d.ts'), target, true)
    : getSourceFile(name, target, ...args);
  const program = ts.createProgram([file], options, host);
  const source = program.getSourceFile(file), checker = program.getTypeChecker();
  const documents = APIS.map((api, index) => ({ id: `doc:${index + 1}`, ...api }));
  const exactDocs = new Map();
  for (const doc of documents) {
    for (const match of doc.sig.matchAll(/([\w$]+(?:\.[\w$]+)*)\(/g)) {
      const list = exactDocs.get(match[1]) || [];
      list.push(doc.id); exactDocs.set(match[1], list);
    }
  }
  const entries = [], seen = new Set(), declarationDocs = new Map();
  function collect(name, type, kind, depth = 0) {
    if (seen.has(name)) return;
    seen.add(name);
    for (const signature of type.getCallSignatures()) {
      const declaration = signature.getDeclaration();
      if (!declaration || declaration.getSourceFile() !== source) continue;
      const parameters = signature.parameters.map(symbol => {
        const node = symbol.valueDeclaration || symbol.declarations[0];
        return { name: symbol.name, type: node.type?.getText(source) || 'unknown',
          optional: Boolean(node.questionToken || node.initializer), rest: Boolean(node.dotDotDotToken) };
      });
      const docIds = exactDocs.get(name) || [];
      if (docIds.length) declarationDocs.set(declaration, [...new Set([...(declarationDocs.get(declaration) || []), ...docIds])]);
      entries.push({ name, kind, signature: `${name}${declaration.typeParameters?.length ? '<' + declaration.typeParameters.map(n => n.getText(source)).join(', ') + '>' : ''}(${parameters.map(p => `${p.rest ? '...' : ''}${p.name}${p.optional ? '?' : ''}: ${p.type}`).join(', ')}): ${declaration.type?.getText(source) || 'unknown'}`,
        parameters, returns: declaration.type?.getText(source) || 'unknown',
        notes: ts.displayPartsToString(signature.getDocumentationComment(checker)), docIds, declaration });
    }
    if (depth >= 2) return;
    for (const property of type.getProperties()) {
      const node = property.valueDeclaration || property.declarations?.[0];
      if (node?.getSourceFile() === source) collect(`${name}.${property.name}`, checker.getTypeOfSymbolAtLocation(property, node), kind, depth + 1);
    }
  }
  const types = [];
  for (const statement of source.statements) {
    if (ts.isFunctionDeclaration(statement) && statement.name) collect(statement.name.text, checker.getTypeAtLocation(statement.name), 'global');
    if (ts.isVariableStatement(statement)) {
      for (const declaration of statement.declarationList.declarations) collect(declaration.name.getText(source), checker.getTypeAtLocation(declaration.name), 'global');
    }
    if (ts.isInterfaceDeclaration(statement) || ts.isTypeAliasDeclaration(statement)) {
      types.push({ name: statement.name.text, declaration: statement.getText(source) });
      if (ts.isInterfaceDeclaration(statement)) collect(statement.name.text, checker.getTypeAtLocation(statement.name), 'instance');
    }
  }
  const callables = entries.map(({ declaration, ...entry }) => ({ ...entry,
    docIds: entry.docIds.length ? entry.docIds : declarationDocs.get(declaration) || []
  })).sort((a, b) => a.name.localeCompare(b.name, 'en'));
  const catalog = JSON.stringify({ sdkVersion: version, categories: CATEGORIES, callables, types, documents }, null, 2) + '\n';
  const outputs = { 'catalog.json': catalog, 'autosdk.d.ts': read('types/autosdk.d.ts') };
  outputs['manifest.json'] = JSON.stringify({ sdkVersion: version,
    sources: Object.fromEntries(inputs.map(file => [file, hash(read(file))])),
    outputs: Object.fromEntries(Object.entries(outputs).map(([file, contents]) => [file, hash(contents)]))
  }, null, 2) + '\n';
  if (process.argv.includes('--check')) {
    for (const [file, contents] of Object.entries(outputs)) {
      if (read(`mcp-server/data/${file}`) !== contents) throw new Error(`MCP data stale: ${file}; run npm run mcp:generate`);
    }
    checkMcpSources();
  } else {
    fs.mkdirSync(out, { recursive: true });
    for (const [file, contents] of Object.entries(outputs)) fs.writeFileSync(path.join(out, file), contents);
    console.log(`Generated MCP reference: ${callables.length} signatures, ${types.length} types, ${documents.length} documentation groups.`);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.join(root, 'tools/generate-mcp-data.mjs')) {
  if (process.argv.includes('--check-sources')) checkMcpSources();
  else await generate();
}
