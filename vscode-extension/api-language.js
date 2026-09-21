'use strict';
const ts = require('typescript');
const catalog = require('./api-catalog.json');
const escapeDefault = value => value.replace(/([\\}$])/g, '\\$1');

function snippet(entry, namespace = '') {
  const name = namespace ? entry.name.slice(namespace.length + 1) : entry.name;
  // Optional/rest parameters are discoverable in signature help, not invalid '?'/ellipsis source.
  const required = entry.parameters.filter(p => !p.optional && !p.rest);
  return `${name}(${required.map((parameter, index) => {
    const choices = parameter.choices.length ? parameter.choices : parameter.type === 'boolean' ? ['true', 'false'] : [];
    if (choices.length) return '${' + (index + 1) + '|' + choices.map(v => v.replace(/[\\,|]/g, '\\$&')).join(',') + '|}';
    const value = parameter.type === 'string' ? '""' : parameter.type === 'number' ? '0' : parameter.type.includes('=>') ? '() => {}' : parameter.name;
    return '${' + (index + 1) + ':' + escapeDefault(value) + '}';
  }).join(', ')})`;
}

function parse(text) {
  if (text.length > 1024 * 1024) return undefined;
  return ts.createSourceFile('script.ts', text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
}

function nonCode(source, offset) {
  const scanner = ts.createScanner(ts.ScriptTarget.Latest, false, ts.LanguageVariant.Standard, source.text);
  let token;
  while ((token = scanner.scan()) !== ts.SyntaxKind.EndOfFileToken) {
    const start = scanner.getTokenPos(), end = scanner.getTextPos();
    if (start >= offset) break;
    const comment = token === ts.SyntaxKind.SingleLineCommentTrivia || token === ts.SyntaxKind.MultiLineCommentTrivia;
    const literal = token === ts.SyntaxKind.StringLiteral || token === ts.SyntaxKind.NoSubstitutionTemplateLiteral;
    if (offset < end && (comment || literal)) return true;
    if (offset === end && (token === ts.SyntaxKind.SingleLineCommentTrivia || (comment || literal) && scanner.isUnterminated())) return true;
  }
  let blocked = false;
  function visit(node) {
    if (offset > node.getStart(source) && offset < node.end &&
        (ts.isStringLiteralLike(node) || ts.isRegularExpressionLiteral(node) || ts.isTemplateExpression(node))) blocked = true;
    if (!blocked && offset >= node.pos && offset <= node.end) ts.forEachChild(node, visit);
  }
  visit(source);
  return blocked;
}

function completions(text, offset = text.length) {
  const source = parse(text);
  if (!source || nonCode(source, offset)) return [];
  const match = text.slice(0, offset).match(/([\w$]+(?:\?*\.[\w$]*)*)$/);
  const prefix = match?.[1] || '';
  const normalized = prefix.replace(/\?\./g, '.');
  const dot = normalized.lastIndexOf('.');
  const namespace = dot < 0 ? '' : normalized.slice(0, dot);
  const typed = normalized.slice(dot + 1);
  const suffix = text.slice(offset).match(/^[\w$]*/)[0];
  const hasArguments = /^\s*\(/.test(text.slice(offset + suffix.length));
  // Do not complete properties of an arbitrary call result or a computed receiver.
  if (!namespace && /[.)\]]\s*\.\s*[\w$]*$/.test(text.slice(0, offset))) return [];
  return catalog.filter(entry => {
    const separator = entry.name.lastIndexOf('.');
    return (!namespace || entry.name.slice(0, separator) === namespace) &&
      entry.name.slice(namespace ? namespace.length + 1 : 0).startsWith(typed);
  }).map(entry => ({ ...entry, insertText: hasArguments ? entry.name.slice(namespace ? namespace.length + 1 : 0) : snippet(entry, namespace),
    replaceLength: typed.length, replaceAfterLength: suffix.length,
    filterText: namespace ? entry.name.slice(namespace.length + 1) : entry.name }));
}

function callHelp(text, offset) {
  // Trailing whitespace is outside an incomplete AST call's end; keep it for lexical checks.
  const source = parse(text);
  if (!source || nonCode(source, offset)) return undefined;
  const cursor = text.slice(0, offset).trimEnd().length;
  let call;
  function visit(node) {
    if (ts.isCallExpression(node) && node.arguments.pos <= cursor && cursor <= node.end &&
        (text[node.end - 1] !== ')' || cursor < node.end)) call = node;
    if (cursor >= node.pos && cursor <= node.end) ts.forEachChild(node, visit);
  }
  visit(source);
  if (!call) return undefined;
  const name = call.expression.getText(source).replace(/\?\./g, '.');
  const entries = catalog.filter(entry => entry.name === name);
  if (!entries.length) return undefined;
  // Count syntax-list separators, not text commas (regexes/templates/generics can contain commas).
  const list = call.getChildren(source).find(node => node.kind === ts.SyntaxKind.SyntaxList &&
    node.pos === call.arguments.pos && node.end === call.arguments.end);
  const parameter = list?.getChildren(source).filter(node => node.kind === ts.SyntaxKind.CommaToken && node.end <= offset).length || 0;
  return { entries, parameter };
}

function hoverEntry(text, offset) {
  const source = parse(text);
  if (!source || nonCode(source, offset)) return undefined;
  let name;
  function visit(node) {
    if (offset >= node.getStart(source) && offset < node.end) {
      if (ts.isPropertyAccessExpression(node) || ts.isIdentifier(node)) name = node.getText(source).replace(/\?\./g, '.');
      if (!catalog.some(entry => entry.name === name)) ts.forEachChild(node, visit);
    }
  }
  visit(source);
  return catalog.find(entry => entry.name === name);
}

module.exports = { catalog, snippet, completions, callHelp, hoverEntry };
