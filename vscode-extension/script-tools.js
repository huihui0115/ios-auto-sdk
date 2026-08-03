const crypto = require('crypto');
const path = require('path');

let typescript;

function typescriptCompiler() {
  if (!typescript) typescript = require('typescript');
  return typescript;
}

function transpileScript(source, fileName, languageId) {
  if (languageId !== 'typescript') return source;
  const ts = typescriptCompiler();
  const sourceFile = ts.createSourceFile(fileName, source, ts.ScriptTarget.ESNext, true, ts.ScriptKind.TS);
  if (ts.isExternalModule(sourceFile)) {
    throw new Error('TypeScript import/export modules are not supported on the phone yet. Bundle the script into one file before running it.');
  }
  const transpiled = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2017, module: ts.ModuleKind.None },
    fileName,
    reportDiagnostics: true
  });
  const errors = (transpiled.diagnostics || []).filter(diagnostic => diagnostic.category === ts.DiagnosticCategory.Error);
  if (errors.length) throw new Error(ts.flattenDiagnosticMessageText(errors[0].messageText, '\n'));
  return transpiled.outputText;
}

function deployedScriptName(fileName, identity = fileName) {
  const stem = path.basename(fileName, path.extname(fileName)).replace(/[^A-Za-z0-9._-]+/g, '_').slice(0, 88);
  const suffix = crypto.createHash('sha256').update(String(identity)).digest('hex').slice(0, 8);
  return `${stem || 'script'}-${suffix}.js`;
}

function deployedAssetName(fileName, identity = fileName) {
  const originalExtension = path.extname(fileName);
  const extension = originalExtension.toLowerCase();
  if (!['.png', '.jpg', '.jpeg'].includes(extension)) throw new Error('AutoSDK image assets must be PNG or JPEG files.');
  const stem = path.basename(fileName, originalExtension).replace(/[^A-Za-z0-9._-]+/g, '_').slice(0, 84);
  const suffix = crypto.createHash('sha256').update(String(identity)).digest('hex').slice(0, 8);
  return `${stem || 'template'}-${suffix}${extension}`;
}

module.exports = { deployedAssetName, deployedScriptName, transpileScript };
