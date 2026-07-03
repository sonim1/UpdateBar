#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

INSTALLER_URL="https://raw.githubusercontent.com/sonim1/UpdateBar/main/Scripts/install-release.sh"
if ! grep -Fq "curl -fsSL $INSTALLER_URL | bash" README.md; then
  echo "README is missing the GitHub one-line install command" >&2
  exit 1
fi

case "$(uname -s)" in
  Darwin) PLATFORM=macos ;;
  Linux) PLATFORM=linux ;;
  *) echo "skipping install-release smoke on unsupported OS: $(uname -s)"; exit 0 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH=arm64 ;;
  x86_64|amd64) ARCH=x86_64 ;;
  *) echo "skipping install-release smoke on unsupported architecture: $(uname -m)"; exit 0 ;;
esac

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

FIXTURES="$TMP_DIR/fixtures"
PAYLOAD="$TMP_DIR/payload"
FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FIXTURES" "$PAYLOAD" "$FAKE_BIN"

cat > "$PAYLOAD/updatebar" <<'SH'
#!/usr/bin/env sh
echo "fixture updatebar 9.9.9"
SH
chmod 755 "$PAYLOAD/updatebar"

ASSET_NAME="updatebar-9.9.9-${PLATFORM}-${ARCH}.tar.gz"
ASSET_URL="https://example.test/releases/${ASSET_NAME}"
tar -czf "$FIXTURES/$ASSET_NAME" -C "$PAYLOAD" updatebar

if command -v shasum >/dev/null 2>&1; then
  SHA="$(shasum -a 256 "$FIXTURES/$ASSET_NAME" | awk '{print $1}')"
else
  SHA="$(sha256sum "$FIXTURES/$ASSET_NAME" | awk '{print $1}')"
fi
printf '%s  %s\n' "$SHA" "$ASSET_NAME" > "$FIXTURES/${ASSET_NAME}.sha256"

cat > "$FIXTURES/release.json" <<JSON
{
  "tag_name": "v9.9.9",
  "assets": [
    { "browser_download_url": "https://example.test/releases/UpdateBar-9.9.9-${PLATFORM}-${ARCH}.app.tar.gz" },
    { "browser_download_url": "https://example.test/releases/updatebar-9.9.9-${PLATFORM}-unsupported.tar.gz" },
    { "browser_download_url": "${ASSET_URL}" }
  ]
}
JSON

cat > "$FAKE_BIN/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

output=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      output="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

fixtures="${UPDATEBAR_FAKE_RELEASE_FIXTURES:?}"
case "$url" in
  https://api.github.com/repos/sonim1/UpdateBar/releases/latest)
    file="$fixtures/release.json"
    ;;
  https://api.github.com/repos/sonim1/UpdateBar/releases/tags/v9.9.9)
    file="$fixtures/release.json"
    ;;
  https://example.test/releases/updatebar-9.9.9-*.tar.gz)
    file="$fixtures/${url##*/}"
    ;;
  https://example.test/releases/updatebar-9.9.9-*.tar.gz.sha256)
    file="$fixtures/${url##*/}"
    ;;
  *)
    echo "unexpected curl URL: $url" >&2
    exit 22
    ;;
esac

if [[ -n "$output" ]]; then
  cp "$file" "$output"
else
  cat "$file"
fi
SH
chmod 755 "$FAKE_BIN/curl"

assert_installed() {
  local prefix="$1"
  local output="$2"

  if [[ ! -x "$prefix/updatebar" ]]; then
    echo "installed updatebar is missing or not executable: $prefix/updatebar" >&2
    exit 1
  fi

  local actual
  actual="$("$prefix/updatebar" --version)"
  if [[ "$actual" != "fixture updatebar 9.9.9" ]]; then
    echo "installed updatebar output mismatch: $actual" >&2
    exit 1
  fi

  if ! grep -Fq "Installed updatebar to ${prefix}/updatebar" "$output"; then
    echo "install output did not include installed path" >&2
    cat "$output" >&2
    exit 1
  fi
}

run_install() {
  local tag="$1"
  local prefix="$2"
  local output="$TMP_DIR/install-${tag:-latest}.out"

  if [[ -n "$tag" ]]; then
    env \
      PATH="$FAKE_BIN:$PATH" \
      UPDATEBAR_FAKE_RELEASE_FIXTURES="$FIXTURES" \
      UPDATEBAR_INSTALL_PREFIX="$prefix" \
      UPDATEBAR_GITHUB_REPO="sonim1/UpdateBar" \
      bash Scripts/install-release.sh "$tag" > "$output"
  else
    env \
      PATH="$FAKE_BIN:$PATH" \
      UPDATEBAR_FAKE_RELEASE_FIXTURES="$FIXTURES" \
      UPDATEBAR_INSTALL_PREFIX="$prefix" \
      UPDATEBAR_GITHUB_REPO="sonim1/UpdateBar" \
      bash Scripts/install-release.sh > "$output"
  fi

  assert_installed "$prefix" "$output"
}

run_piped_install() {
  local tag="$1"
  local prefix="$2"
  local output="$TMP_DIR/install-piped-${tag:-latest}.out"

  if [[ -n "$tag" ]]; then
    env \
      PATH="$FAKE_BIN:$PATH" \
      UPDATEBAR_FAKE_RELEASE_FIXTURES="$FIXTURES" \
      UPDATEBAR_INSTALL_PREFIX="$prefix" \
      UPDATEBAR_GITHUB_REPO="sonim1/UpdateBar" \
      bash -s -- "$tag" < Scripts/install-release.sh > "$output"
  else
    env \
      PATH="$FAKE_BIN:$PATH" \
      UPDATEBAR_FAKE_RELEASE_FIXTURES="$FIXTURES" \
      UPDATEBAR_INSTALL_PREFIX="$prefix" \
      UPDATEBAR_GITHUB_REPO="sonim1/UpdateBar" \
      bash < Scripts/install-release.sh > "$output"
  fi

  assert_installed "$prefix" "$output"
}

run_missing_checksum_tool_fails_clearly() {
  local limited_bin="$TMP_DIR/no-checksum-bin"
  local output="$TMP_DIR/install-no-checksum.out"
  mkdir -p "$limited_bin"
  for tool in awk bash cat cp head mktemp rm uname; do
    ln -sf "$(command -v "$tool")" "$limited_bin/$tool"
  done
  cp "$FAKE_BIN/curl" "$limited_bin/curl"
  chmod 755 "$limited_bin/curl"

  set +e
  env \
    PATH="$limited_bin" \
    UPDATEBAR_FAKE_RELEASE_FIXTURES="$FIXTURES" \
    UPDATEBAR_INSTALL_PREFIX="$TMP_DIR/install-no-checksum" \
    UPDATEBAR_GITHUB_REPO="sonim1/UpdateBar" \
    /bin/bash Scripts/install-release.sh > "$output" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    echo "install-release succeeded without shasum or sha256sum" >&2
    cat "$output" >&2
    exit 1
  fi
  if ! grep -Fq "shasum or sha256sum is required" "$output"; then
    echo "install-release missing checksum-tool error was not clear" >&2
    cat "$output" >&2
    exit 1
  fi
}

run_install "" "$TMP_DIR/install-latest"
run_install "v9.9.9" "$TMP_DIR/install-tag"
run_piped_install "" "$TMP_DIR/install-piped-latest"
run_piped_install "v9.9.9" "$TMP_DIR/install-piped-tag"
run_missing_checksum_tool_fails_clearly

echo "install release smoke ok"
