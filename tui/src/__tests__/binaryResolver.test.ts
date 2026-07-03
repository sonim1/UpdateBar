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

  it('resolves relative UPDATEBAR_BIN from the configured cwd', async () => {
    const root = await tempDir();
    const override = await executable(path.join(root, 'bin', 'updatebar'));

    await expect(
      resolveUpdateBarBinary({
        env: {UPDATEBAR_BIN: 'bin/updatebar'},
        cwd: root,
        defaultPathEntries: []
      })
    ).resolves.toEqual({path: override, source: 'UPDATEBAR_BIN'});
  });

  it('uses configured path after UPDATEBAR_BIN and before bundled binaries', async () => {
    const root = await tempDir();
    const configured = await executable(path.join(root, 'configured-updatebar'));
    const bundled = await executable(path.join(root, 'Resources', 'updatebar'));

    await expect(
      resolveUpdateBarBinary({
        env: {},
        configuredPath: configured,
        bundledDirectory: path.dirname(bundled),
        cwd: root,
        defaultPathEntries: []
      })
    ).resolves.toEqual({path: configured, source: 'configured'});
  });

  it('resolves relative configured paths from the configured cwd', async () => {
    const root = await tempDir();
    const configured = await executable(path.join(root, 'bin', 'configured-updatebar'));

    await expect(
      resolveUpdateBarBinary({
        env: {},
        configuredPath: 'bin/configured-updatebar',
        cwd: root,
        defaultPathEntries: []
      })
    ).resolves.toEqual({path: configured, source: 'configured'});
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

  it('ignores relative PATH entries', async () => {
    const root = await tempDir();
    await executable(path.join(root, 'updatebar'));
    const originalCwd = process.cwd();
    try {
      process.chdir(root);
      await expect(
        resolveUpdateBarBinary({
          env: {PATH: '.'},
          cwd: root,
          defaultPathEntries: []
        })
      ).rejects.toThrow(/updatebar binary not found/);
    } finally {
      process.chdir(originalCwd);
    }
  });

  it('ignores executable directories on PATH', async () => {
    const root = await tempDir();
    await mkdir(path.join(root, 'bin', 'updatebar'), {recursive: true});
    await chmod(path.join(root, 'bin', 'updatebar'), 0o755);

    await expect(
      resolveUpdateBarBinary({
        env: {PATH: path.join(root, 'bin')},
        cwd: root,
        defaultPathEntries: []
      })
    ).rejects.toThrow(/updatebar binary not found/);
  });

  it('uses development fallback after PATH misses', async () => {
    const root = await tempDir();
    const dev = await executable(path.join(root, '.build', 'debug', 'updatebar'));

    await expect(
      resolveUpdateBarBinary({env: {}, cwd: root, defaultPathEntries: []})
    ).resolves.toEqual({path: dev, source: 'development_fallback'});
  });

  it('reports missing binaries with setup guidance', async () => {
    const root = await tempDir();

    await expect(
      resolveUpdateBarBinary({env: {}, cwd: root, defaultPathEntries: []})
    ).rejects.toThrow(/updatebar binary not found.*swift build.*set UPDATEBAR_BIN/);
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
