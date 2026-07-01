import {chmod, mkdir, writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import {describe, expect, it} from 'vitest';
import {resolveUpdateBarBinary} from '../binaryResolver.js';

describe('resolveUpdateBarBinary', () => {
  it('prefers UPDATEBAR_BIN', async () => {
    const root = await tempDir();
    const override = await executable(path.join(root, 'override-updatebar'));
    const bundled = await executable(path.join(root, 'Resources', 'updatebar'));

    await expect(
      resolveUpdateBarBinary({
        env: {UPDATEBAR_BIN: override},
        bundledDirectory: path.dirname(bundled),
        cwd: root,
        defaultPathEntries: []
      })
    ).resolves.toEqual({path: override, source: 'UPDATEBAR_BIN'});
  });

  it('uses bundled before PATH and development fallback', async () => {
    const root = await tempDir();
    const bundled = await executable(path.join(root, 'Resources', 'updatebar'));
    const pathBin = await executable(path.join(root, 'bin', 'updatebar'));
    await executable(path.join(root, '.build', 'debug', 'updatebar'));

    await expect(
      resolveUpdateBarBinary({
        env: {PATH: path.dirname(pathBin)},
        bundledDirectory: path.dirname(bundled),
        cwd: root,
        defaultPathEntries: []
      })
    ).resolves.toEqual({path: bundled, source: 'bundled'});
  });

  it('uses development fallback after PATH misses', async () => {
    const root = await tempDir();
    const dev = await executable(path.join(root, '.build', 'debug', 'updatebar'));

    await expect(
      resolveUpdateBarBinary({env: {}, cwd: root, defaultPathEntries: []})
    ).resolves.toEqual({path: dev, source: 'development_fallback'});
  });

  it('reports missing binaries', async () => {
    const root = await tempDir();

    await expect(
      resolveUpdateBarBinary({env: {}, cwd: root, defaultPathEntries: []})
    ).rejects.toThrow('updatebar binary not found');
  });
});

async function tempDir() {
  return os.tmpdir() + path.sep + `updatebar-tui-${randomUUID()}`;
}

async function executable(file: string) {
  await mkdir(path.dirname(file), {recursive: true});
  await writeFile(file, '#!/bin/sh\nexit 0\n');
  await chmod(file, 0o755);
  return file;
}
