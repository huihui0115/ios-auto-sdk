#!/usr/bin/env node
// Brand the template app: set your own bundle identifier and display name.
//   node tools/init-project.mjs --bundle-id com.yourname.automation --name "My App"
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function usage() {
  console.error(`Usage:
  node tools/init-project.mjs --bundle-id <com.example.myapp> [--name "My App"]

Brands Examples/TemplateApp so the built IPA installs under your own bundle
identifier and display name. Afterwards run "npm run build" (macOS) or
"npm run build:remote" (Windows/Linux).

  --bundle-id   iOS bundle identifier, e.g. com.yourname.automation (required)
  --name        CFBundleDisplayName shown under the app icon (optional)
  --help        Show this help`);
}

function parseArgs(argv) {
  const args = { bundleId: undefined, name: undefined, help: false };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--help' || token === '-h') { args.help = true; continue; }
    if (!token.startsWith('--')) continue;
    const key = token.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) throw new Error(`Missing value for --${key}`);
    args[key] = argv[++i];
  }
  return args;
}

function escapeXml(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function patch(relativePath, replacements) {
  const filePath = resolve(root, relativePath);
  let text = readFileSync(filePath, 'utf8');
  let applied = 0;
  for (const [from, to] of replacements) {
    if (!text.includes(from)) throw new Error(`${relativePath}: pattern not found: ${from}`);
    text = text.replace(from, () => to);
    applied += 1;
  }
  writeFileSync(filePath, text);
  return applied;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) { usage(); return; }
  if (!args.bundleId || !/^[A-Za-z0-9][A-Za-z0-9.-]{0,254}$/.test(args.bundleId)) {
    throw new Error('--bundle-id must be a bounded iOS bundle identifier, e.g. com.yourname.automation');
  }
  if (args.name !== undefined && (typeof args.name !== 'string' || args.name.length === 0 || args.name.length > 40)) {
    throw new Error('--name must be 1-40 characters.');
  }
  const replacements = [
    ['PRODUCT_BUNDLE_IDENTIFIER: com.example.autosdk.template', `PRODUCT_BUNDLE_IDENTIFIER: ${args.bundleId}`],
  ];
  if (args.name) {
    replacements.push(['<string>AutoSDK Template</string>', `<string>${escapeXml(args.name)}</string>`]);
  }
  const count = patch('Examples/TemplateApp/project.yml', [replacements[0]]);
  if (args.name) patch('Examples/TemplateApp/App/Info.plist', [replacements[1]]);
  console.log(`[init] Updated ${count} setting(s) in Examples/TemplateApp.`);
  console.log(`[init] bundle id : ${args.bundleId}`);
  if (args.name) console.log(`[init] display name: ${args.name}`);
  console.log('[init] Next: npm run build (macOS) or npm run build:remote (Windows/Linux).');
}

try {
  main();
} catch (error) {
  console.error(`[init] ${error.message}`);
  process.exitCode = 1;
}