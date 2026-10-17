#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/dist/UpdateBar.app}"
RESULT="${2:-$ROOT/.build/app-e2e-results/$(date -u +%Y%m%dT%H%M%SZ)-$$.xcresult}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "packaged app E2E requires macOS with Xcode and a logged-in desktop session" >&2
  exit 64
fi
if [[ ! -d "$APP" || ! -x "$APP/Contents/MacOS/UpdateBar" || ! -x "$APP/Contents/Resources/updatebar" ]]; then
  echo "a packaged UpdateBar.app with its bundled CLI is required: $APP" >&2
  exit 64
fi
APP="$(cd "$APP" && pwd -P)"
if [[ -e "$RESULT" || -L "$RESULT" ]]; then
  echo "E2E result bundle already exists: $RESULT" >&2
  exit 64
fi
mkdir -p "$(dirname "$RESULT")"
RESULT="$(cd "$(dirname "$RESULT")" && pwd -P)/$(basename "$RESULT")"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "testing packaged app: $APP"
echo "E2E results: $RESULT"
xcodebuild test \
  -project "$ROOT/Tests/PackagedAppE2E/PackagedAppE2E.xcodeproj" \
  -scheme PackagedAppE2E \
  -destination 'platform=macOS' \
  -derivedDataPath "$ROOT/.build/app-e2e" \
  -resultBundlePath "$RESULT" \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  "UPDATEBAR_E2E_APP_PATH=$APP"
