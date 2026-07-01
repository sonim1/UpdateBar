#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT_DIR/tui"

npm ci --no-audit --no-fund
npm run typecheck
npm test
npm run lint
npm run build

PACK_JSON="$(npm pack --dry-run --json)"
PACK_JSON="$PACK_JSON" node <<'NODE'
const packages = JSON.parse(process.env.PACK_JSON ?? '');
const pack = packages[0];
if (!pack) {
  throw new Error('npm pack did not return package metadata');
}

for (const file of pack.files) {
  const path = file.path;
  const allowed = path === 'README.md' || path === 'package.json' || path.startsWith('dist/');
  if (!allowed) {
    throw new Error(`unexpected TUI package file: ${path}`);
  }
}

const index = pack.files.find(file => file.path === 'dist/index.js');
if (!index) {
  throw new Error('dist/index.js missing from TUI package');
}
if ((index.mode & 0o111) === 0) {
  throw new Error('dist/index.js is not executable in TUI package');
}
NODE

echo "tui smoke ok"
