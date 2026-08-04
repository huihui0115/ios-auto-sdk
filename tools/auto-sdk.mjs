#!/usr/bin/env node
import { existsSync, mkdirSync, statSync } from 'node:fs';
import { copyFile, mkdtemp, open, readdir, rename, rm } from 'node:fs/promises';
import { dirname, resolve, basename } from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { tmpdir } from 'node:os';

const MAX_CAPTURE_BYTES = 8 * 1024 * 1024;
const MAX_ARTIFACT_ENTRIES = 10000;
const MAX_IPA_BYTES = 512 * 1024 * 1024;
const MAX_CENTRAL_DIRECTORY_BYTES = 16 * 1024 * 1024;
const ZIP_END_OF_CENTRAL_DIRECTORY = 0x06054b50;
const ZIP_CENTRAL_DIRECTORY_ENTRY = 0x02014b50;

function usage() {
  console.error(`Usage:
  auto-sdk build --project <path> --bundle-id <id> --output <ipa> [--scheme <name>] [--configuration <name>]
  auto-sdk build-remote --output <ipa> [--repo <owner/name>] [--workflow <name-or-file>] [--ref <branch>] [--artifact <name>] [--timeout <seconds>]
  NOTE: local builds require macOS with Xcode. On Windows/Linux use: auto-sdk build-remote`);
}

function parseArgs(argv) {
  const result = { command: argv[0] };
  for (let i = 1; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) result[key] = true;
    else result[key] = argv[++i];
  }
  return result;
}

function optionText(value, label, maximumLength = 256) {
  if (value === undefined || value === null) return undefined;
  if (value === true) throw new Error(`${label} requires a value.`);
  const text = String(value);
  if (!text || text.length > maximumLength || text.includes('\0') || text.startsWith('--')) {
    throw new Error(`${label} is empty, too long, or starts with an option marker.`);
  }
  return text;
}

function required(args, key) {
  if (!args[key] || args[key] === true) {
    throw new Error(`Missing --${key}`);
  }
  return args[key];
}

function run(command, args, cwd) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, { cwd, stdio: 'inherit', shell: false, windowsHide: true });
    child.once('error', reject);
    child.once('exit', code => code === 0 ? resolvePromise() : reject(new Error(`${command} exited with ${code}`)));
  });
}

function runCapture(command, args, cwd) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'], shell: false });
    let stdout = '';
    let stderr = '';
    let capturedBytes = 0;
    let settled = false;
    const fail = error => {
      if (settled) return;
      settled = true;
      try { child.kill(); } catch (_) { /* process may already have exited */ }
      reject(error);
    };
    const capture = (kind, data) => {
      if (settled) return;
      const bytes = Buffer.isBuffer(data) ? data.length : Buffer.byteLength(String(data), 'utf8');
      capturedBytes += bytes;
      if (capturedBytes > MAX_CAPTURE_BYTES) {
        fail(new Error(`${command} produced more than ${MAX_CAPTURE_BYTES} bytes of output.`));
        return;
      }
      if (kind === 'stdout') stdout += data.toString();
      else stderr += data.toString();
    };
    child.stdout.on('data', data => capture('stdout', data));
    child.stderr.on('data', data => capture('stderr', data));
    child.once('error', fail);
    child.once('close', code => {
      if (settled) return;
      settled = true;
      if (code === 0) resolvePromise({ stdout, stderr });
      else reject(new Error(`${command} exited with ${code}: ${(stderr || stdout).trim()}`));
    });
  });
}

function delay(milliseconds) {
  return new Promise(resolvePromise => setTimeout(resolvePromise, milliseconds));
}

async function listWorkflowRuns(repo, workflow, cwd) {
  const result = await runCapture('gh', [
    'run', 'list', '--repo', repo, '--workflow', workflow,
    '--event', 'workflow_dispatch', '--limit', '50',
    '--json', 'databaseId,status,conclusion,createdAt,displayTitle'
  ], cwd);
  try {
    const runs = JSON.parse(result.stdout);
    return Array.isArray(runs) ? runs : [];
  } catch (error) {
    throw new Error(`GitHub CLI returned invalid run data: ${error.message}`);
  }
}

async function repositoryForBuild(value, cwd) {
  let repo = value;
  if (!repo) {
    let result;
    try {
      result = await runCapture('gh', ['repo', 'view', '--json', 'nameWithOwner'], cwd);
      const parsed = JSON.parse(result.stdout);
      repo = parsed?.nameWithOwner;
    } catch (error) {
      throw new Error(`Unable to detect the GitHub repository. Pass --repo owner/name. ${error.message}`);
    }
  }
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo)) {
    throw new Error('--repo must be in owner/name form using GitHub-safe characters');
  }
  return repo;
}

async function findWorkflowRun(repo, workflow, requestId, startedAt, cwd) {
  const runs = await listWorkflowRuns(repo, workflow, cwd);
  const candidates = runs
    .filter(runInfo => (runInfo.displayTitle || '').includes(requestId))
    .sort((left, right) => Number(right.databaseId || 0) - Number(left.databaseId || 0));
  void startedAt;
  return candidates[0] || null;
}

async function findIPA(root) {
  const pending = [root];
  let examinedEntries = 0;
  while (pending.length > 0) {
    const directory = pending.pop();
    const entries = await readdir(directory, { withFileTypes: true });
    for (const entry of entries) {
      examinedEntries += 1;
      if (examinedEntries > MAX_ARTIFACT_ENTRIES) {
        throw new Error(`Downloaded artifact contains more than ${MAX_ARTIFACT_ENTRIES} entries.`);
      }
      const fullPath = resolve(directory, entry.name);
      if (entry.isDirectory()) pending.push(fullPath);
      else if (entry.name.toLowerCase().endsWith('.ipa')) return fullPath;
    }
  }
  return null;
}

async function validateIPA(filePath) {
  const handle = await open(filePath, 'r');
  try {
    const fileStats = await handle.stat();
    if (!fileStats.isFile() || fileStats.size < 22 || fileStats.size > MAX_IPA_BYTES) {
      throw new Error(`IPA must be a regular file between 22 bytes and ${MAX_IPA_BYTES} bytes.`);
    }
    const tailLength = Math.min(fileStats.size, 22 + 0xffff);
    const tail = Buffer.alloc(tailLength);
    await handle.read(tail, 0, tail.length, fileStats.size - tail.length);
    let endOffset = -1;
    for (let index = tail.length - 22; index >= 0; index -= 1) {
      if (tail.readUInt32LE(index) !== ZIP_END_OF_CENTRAL_DIRECTORY) continue;
      const commentLength = tail.readUInt16LE(index + 20);
      if (index + 22 + commentLength === tail.length) { endOffset = index; break; }
    }
    if (endOffset < 0) throw new Error('IPA is not a valid ZIP archive (missing end record).');
    const centralSize = tail.readUInt32LE(endOffset + 12);
    const centralOffset = tail.readUInt32LE(endOffset + 16);
    if (centralSize === 0xffffffff || centralOffset === 0xffffffff || centralSize > MAX_CENTRAL_DIRECTORY_BYTES ||
        centralOffset + centralSize > fileStats.size) {
      throw new Error('IPA ZIP central directory is invalid or too large.');
    }
    const central = Buffer.alloc(centralSize);
    await handle.read(central, 0, central.length, centralOffset);
    let offset = 0;
    let entries = 0;
    let hasApp = false;
    while (offset < central.length) {
      if (central.length - offset < 46 || central.readUInt32LE(offset) !== ZIP_CENTRAL_DIRECTORY_ENTRY) {
        throw new Error('IPA ZIP central directory contains a malformed entry.');
      }
      const nameLength = central.readUInt16LE(offset + 28);
      const extraLength = central.readUInt16LE(offset + 30);
      const commentLength = central.readUInt16LE(offset + 32);
      const entryLength = 46 + nameLength + extraLength + commentLength;
      if (entryLength > central.length - offset) throw new Error('IPA ZIP entry exceeds its central directory.');
      const name = central.toString('utf8', offset + 46, offset + 46 + nameLength);
      if (/^Payload\/[^/]+\.app\/(?:$|Info\.plist$)/i.test(name)) hasApp = true;
      entries += 1;
      if (entries > MAX_ARTIFACT_ENTRIES) {
        throw new Error(`IPA ZIP contains more than ${MAX_ARTIFACT_ENTRIES} entries.`);
      }
      offset += entryLength;
    }
    if (entries === 0 || !hasApp) throw new Error('IPA ZIP does not contain a Payload/*.app bundle.');
    return { bytes: fileStats.size, entries };
  } finally {
    await handle.close();
  }
}

async function replaceOutputFile(source, destination) {
  const parent = dirname(destination);
  const temporary = resolve(parent, `.${basename(destination)}.${randomUUID()}.tmp`);
  const backup = resolve(parent, `.${basename(destination)}.${randomUUID()}.bak`);
  await copyFile(source, temporary);
  let movedOld = false;
  try {
    if (existsSync(destination)) {
      await rename(destination, backup);
      movedOld = true;
    }
    await rename(temporary, destination);
    if (movedOld) {
      try { await rm(backup, { force: true }); } catch (_) { /* stale backup is recoverable and harmless */ }
    }
  } catch (error) {
    try { await rm(temporary, { force: true }); } catch (_) { /* best effort cleanup */ }
    if (movedOld && !existsSync(destination) && existsSync(backup)) {
      try { await rename(backup, destination); } catch (_) { /* report original error */ }
    }
    throw error;
  }
}

async function waitForWorkflowRun(repo, runId, deadline, cwd) {
  while (Date.now() < deadline) {
    const result = await runCapture('gh', [
      'run', 'view', runId, '--repo', repo,
      '--json', 'status,conclusion'
    ], cwd);
    let state;
    try {
      state = JSON.parse(result.stdout);
    } catch (error) {
      throw new Error(`GitHub CLI returned invalid workflow status: ${error.message}`);
    }
    if (state.status === 'completed') {
      if (state.conclusion !== 'success') {
        throw new Error(`GitHub Actions run ${runId} finished with conclusion '${state.conclusion || 'unknown'}'.`);
      }
      return;
    }
    await delay(5000);
  }
  throw new Error(`Timed out waiting for GitHub Actions run ${runId}.`);
}

async function buildRemote(args) {
  const output = resolve(required(args, 'output'));
  if (existsSync(output) && statSync(output).isDirectory()) throw new Error('--output must be a file path, not a directory.');
  const workflow = optionText(args.workflow || 'Build TrollStore IPA', '--workflow');
  const ref = args.ref === undefined ? undefined : optionText(args.ref, '--ref');
  const artifact = optionText(args.artifact || 'AutoSDKTemplate-TrollStore', '--artifact');
  const requestedTimeout = Number(args.timeout);
  const timeoutSeconds = Number.isFinite(requestedTimeout)
    ? Math.min(21600, Math.max(60, requestedTimeout))
    : 1800;
  const cwd = resolve(args.cwd || process.cwd());
  const repo = await repositoryForBuild(args.repo, cwd);
  mkdirSync(resolve(output, '..'), { recursive: true });

  const requestId = randomUUID();
  const dispatchArgs = ['workflow', 'run', workflow, '--repo', repo, '--field', `requestId=${requestId}`];
  if (ref) dispatchArgs.push('--ref', ref);
  const startedAt = Date.now();
  console.log(`[auto-sdk] Dispatching ${workflow} for ${repo} (${requestId})`);
  await run('gh', dispatchArgs, cwd);

  const deadline = startedAt + timeoutSeconds * 1000;
  let runInfo = null;
  while (Date.now() < deadline && !runInfo) {
    try {
      runInfo = await findWorkflowRun(repo, workflow, requestId, startedAt, cwd);
    } catch (error) {
      if (Date.now() >= deadline) throw error;
    }
    if (!runInfo) await delay(3000);
  }
  if (!runInfo) throw new Error(`Timed out waiting for the dispatched workflow run (${requestId}).`);
  const runNumber = Number(runInfo.databaseId);
  if (!Number.isSafeInteger(runNumber) || runNumber <= 0) {
    throw new Error('GitHub CLI returned a workflow run without a valid database ID.');
  }
  const runId = String(runNumber);
  console.log(`[auto-sdk] Waiting for GitHub Actions run ${runId}`);
  await waitForWorkflowRun(repo, runId, deadline, cwd);

  const downloadDir = await mkdtemp(resolve(tmpdir(), 'autosdk-artifact-'));
  try {
    await run('gh', ['run', 'download', runId, '--repo', repo, '--name', artifact, '--dir', downloadDir], cwd);
    const ipa = await findIPA(downloadDir);
    if (!ipa || !existsSync(ipa)) throw new Error(`Artifact '${artifact}' did not contain an IPA file.`);
    await validateIPA(ipa);
    const outputParent = dirname(output);
    mkdirSync(outputParent, { recursive: true });
    await replaceOutputFile(ipa, output);
    await validateIPA(output);
    console.log(`[auto-sdk] IPA downloaded to ${output}`);
  } finally {
    await rm(downloadDir, { recursive: true, force: true });
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.command || args.command === '--help' || args.command === '-h' || args.command === 'help') {
    usage();
    process.exitCode = args.command ? 0 : 2;
    return;
  }
  if (args.command === 'build-remote') {
    await buildRemote(args);
    return;
  }
  if (args.command !== 'build') {
    usage();
    process.exitCode = 2;
    return;
  }
  if (process.platform !== 'darwin') {
    throw new Error('Local builds require macOS with Xcode. On Windows or Linux use: auto-sdk build-remote');
  }
  const project = resolve(required(args, 'project'));
  const output = resolve(required(args, 'output'));
  if (existsSync(output) && statSync(output).isDirectory()) throw new Error('--output must be a file path, not a directory.');
  const bundleId = required(args, 'bundle-id');
  if (!/^[A-Za-z0-9][A-Za-z0-9.-]{0,254}$/.test(bundleId)) {
    throw new Error('--bundle-id must be a bounded iOS bundle identifier.');
  }
  const scheme = optionText(args.scheme || 'AutoSDK', '--scheme', 128);
  const configuration = optionText(args.configuration || 'Release', '--configuration', 128);
  if (/[\\/]/.test(scheme)) throw new Error('--scheme must not contain path separators.');
  if (!existsSync(project)) throw new Error(`Project does not exist: ${project}`);
  if (!project.endsWith('.xcodeproj') && !project.endsWith('.xcworkspace')) {
    throw new Error('--project must point to an .xcodeproj or .xcworkspace');
  }
  mkdirSync(resolve(output, '..'), { recursive: true });
  const archive = resolve(output, '..', `${scheme}.xcarchive`);
  const projectFlag = project.endsWith('.xcworkspace') ? '-workspace' : '-project';
  const projectName = project.split(/[\\/]/).pop().replace(/\.(xcodeproj|xcworkspace)$/, '');
  const sdkRoot = resolve(fileURLToPath(new URL('.', import.meta.url)), '..');
  console.log(`[auto-sdk] Building ${bundleId} (${configuration})`);
  await run('xcodebuild', [projectFlag, project, '-scheme', scheme, '-configuration', configuration,
    '-archivePath', archive, 'archive', 'CODE_SIGNING_ALLOWED=YES', `PRODUCT_BUNDLE_IDENTIFIER=${bundleId}`], sdkRoot);
  await run('xcodebuild', ['-exportArchive', '-archivePath', archive, '-exportPath', resolve(output, '..'),
    '-exportOptionsPlist', resolve(sdkRoot, 'tools', 'ExportOptions.plist')], sdkRoot);
  const generated = resolve(output, '..', `${projectName}.ipa`);
  if (generated !== output && existsSync(generated)) {
    await validateIPA(generated);
    await replaceOutputFile(generated, output);
  }
  if (!existsSync(output) || statSync(output).size === 0) {
    throw new Error(`xcodebuild completed without producing a non-empty IPA at ${output}`);
  }
  await validateIPA(output);
  console.log(`[auto-sdk] IPA exported to ${output}`);
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) {
  main().catch(error => {
    console.error(`[auto-sdk] ${error.message}`);
    process.exitCode = 1;
  });
}

export { findIPA, parseArgs, replaceOutputFile, validateIPA };
