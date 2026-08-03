import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { parseArgs, replaceOutputFile, validateIPA } from './auto-sdk.mjs';

function zipEntry(name, content = '') {
  const nameBytes = Buffer.from(name, 'utf8');
  const data = Buffer.from(content, 'utf8');
  const local = Buffer.alloc(30 + nameBytes.length + data.length);
  local.writeUInt32LE(0x04034b50, 0);
  local.writeUInt16LE(20, 4);
  local.writeUInt16LE(0, 6);
  local.writeUInt16LE(0, 8);
  local.writeUInt16LE(0, 10);
  local.writeUInt16LE(0, 12);
  local.writeUInt32LE(0, 14);
  local.writeUInt32LE(data.length, 18);
  local.writeUInt32LE(data.length, 22);
  local.writeUInt16LE(nameBytes.length, 26);
  nameBytes.copy(local, 30);
  data.copy(local, 30 + nameBytes.length);
  return { nameBytes, data, local };
}

function zipArchive(entries) {
  const localEntries = entries.map(entry => zipEntry(entry));
  const localData = Buffer.concat(localEntries.map(entry => entry.local));
  let offset = 0;
  const centralEntries = localEntries.map(entry => {
    const central = Buffer.alloc(46 + entry.nameBytes.length);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0, 8);
    central.writeUInt16LE(0, 10);
    central.writeUInt16LE(0, 12);
    central.writeUInt32LE(0, 16);
    central.writeUInt32LE(entry.data.length, 20);
    central.writeUInt32LE(entry.data.length, 24);
    central.writeUInt16LE(entry.nameBytes.length, 28);
    central.writeUInt32LE(offset, 42);
    entry.nameBytes.copy(central, 46);
    offset += entry.local.length;
    return central;
  });
  const central = Buffer.concat(centralEntries);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(localEntries.length, 8);
  end.writeUInt16LE(localEntries.length, 10);
  end.writeUInt32LE(central.length, 12);
  end.writeUInt32LE(localData.length, 16);
  return Buffer.concat([localData, central, end]);
}

test('IPA validation requires a Payload app bundle without reading the whole archive', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'autosdk-ipa-test-'));
  try {
    const validPath = join(directory, 'valid.ipa');
    const invalidPath = join(directory, 'invalid.ipa');
    await writeFile(validPath, zipArchive(['Payload/AutoSDKTemplate.app/', 'Payload/AutoSDKTemplate.app/Info.plist']));
    await writeFile(invalidPath, zipArchive(['README.txt']));
    const result = await validateIPA(validPath);
    assert.equal(result.entries, 2);
    await assert.rejects(validateIPA(invalidPath), /Payload\/\*\.app/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('output replacement leaves the previous IPA recoverable when the commit succeeds', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'autosdk-output-test-'));
  try {
    const source = join(directory, 'source.ipa');
    const destination = join(directory, 'AutoSDKTemplate.ipa');
    await writeFile(source, zipArchive(['Payload/AutoSDKTemplate.app/Info.plist']));
    await writeFile(destination, Buffer.from('old output'));
    await replaceOutputFile(source, destination);
    assert.deepEqual(await readFile(destination), await readFile(source));
    assert.deepEqual((await readdir(directory)).filter(name => /\.(tmp|bak)$/.test(name)), []);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('CLI parsing preserves values and represents missing values explicitly', () => {
  assert.deepEqual(parseArgs(['build-remote', '--output', 'out.ipa', '--timeout', '60']), {
    command: 'build-remote', output: 'out.ipa', timeout: '60'
  });
  assert.equal(parseArgs(['build-remote', '--workflow']).workflow, true);
});
