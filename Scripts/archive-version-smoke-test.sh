#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/version.env"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BAD_VERSION="9.9.9"
CLI_ARCHIVE="$TMP_DIR/updatebar-bad-version.tar.gz"
APP_ARCHIVE="$TMP_DIR/UpdateBar-bad-version.app.tar.gz"

mkdir -p "$TMP_DIR/cli"
cat >"$TMP_DIR/cli/updatebar" <<SH
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
  echo "$BAD_VERSION"
fi
exit 0
SH
chmod 0755 "$TMP_DIR/cli/updatebar"
tar -C "$TMP_DIR/cli" -czf "$CLI_ARCHIVE" updatebar

set +e
"$ROOT/Scripts/archive-smoke-test.sh" "$CLI_ARCHIVE" >/dev/null 2>&1
CLI_RC=$?
set -e
if [[ "$CLI_RC" -eq 0 ]]; then
  echo "archive smoke accepted CLI version $BAD_VERSION; expected $UPDATEBAR_VERSION" >&2
  exit 1
fi

APP_DIR="$TMP_DIR/app/UpdateBar.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cat >"$APP_DIR/Contents/MacOS/UpdateBar" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$APP_DIR/Contents/Resources/updatebar" <<SH
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
  echo "$BAD_VERSION"
fi
exit 0
SH
chmod 0755 "$APP_DIR/Contents/MacOS/UpdateBar" "$APP_DIR/Contents/Resources/updatebar"
cat >"$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>$BAD_VERSION</string>
</dict>
</plist>
PLIST
tar -C "$TMP_DIR/app" -czf "$APP_ARCHIVE" UpdateBar.app

set +e
"$ROOT/Scripts/app-archive-smoke-test.sh" "$APP_ARCHIVE" >/dev/null 2>&1
APP_RC=$?
set -e
if [[ "$APP_RC" -eq 0 ]]; then
  echo "app archive smoke accepted app version $BAD_VERSION; expected $UPDATEBAR_VERSION" >&2
  exit 1
fi

echo "archive version smoke ok"
