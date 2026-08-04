#!/usr/bin/env node
/**
 * Synchronizes the AutoSDK version across package.json, AutoSDK.podspec and
 * AutoSDKVersion.m, then prints the git tag command to publish it.
 *
 * Usage: node tools/bump-version.mjs 1.2.0
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const versionArg = process.argv[2];

function fail(message) {
  console.error(`bump-version: ${message}`);
  process.exit(1);
}

if (!versionArg) fail('missing version argument (e.g. node tools/bump-version.mjs 1.2.0)');
if (!/^\d+\.\d+\.\d+$/.test(versionArg)) fail(`invalid version "${versionArg}" (expected x.y.z)`);

const files = {
  package: resolve(root, 'package.json'),
  podspec: resolve(root, 'AutoSDK.podspec'),
  version: resolve(root, 'Sources/AutoSDK/AutoSDKVersion.m'),
  changelog: resolve(root, 'CHANGELOG.md'),
};

const packageJSON = JSON.parse(readFileSync(files.package, 'utf8'));
const oldVersion = packageJSON.version;
if (oldVersion === versionArg) fail(`version is already ${versionArg}`);

packageJSON.version = versionArg;
writeFileSync(files.package, `${JSON.stringify(packageJSON, null, 2)}\n`, 'utf8');

let podspec = readFileSync(files.podspec, 'utf8');
podspec = podspec.replace(/s\.version\s*=\s*'[^']+'/, `s.version          = '${versionArg}'`);
writeFileSync(files.podspec, podspec, 'utf8');

let versionSource = readFileSync(files.version, 'utf8');
versionSource = versionSource.replace(/AutoSDKVersionNumber\s*=\s*[\d.]+/, `AutoSDKVersionNumber = ${versionArg}`);
versionSource = versionSource.replace(/AutoSDKVersionString\[\]\s*=\s*"[^"]+"/, `AutoSDKVersionString[] = "${versionArg}"`);
writeFileSync(files.version, versionSource, 'utf8');

let changelog = readFileSync(files.changelog, 'utf8');
if (changelog.includes(`## [${versionArg}]`)) {
  console.warn(`bump-version: CHANGELOG.md already contains [${versionArg}]; leaving it untouched.`);
} else {
  const today = new Date().toISOString().slice(0, 10);
  const header = `## [${versionArg}] - ${today}\n\n### Added\n\n- Version synchronized to ${versionArg}.\n\n### Fixed\n\n- (fill in)`;
  changelog = changelog.replace('## [Unreleased]', `## [Unreleased]\n\n## [${versionArg}] - ${today}`);
  writeFileSync(files.changelog, changelog, 'utf8');
  console.log(`bump-version: added CHANGELOG.md section [${versionArg}] - ${today}`);
}

console.log(`bump-version: ${oldVersion} -> ${versionArg}`);
console.log('  package.json          updated');
console.log('  AutoSDK.podspec       updated');
console.log('  AutoSDKVersion.m      updated');
console.log('');
console.log('Next steps:');
console.log(`  git add -A && git commit -m "Release ${versionArg}"`);
console.log(`  git tag v${versionArg} && git push origin main v${versionArg}`);