#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

TEST_ROOT="$TMP_DIR/root"
BIN_DIR="$TMP_DIR/bin"
INSTALL_DIR="$TMP_DIR/install-bin"
mkdir -p "$TEST_ROOT/Scripts" "$BIN_DIR" "$INSTALL_DIR"
cp "$ROOT/Scripts/install-local.sh" "$TEST_ROOT/Scripts/install-local.sh"

cat > "$BIN_DIR/swift" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"build -c release --product updatebar"*)
    mkdir -p .build/release
    cat > .build/release/updatebar <<'BIN'
#!/usr/bin/env sh
echo "fixture updatebar local"
BIN
    chmod 755 .build/release/updatebar
    ;;
  *)
    echo "unexpected swift invocation: $*" >&2
    exit 1
    ;;
esac
SH
chmod 755 "$BIN_DIR/swift"

output="$(
  env \
    SWIFT_BIN="$BIN_DIR/swift" \
    UPDATEBAR_INSTALL_PREFIX="$INSTALL_DIR" \
    bash "$TEST_ROOT/Scripts/install-local.sh"
)"

if [[ ! -x "$INSTALL_DIR/updatebar" ]]; then
  echo "install-local did not install executable to UPDATEBAR_INSTALL_PREFIX" >&2
  echo "$output" >&2
  exit 1
fi

if [[ "$("$INSTALL_DIR/updatebar")" != "fixture updatebar local" ]]; then
  echo "installed local updatebar output mismatch" >&2
  exit 1
fi

if ! grep -Fq "installed $INSTALL_DIR/updatebar" <<<"$output"; then
  echo "install-local output did not include installed path" >&2
  echo "$output" >&2
  exit 1
fi

help_output="$(bash "$TEST_ROOT/Scripts/install-local.sh" --help)"
if ! grep -Fq "UPDATEBAR_INSTALL_PREFIX" <<<"$help_output"; then
  echo "install-local help should document UPDATEBAR_INSTALL_PREFIX" >&2
  echo "$help_output" >&2
  exit 1
fi

echo "install local smoke ok"
