#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/version.env"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_ROOT="$TMP_DIR/root"
BIN_DIR="$TMP_DIR/bin"
CODESIGN_LOG="$TMP_DIR/codesign.log"
mkdir -p "$TEST_ROOT/Scripts" "$BIN_DIR"

cp "$ROOT/Scripts/package-app.sh" "$TEST_ROOT/Scripts/package-app.sh"
cp "$ROOT/version.env" "$TEST_ROOT/version.env"

cat >"$TEST_ROOT/Scripts/generate-version-source.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exit 0
SH
chmod +x "$TEST_ROOT/Scripts/generate-version-source.sh"

cat >"$BIN_DIR/uname" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-s" ]]; then
  printf 'Darwin\n'
else
  /usr/bin/uname "$@"
fi
SH

cat >"$BIN_DIR/swift" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p .build/release
case "$*" in
  *"--product updatebar-menubar"*)
    cat > .build/release/updatebar-menubar <<'BIN'
#!/usr/bin/env sh
exit 0
BIN
    chmod 755 .build/release/updatebar-menubar
    ;;
  *"--product updatebar"*)
    cat > .build/release/updatebar <<'BIN'
#!/usr/bin/env sh
if [ "${1:-}" = "--version" ]; then
  echo "fixture"
fi
exit 0
BIN
    chmod 755 .build/release/updatebar
    ;;
  *)
    echo "unexpected swift invocation: $*" >&2
    exit 1
    ;;
esac
SH

cat >"$BIN_DIR/plutil" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exit 0
SH

cat >"$BIN_DIR/codesign" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${CODESIGN_LOG:?}"
SH

chmod +x "$BIN_DIR/uname" "$BIN_DIR/swift" "$BIN_DIR/plutil" "$BIN_DIR/codesign"

(
  cd "$TEST_ROOT"
  env \
    PATH="$BIN_DIR:$PATH" \
    CODESIGN_LOG="$CODESIGN_LOG" \
    UPDATEBAR_SIGN_APP=1 \
    UPDATEBAR_SIGN_IDENTITY="Developer ID Application: Test" \
    UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE=1 \
    bash Scripts/package-app.sh >/dev/null
)

if grep -F -- "--deep" "$CODESIGN_LOG" >/dev/null; then
  echo "package-app signing must not use codesign --deep" >&2
  cat "$CODESIGN_LOG" >&2
  exit 1
fi

if [[ "$(wc -l <"$CODESIGN_LOG" | tr -d ' ')" != "3" ]]; then
  echo "package-app should sign nested binaries and app bundle separately" >&2
  cat "$CODESIGN_LOG" >&2
  exit 1
fi

expected_first="dist/UpdateBar.app/Contents/Resources/updatebar"
expected_second="dist/UpdateBar.app/Contents/MacOS/UpdateBar"
expected_third="dist/UpdateBar.app"

if ! sed -n '1p' "$CODESIGN_LOG" | grep -Fq -- "$expected_first"; then
  echo "first codesign call should sign bundled CLI" >&2
  cat "$CODESIGN_LOG" >&2
  exit 1
fi
if ! sed -n '2p' "$CODESIGN_LOG" | grep -Fq -- "$expected_second"; then
  echo "second codesign call should sign menu bar executable" >&2
  cat "$CODESIGN_LOG" >&2
  exit 1
fi
if ! sed -n '3p' "$CODESIGN_LOG" | grep -Fq -- "$expected_third"; then
  echo "third codesign call should sign app bundle" >&2
  cat "$CODESIGN_LOG" >&2
  exit 1
fi

for required in "--force" "--options runtime" "--timestamp" "--sign Developer ID Application: Test"; do
  if ! grep -Fq -- "$required" "$CODESIGN_LOG"; then
    echo "codesign calls missing required option: $required" >&2
    cat "$CODESIGN_LOG" >&2
    exit 1
  fi
done

echo "package app signing behavior ok"
