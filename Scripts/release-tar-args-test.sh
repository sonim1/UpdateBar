#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/gnu-tar" <<'SH'
#!/usr/bin/env bash
echo "tar (GNU tar) 1.35"
SH
chmod +x "$TMP_DIR/gnu-tar"

cat >"$TMP_DIR/bsd-tar" <<'SH'
#!/usr/bin/env bash
echo "bsdtar 3.5.3 - libarchive"
SH
chmod +x "$TMP_DIR/bsd-tar"

gnu_args="$(bash Scripts/release-tar-args.sh "$TMP_DIR/gnu-tar" | tr '\n' ' ')"
bsd_args="$(bash Scripts/release-tar-args.sh "$TMP_DIR/bsd-tar" | tr '\n' ' ')"

[[ "$gnu_args" == *"--owner=0"* ]]
[[ "$gnu_args" == *"--group=0"* ]]
[[ "$gnu_args" == *"--numeric-owner"* ]]
[[ "$gnu_args" != *"--uid"* ]]

[[ "$bsd_args" == *"--uid 0"* ]]
[[ "$bsd_args" == *"--gid 0"* ]]
[[ "$bsd_args" == *"--uname root"* ]]
[[ "$bsd_args" == *"--gname wheel"* ]]
[[ "$bsd_args" != *"--owner=0"* ]]

echo "release tar args ok"
