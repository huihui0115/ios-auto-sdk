#!/usr/bin/env node
// AutoSDK environment diagnostics.
//   npm run doctor
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const failures = [];
const warnings = [];

function sh(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8', windowsHide: true });
  return { ok: result.status === 0, stdout: (result.stdout || '').trim(), stderr: (result.stderr || '').trim() };
}

function report(label, ok, detail, warn = false) {
  const bucket = warn ? warnings : failures;
  console.log(`${ok ? 'PASS' : (warn ? 'WARN' : 'FAIL')}  ${label}${detail ? ' — ' + detail : ''}`);
  if (!ok) bucket.push(label);
}

const nodeMajor = Number(process.versions.node.split('.')[0]);
report('Node.js version >= 22', nodeMajor >= 22, process.version);

const isGitRepo = sh('git', ['rev-parse', '--is-inside-work-tree']);
report('Git repository', isGitRepo.ok, isGitRepo.stdout || isGitRepo.stderr);
if (isGitRepo.ok) {
  const remote = sh('git', ['config', '--get', 'remote.origin.url']);
  report('Git remote origin', remote.ok, remote.stdout || '(missing)');
} else {
  failures.push('Git repository');
}

const packageJson = (() => {
  try { return JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8')); }
  catch { return {}; }
})();
const requiredScripts = ['build', 'build:remote', 'verify', 'test', 'init', 'doctor'];
const missingScripts = requiredScripts.filter(name => !packageJson.scripts || !packageJson.scripts[name]);
report('npm scripts (build/build:remote/verify/test/init/doctor)', missingScripts.length === 0,
  missingScripts.length ? 'missing: ' + missingScripts.join(', ') : undefined);

const ghVersion = sh('gh', ['--version']);
report('GitHub CLI (gh) installed', ghVersion.ok, ghVersion.ok ? ghVersion.stdout.split('\n')[0] : 'run: winget install GitHub.cli');
if (ghVersion.ok) {
  const auth = sh('gh', ['auth', 'status']);
  report('gh authenticated', auth.ok, auth.ok ? 'logged in' : 'run: gh auth login (needed for build-remote/release)', true);
}

const iproxyCommand = process.platform === 'win32' ? 'where.exe' : 'which';
const iproxy = sh(iproxyCommand, ['iproxy']);
report('iproxy available (USB tunnel)', iproxy.ok, iproxy.ok ? 'found in PATH' : 'install libimobiledevice (brew / winget)', true);

const syntaxFiles = [
  'tools/auto-sdk.mjs', 'tools/debug-client.mjs', 'tools/verify.mjs',
  'tools/init-project.mjs', 'tools/doctor.mjs', 'tools/bump-version.mjs',
  'tools/generate-api-reference.mjs', 'tools/generate-devdocs.mjs',
];
const syntaxFailures = syntaxFiles.filter(path => {
  const result = spawnSync(process.execPath, ['--check', resolve(root, path)], { encoding: 'utf8', windowsHide: true });
  return result.status !== 0;
});
report('Node syntax check (tools/*.mjs)', syntaxFailures.length === 0,
  syntaxFailures.length ? 'failed: ' + syntaxFailures.join(', ') : undefined);

const requiredDocs = [
  'README.md', 'docs/index.html', 'docs/QUICK_START.md',
  'types/autosdk.d.ts', 'Examples/TemplateApp/App/Info.plist', 'Examples/TemplateApp/project.yml',
];
const missingDocs = requiredDocs.filter(path => !existsSync(resolve(root, path)));
report('Docs and templates present', missingDocs.length === 0,
  missingDocs.length ? 'missing: ' + missingDocs.join(', ') : undefined);

const { readdirSync } = await import('node:fs');
const extensionDir = resolve(root, 'vscode-extension');
const extensionVersion = JSON.parse(readFileSync(resolve(extensionDir, 'package.json'), 'utf8')).version;
const vsixFiles = existsSync(extensionDir) ? readdirSync(extensionDir).filter(name => name.endsWith('.vsix')) : [];
report('VS Code extension packaged (*.vsix)', vsixFiles.length > 0,
  vsixFiles.length ? vsixFiles.map(name => name.replace('autosdk-', '')).join(', ') : `run: npx @vscode/vsce package --out vscode-extension/autosdk-vscode-${extensionVersion}.vsix`, true);

const tags = sh('git', ['tag', '--list', 'v*']);
report('Version tag exists (v*)', tags.ok && tags.stdout.length > 0, tags.stdout ? tags.stdout.split('\n')[0] : 'run: npm run bump', true);

const distDir = resolve(root, 'dist');
const ipaFiles = existsSync(distDir) ? readdirSync(distDir).filter(name => name.endsWith('.ipa')) : [];
report('Local IPA build (dist/*.ipa)', ipaFiles.length > 0,
  ipaFiles.length ? ipaFiles.join(', ') : 'run: npm run build:remote', true);

console.log('');
if (failures.length === 0 && warnings.length === 0) {
  console.log('AutoSDK doctor: all checks passed.');
} else if (failures.length === 0) {
  console.log(`AutoSDK doctor: ${warnings.length} warning(s) — optional improvements above.`);
  process.exitCode = 0;
} else {
  console.log(`AutoSDK doctor: ${failures.length} problem(s) found — fix the FAIL items first.`);
  process.exitCode = 1;
}
