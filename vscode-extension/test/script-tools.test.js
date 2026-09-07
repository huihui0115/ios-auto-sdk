const assert = require('node:assert/strict');
const test = require('node:test');
const { deployedAssetName, deployedScriptName, editorScript, transpileScript } = require('../script-tools');

test('JavaScript passthrough does not load the TypeScript compiler', () => {
  const typescriptPath = require.resolve('typescript');
  assert.equal(require.cache[typescriptPath], undefined);
  assert.equal(transpileScript('const value = 7;', 'script.js', 'javascript'), 'const value = 7;');
  assert.equal(require.cache[typescriptPath], undefined);
});

test('TypeScript annotations are transpiled for JavaScriptCore', () => {
  const output = transpileScript('const value: number = 42; value;', 'example.ts', 'typescript');
  assert.match(output, /const value = 42/);
  assert.doesNotMatch(output, /: number/);
});

test('TypeScript modules are rejected instead of emitting require or exports', () => {
  assert.throws(
    () => transpileScript("import { value } from './value'; value;", 'example.ts', 'typescript'),
    /import\/export modules are not supported/
  );
});

test('deployed names remain readable and distinguish same basenames', () => {
  const first = deployedScriptName('login.ts', 'file:///one/login.ts');
  const second = deployedScriptName('login.ts', 'file:///two/login.ts');
  assert.match(first, /^login-[a-f0-9]{8}\.js$/);
  assert.notEqual(first, second);
});

test('deployed image names preserve supported extensions and avoid collisions', () => {
  const first = deployedAssetName('登录 按钮.PNG', 'file:///one/button.png');
  const second = deployedAssetName('登录 按钮.PNG', 'file:///two/button.png');
  assert.match(first, /^_+-[a-f0-9]{8}\.png$/);
  assert.notEqual(first, second);
  assert.throws(() => deployedAssetName('template.webp'), /PNG or JPEG/);
});

function fakeEditor(languageId = 'javascript') {
  const selection = { isEmpty: false, start: { line: 4 } };
  return { selection, selections: [selection], document: {
    languageId, fileName: 'example.js', uri: { toString: () => 'file:///example.js' },
    getText: range => range ? 'log("selection");' : 'log("whole file");'
  } };
}

test('selected-code run sends only selected text with its source location', () => {
  const editor = fakeEditor();
  assert.equal(editorScript(editor, true).source, 'log("selection");');
  assert.equal(editorScript(editor, true).name, 'example.js (selection, line 5)');
  assert.equal(editorScript(editor).source, 'log("whole file");');
});

test('empty and multiple selections never fall back to running a whole file', () => {
  const editor = fakeEditor(); editor.selection.isEmpty = true;
  assert.throws(() => editorScript(editor, true), /Select one code block/);
  editor.selection.isEmpty = false; editor.selections.push(editor.selection);
  assert.throws(() => editorScript(editor, true), /Select one code block/);
  editor.selections.pop(); editor.document.getText = () => '   ';
  assert.throws(() => editorScript(editor, true), /empty/);
});

test('selected TypeScript uses the same compiler and module restrictions', () => {
  const editor = fakeEditor('typescript');
  editor.document.getText = () => 'const n: number = 1; log(n);';
  assert.match(editorScript(editor, true).source, /const n = 1/);
  editor.document.getText = () => 'import x from "module";';
  assert.throws(() => editorScript(editor, true), /import\/export/);
});
