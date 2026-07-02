#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/version.env"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_ROOT="$TMP_DIR/root"
BIN_DIR="$TMP_DIR/bin"
TAR_LOG="$TMP_DIR/tar.log"
GZIP_LOG="$TMP_DIR/gzip.log"

mkdir -p "$TEST_ROOT/Scripts" "$TEST_ROOT/dist/UpdateBar.app/Contents" "$BIN_DIR"
cp "$ROOT/Scripts/build-app-archive.sh" "$TEST_ROOT/Scripts/build-app-archive.sh"
cp "$ROOT/version.env" "$TEST_ROOT/version.env"
printf 'fixture\n' >"$TEST_ROOT/dist/UpdateBar.app/Contents/fixture.txt"

cat >"$BIN_DIR/tar" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"${TAR_LOG:?}"

archive=""
expect_archive=0
for arg in "$@"; do
  if [[ "$expect_archive" == "1" ]]; then
    archive="$arg"
    break
  fi
  case "$arg" in
    -f|-cf|-czf)
      expect_archive=1
      ;;
  esac
done

if [[ -z "$archive" ]]; then
  echo "fake tar could not find archive path" >&2
  exit 1
fi

mkdir -p "$(dirname "$archive")"
printf 'archive\n' >"$archive"
SH

cat >"$BIN_DIR/gzip" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"${GZIP_LOG:?}"
input="${*: -1}"
mv "$input" "$input.gz"
SH

cat >"$BIN_DIR/shasum" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

target="${*: -1}"
printf 'fakehash  %s\n' "$target"
SH

chmod +x "$BIN_DIR/tar" "$BIN_DIR/gzip" "$BIN_DIR/shasum"

output="$(
  env PATH="$BIN_DIR:$PATH" TAR_LOG="$TAR_LOG" GZIP_LOG="$GZIP_LOG" \
    "$TEST_ROOT/Scripts/build-app-archive.sh"
)"

expected_archive="$TEST_ROOT/dist/UpdateBar-${UPDATEBAR_VERSION}-macos-arm64.app.tar.gz"

if [[ "$output" != "$expected_archive" ]]; then
  echo "unexpected app archive output path" >&2
  echo "  expected: $expected_archive" >&2
  echo "  actual:   $output" >&2
  exit 1
fi

if [[ ! -f "$expected_archive" ]]; then
  echo "missing app archive: $expected_archive" >&2
  exit 1
fi

if [[ ! -f "${expected_archive}.sha256" ]]; then
  echo "missing app archive checksum: ${expected_archive}.sha256" >&2
  exit 1
fi

if [[ -f "$GZIP_LOG" ]]; then
  echo "build-app-archive.sh invoked gzip; expected direct tar gzip output" >&2
  exit 1
fi

if ! grep -Fx -- "-czf" "$TAR_LOG" >/dev/null; then
  echo "build-app-archive.sh did not pass -czf to tar" >&2
  exit 1
fi

echo "build app archive behavior ok"
