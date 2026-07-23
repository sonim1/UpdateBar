#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node - "$ROOT/package.json" "$ROOT/package-lock.json" <<'NODE'
const fs = require('node:fs');
const assert = require('node:assert/strict');
const pkg = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const lock = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
assert.equal(pkg.name, 'updatebar-release-tools');
assert.equal(pkg.private, true);
assert.deepEqual(pkg.scripts, undefined, 'release tooling must not have lifecycle scripts');
assert.deepEqual(pkg.devDependencies, {wrangler: '4.112.0'});
assert.deepEqual(pkg.overrides, {sharp: '0.35.3'});
assert.equal(lock.packages[''].name, 'updatebar-release-tools');
assert.equal(lock.packages[''].devDependencies.wrangler, '4.112.0');
const wrangler = lock.packages['node_modules/wrangler'];
assert.equal(wrangler.version, '4.112.0');
assert.match(wrangler.integrity, /^sha512-/);
const sharp = lock.packages['node_modules/sharp'];
assert.equal(sharp.version, '0.35.3');
assert.match(sharp.integrity, /^sha512-/);
NODE

ignore_source="$(
  git -C "$ROOT" check-ignore -v --no-index node_modules/.release-tooling-ignore-probe
)"
case "$ignore_source" in .gitignore:*) ;; *) echo "root node_modules must be ignored" >&2; exit 1 ;; esac
echo "release tooling tests passed"
