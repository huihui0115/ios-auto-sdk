// Submitted text is NEVER evaluated, transpiled for execution, imported, or written.
import { parentPort, workerData } from 'node:worker_threads';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import ts from 'typescript';

const require = createRequire(import.meta.url);
const libDir = path.dirname(require.resolve('typescript/lib/typescript.js'));
// Only trusted, fixed package assets are read. The compiler host below has no disk fallback.
const files = new Map();
for (const name of fs.readdirSync(libDir)) {
  if (/^lib\.[a-z\d.]+\.d\.ts$/.test(name)) files.set('/' + name, fs.readFileSync(path.join(libDir, name), 'utf8'));
}
files.set('/autosdk.d.ts', fs.readFileSync(new URL('./data/autosdk.d.ts', import.meta.url), 'utf8'));
const { code, language } = workerData;
const scriptName = language === 'typescript' ? '/script.ts' : '/script.js';
files.set(scriptName, code);
const options = { noEmit: true, allowJs: true, checkJs: true, strictNullChecks: true,
  skipLibCheck: true, target: ts.ScriptTarget.ES2017, module: ts.ModuleKind.None,
  lib: ['lib.es2017.d.ts'], types: [], maxNodeModuleJsDepth: 0, noErrorTruncation: false };
const normalize = name => path.posix.normalize(name.replace(/\\/g, '/'));
const host = {
  getSourceFile(name, target) { const text = files.get(normalize(name)); return text === undefined ? undefined : ts.createSourceFile(name, text, target, true); },
  getDefaultLibFileName: () => '/lib.es2017.d.ts', getCurrentDirectory: () => '/',
  getCanonicalFileName: name => normalize(name), useCaseSensitiveFileNames: () => true,
  getNewLine: () => '\n', writeFile() { throw new Error('Writing is disabled'); },
  fileExists: name => files.has(normalize(name)), readFile: name => files.get(normalize(name)),
  directoryExists: name => name === '/', getDirectories: () => [], readDirectory: () => [],
  resolveModuleNames: names => names.map(() => undefined),
  resolveTypeReferenceDirectives: names => names.map(() => undefined)
};
const program = ts.createProgram([scriptName, '/autosdk.d.ts'], options, host);
const source = program.getSourceFile(scriptName), issues = [];
function issue(code, message, start = 0, severity = 'error') {
  const position = source.getLineAndCharacterOfPosition(start);
  issues.push({ code, severity, line: position.line + 1, column: position.character + 1, message });
}
// Directives may suppress TypeScript's own diagnostics; do not report those scripts as clean.
const scanner = ts.createScanner(ts.ScriptTarget.ES2017, false, ts.LanguageVariant.Standard, code);
for (let token = scanner.scan(); token !== ts.SyntaxKind.EndOfFileToken; token = scanner.scan()) {
  if ([ts.SyntaxKind.SingleLineCommentTrivia, ts.SyntaxKind.MultiLineCommentTrivia].includes(token) &&
      /@ts-(?:ignore|nocheck|expect-error)\b/.test(scanner.getTokenText())) {
    issue('CHECK_SUPPRESSED', '禁止使用 @ts-ignore / @ts-nocheck / @ts-expect-error 隐藏检查结果。', scanner.getTokenPos());
  }
}
if (source.referencedFiles.length || source.typeReferenceDirectives.length || source.libReferenceDirectives.length || source.hasNoDefaultLib) {
  issue('EXTERNAL_REFERENCE', '不允许 triple-slash reference；只使用本包的 AutoSDK 与 ES2017 声明。');
}
const checker = program.getTypeChecker();
function visit(node) {
  if (ts.isImportDeclaration(node) || ts.isImportEqualsDeclaration(node) || ts.isExportDeclaration(node) ||
      ts.isExportAssignment(node) || node.modifiers?.some(m => m.kind === ts.SyntaxKind.ExportKeyword) ||
      (ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword)) {
    issue('MODULE_UNSUPPORTED', '手机 JavaScriptCore 脚本不支持 import/export/模块加载。', node.getStart(source));
  }
  if (ts.isAsExpression(node) || ts.isTypeAssertionExpression(node) || node.kind === ts.SyntaxKind.AnyKeyword) {
    issue('TYPE_ESCAPE', 'any / 类型断言可能绕过 API 校验，请核对真实声明。', node.getStart(source), 'warning');
  }
  if (ts.isCallExpression(node)) {
    if (checker.getTypeAtLocation(node.expression).flags & ts.TypeFlags.Any) {
      issue('UNCHECKED_CALL', '该调用的类型是 any，无法确认目标函数和参数；不要把静态通过当作 API 已存在。', node.getStart(source), 'warning');
    }
    if (ts.isIdentifier(node.expression) && ['eval', 'Function'].includes(node.expression.text)) {
      issue('DYNAMIC_CODE', '动态生成的代码无法静态核对，请使用显式 API 调用。', node.getStart(source), 'warning');
    }
  }
  ts.forEachChild(node, visit);
}
visit(source);
for (const diagnostic of ts.getPreEmitDiagnostics(program)) {
  if (diagnostic.file && diagnostic.file.fileName !== scriptName) continue;
  issue(`TS${diagnostic.code}`, ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n').slice(0, 1200), diagnostic.start || 0,
    diagnostic.category === ts.DiagnosticCategory.Error ? 'error' : 'warning');
}
const errors = issues.filter(i => i.severity === 'error').length;
// Do not let many earlier warnings hide the actual error in a truncated response.
issues.sort((a, b) => (a.severity === 'error' ? 0 : 1) - (b.severity === 'error' ? 0 : 1) || a.line - b.line || a.column - b.column);
parentPort.postMessage({ valid: errors === 0, status: errors ? 'errors' : issues.length ? 'warnings' : 'passed',
  errors, warnings: issues.length - errors, diagnostics: issues.slice(0, 50), truncated: issues.length > 50,
  executed: false, language, requiresTranspilation: language === 'typescript' });
