#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source "$ROOT/version.env"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN_DIR="$TMP_DIR/bin"
mkdir -p "$BIN_DIR"

TAR_LOG="$TMP_DIR/tar.log"
GZIP_LOG="$TMP_DIR/gzip.log"

cat >"$BIN_DIR/swift" <<'SH'
#!/usr/bin/env bash
mkdir -p .build/release
cat >.build/release/updatebar <<'BIN'
#!/usr/bin/env bash
echo updatebar
BIN
chmod 0755 .build/release/updatebar
SH
chmod +x "$BIN_DIR/swift"

cat >"$BIN_DIR/tar" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"${TAR_LOG:?}"
archive=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --version)
      echo "bsdtar 3.5.3 - libarchive"
      exit 0
      ;;
    -cf)
      shift
      archive="${1:-}"
      ;;
  esac
  shift || true
done
if [[ -z "$archive" ]]; then
  echo "missing archive path" >&2
  exit 2
fi
if [[ "$archive" == "-" ]]; then
  printf 'archive\n'
else
  mkdir -p "$(dirname "$archive")"
  printf 'archive\n' >"$archive"
fi
SH
chmod +x "$BIN_DIR/tar"

cat >"$BIN_DIR/gzip" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"${GZIP_LOG:?}"
input=""
for arg in "$@"; do
  case "$arg" in
    -*) ;;
    *) input="$arg" ;;
  esac
done
if [[ -n "$input" ]]; then
  mv "$input" "$input.gz"
else
  cat
fi
SH
chmod +x "$BIN_DIR/gzip"

archive="$(
  TAR_LOG="$TAR_LOG" GZIP_LOG="$GZIP_LOG" PATH="$BIN_DIR:$PATH" SWIFT_BIN="$BIN_DIR/swift" \
    bash Scripts/build-release.sh | tail -n 1
)"

case "$(uname -s)" in
  Darwin) platform="macos" ;;
  Linux) platform="linux" ;;
  *) echo "unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) arch="arm64" ;;
  x86_64|amd64) arch="x86_64" ;;
  *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

expected_archive="$ROOT/dist/updatebar-${UPDATEBAR_VERSION}-${platform}-${arch}.tar.gz"
if [[ "$archive" != "$expected_archive" ]]; then
  echo "unexpected archive path: $archive" >&2
  exit 1
fi

if [[ ! -f "$expected_archive" ]]; then
  echo "release archive was not created" >&2
  exit 1
fi

if ! grep -Fx -- "-cf" "$TAR_LOG" >/dev/null || ! grep -Fx -- "-" "$TAR_LOG" >/dev/null; then
  echo "build-release.sh did not stream tar output to stdout" >&2
  exit 1
fi

if ! grep -Fx -- "-n" "$GZIP_LOG" >/dev/null; then
  echo "build-release.sh did not pass -n to gzip" >&2
  exit 1
fi

if grep -Fx -- "-f" "$GZIP_LOG" >/dev/null; then
  echo "build-release.sh forced gzip on an intermediate tar archive" >&2
  exit 1
fi

echo "release archive behavior ok"
