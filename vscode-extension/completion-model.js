'use strict';

const CALL_PATTERN = /([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)\(([^()]*)\)/g;

function callableSignatures(group) {
  const signatures = [];
  let inheritedNamespace = '';
  let match;
  while ((match = CALL_PATTERN.exec(String(group || ''))) !== null) {
    let name = match[1];
    const separator = name.lastIndexOf('.');
    if (separator >= 0) {
      inheritedNamespace = name.slice(0, separator);
    } else if (inheritedNamespace) {
      name = `${inheritedNamespace}.${name}`;
    }
    signatures.push(`${name}(${match[2]})`);
  }
  return signatures;
}

function namespaceBeforeCursor(prefix) {
  return String(prefix || '').match(/\b([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)\.$/)?.[1] || '';
}

function namespaceOf(signature) {
  const name = signature.slice(0, signature.indexOf('('));
  const separator = name.lastIndexOf('.');
  return separator >= 0 ? name.slice(0, separator) : '';
}

function escapeSnippetDefault(value) {
  return value.replace(/([\\}$])/g, '\\$1');
}

function snippetForSignature(signature, namespace) {
  const opening = signature.indexOf('(');
  const name = signature.slice(0, opening);
  const insertionName = namespace && name.startsWith(`${namespace}.`)
    ? name.slice(namespace.length + 1)
    : name;
  const args = signature.slice(opening + 1, -1).trim();
  if (!args) return `${insertionName}()`;
  const placeholders = args.split(/\s*,\s*/).map((arg, index) =>
    `\${${index + 1}:${escapeSnippetDefault(arg)}}`
  );
  return `${insertionName}(${placeholders.join(', ')})`;
}

function completionEntries(entries, prefix, aliases = {}) {
  const requestedNamespace = namespaceBeforeCursor(prefix);
  const sourceNamespace = aliases[requestedNamespace] || requestedNamespace;
  const results = [];
  const seen = new Set();
  for (const [group, documentation] of entries) {
    for (const sourceSignature of callableSignatures(group)) {
      if (requestedNamespace && namespaceOf(sourceSignature) !== sourceNamespace) continue;
      const signature = requestedNamespace && requestedNamespace !== sourceNamespace
        ? `${requestedNamespace}${sourceSignature.slice(sourceNamespace.length)}`
        : sourceSignature;
      if (seen.has(signature)) continue;
      seen.add(signature);
      results.push({
        documentation,
        insertText: snippetForSignature(signature, requestedNamespace),
        label: signature.slice(0, signature.indexOf('(')),
        signature
      });
    }
  }
  return results;
}

module.exports = { callableSignatures, completionEntries, namespaceBeforeCursor, snippetForSignature };
