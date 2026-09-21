// Build the VS Code callable catalog from the SAME declarations and docs as the SDK.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { APIS } from './generate-api-reference.mjs';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(path.join(root, 'vscode-extension/package.json'));
const ts = require('typescript');

export function buildCatalog() {
  const file = path.join(root, 'types/autosdk.d.ts');
  const program = ts.createProgram([file], { noLib: true, skipLibCheck: true });
  const checker = program.getTypeChecker(), source = program.getSourceFile(file), result = [];
  const docs = new Map();
  for (const api of APIS) {
    for (const match of api.sig.matchAll(/([\w$]+(?:\.[\w$]+)*)\(/g)) {
      if (!docs.has(match[1])) docs.set(match[1], api);
    }
  }
  function collect(name, type, depth = 0) {
    for (const signature of type.getCallSignatures()) {
      const declaration = signature.getDeclaration();
      const parameters = signature.parameters.map(symbol => {
        const node = symbol.valueDeclaration || symbol.declarations[0];
        const parameterType = checker.getTypeOfSymbolAtLocation(symbol, node);
        const choices = (parameterType.isUnion() ? parameterType.types : [parameterType])
          .filter(type => type.isStringLiteral()).map(type => JSON.stringify(type.value));
        return { name: symbol.name, type: node.type?.getText(source) || 'unknown',
          optional: Boolean(node.questionToken || node.initializer), rest: Boolean(node.dotDotDotToken), choices };
      });
      const api = docs.get(name);
      const doc = ts.displayPartsToString(signature.getDocumentationComment(checker));
      result.push({ name, signature: `${name}${declaration.typeParameters?.length ? '<' + declaration.typeParameters.map(n => n.getText(source)).join(', ') + '>' : ''}(${parameters.map(p => `${p.rest ? '...' : ''}${p.name}${p.optional ? '?' : ''}: ${p.type}`).join(', ')}): ${declaration.type?.getText(source) || 'unknown'}`,
        parameters, title: api?.title || doc || name, documentation: api?.desc || doc || `AutoSDK ${name}`,
        category: api?.cat || '', example: api?.example || '' });
    }
    if (depth >= 2) return;
    for (const property of type.getProperties()) {
      const node = property.valueDeclaration || property.declarations?.[0];
      if (node?.getSourceFile() === source) collect(`${name}.${property.name}`, checker.getTypeOfSymbolAtLocation(property, node), depth + 1);
    }
  }
  for (const statement of source.statements) {
    if (ts.isFunctionDeclaration(statement) && statement.name) {
      // One symbol contains all overloads; visit it once.
      if (!result.some(item => item.name === statement.name.text)) collect(statement.name.text, checker.getTypeAtLocation(statement.name));
    } else if (ts.isVariableStatement(statement)) {
      for (const declaration of statement.declarationList.declarations) collect(declaration.name.getText(source), checker.getTypeAtLocation(declaration.name));
    }
  }
  return result.sort((a, b) => a.name.localeCompare(b.name, 'en'));
}

const output = path.join(root, 'vscode-extension/api-catalog.json');
const generated = JSON.stringify(buildCatalog(), null, 2) + '\n';
if (process.argv.includes('--check')) {
  if (fs.readFileSync(output, 'utf8').replace(/\r\n/g, '\n') !== generated) throw new Error('VS Code API catalog is stale. Run node tools/generate-vscode-api.mjs');
} else {
  fs.writeFileSync(output, generated);
  console.log(`Generated VS Code API catalog (${JSON.parse(generated).length} callable signatures).`);
}
