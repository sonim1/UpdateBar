import {constants} from 'node:fs';
import {access} from 'node:fs/promises';
import path from 'node:path';

export type BinarySource =
  | 'UPDATEBAR_BIN'
  | 'bundled'
  | 'PATH'
  | 'development_fallback';

export interface BinaryResolution {
  path: string;
  source: BinarySource;
}

export interface BinaryResolverOptions {
  env?: NodeJS.ProcessEnv;
  bundledDirectory?: string;
  cwd?: string;
  defaultPathEntries?: string[];
}

export class BinaryResolutionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'BinaryResolutionError';
  }
}

export async function resolveUpdateBarBinary(
  options: BinaryResolverOptions = {}
): Promise<BinaryResolution> {
  const env = options.env ?? process.env;
  const cwd = options.cwd ?? process.cwd();
  const defaultPathEntries = options.defaultPathEntries ?? ['/opt/homebrew/bin', '/usr/local/bin'];

  const updateBarBin = await explicitPath(env.UPDATEBAR_BIN, 'UPDATEBAR_BIN');
  if (updateBarBin) return updateBarBin;

  if (options.bundledDirectory) {
    const bundled = path.join(options.bundledDirectory, 'updatebar');
    if (await isExecutable(bundled)) return {path: bundled, source: 'bundled'};
  }

  const pathCandidate = await findOnPath(env.PATH ?? '', defaultPathEntries);
  if (pathCandidate) return {path: pathCandidate, source: 'PATH'};

  const development = await developmentFallback(cwd);
  if (development) return {path: development, source: 'development_fallback'};

  throw new BinaryResolutionError(
    'updatebar binary not found; install updatebar on PATH, run swift build from the UpdateBar project, or set UPDATEBAR_BIN=/path/to/updatebar'
  );
}

async function explicitPath(value: string | undefined, source: BinarySource) {
  if (!value) return undefined;
  if (!(await isExecutable(value))) {
    throw new BinaryResolutionError(`${source} path is not executable: ${value}`);
  }
  return {path: value, source};
}

async function findOnPath(pathValue: string, defaultEntries: string[]) {
  const entries = [...pathValue.split(path.delimiter).filter(Boolean), ...defaultEntries];
  const seen = new Set<string>();
  for (const entry of entries) {
    if (seen.has(entry)) continue;
    seen.add(entry);
    const candidate = path.join(entry, 'updatebar');
    if (await isExecutable(candidate)) return candidate;
  }
  return undefined;
}

async function developmentFallback(cwd: string) {
  const candidates = [
    '.build/debug/updatebar',
    '.build/arm64-apple-macosx/debug/updatebar',
    '.build/x86_64-apple-macosx/debug/updatebar'
  ];
  for (const candidate of candidates) {
    const absolute = path.join(cwd, candidate);
    if (await isExecutable(absolute)) return absolute;
  }
  return undefined;
}

async function isExecutable(candidate: string) {
  try {
    await access(candidate, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}
