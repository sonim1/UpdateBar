#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORMULA="$ROOT/Packaging/homebrew/updatebar.rb"
TUI_FORMULA="$ROOT/Packaging/homebrew/updatebar-tui.rb"
CASK_DIR="$ROOT/Packaging/homebrew/Casks"
FORMULA_TOKEN="$(basename "$FORMULA" .rb)"
EXPECTED_CASK_BINARY='  binary "#{appdir}/UpdateBar.app/Contents/Resources/updatebar"'

test_sparkle_bundle_replacement_updates_cli() {
  local temp_dir app_dir next_app cli_link
  temp_dir="$(mktemp -d)"
  trap 'rm -rf -- "$temp_dir"' RETURN

  app_dir="$temp_dir/Applications/UpdateBar.app"
  next_app="$temp_dir/UpdateBar.next.app"
  cli_link="$temp_dir/bin/updatebar"

  mkdir -p "$app_dir/Contents/Resources" "$next_app/Contents/Resources" "${cli_link%/*}"
  printf '#!/usr/bin/env bash\necho 0.0.1\n' > "$app_dir/Contents/Resources/updatebar"
  printf '#!/usr/bin/env bash\necho 0.0.2\n' > "$next_app/Contents/Resources/updatebar"
  chmod +x "$app_dir/Contents/Resources/updatebar" "$next_app/Contents/Resources/updatebar"
  ln -s "$app_dir/Contents/Resources/updatebar" "$cli_link"

  [[ "$("$cli_link")" == "0.0.1" ]] || {
    echo "bundled CLI link did not run the original app version" >&2
    return 1
  }

  mv "$app_dir" "$temp_dir/UpdateBar.previous.app"
  mv "$next_app" "$app_dir"

  [[ "$("$cli_link")" == "0.0.2" ]] || {
    echo "bundled CLI link did not follow the Sparkle replacement app bundle" >&2
    return 1
  }
}

if [[ ! -f "$FORMULA" ]]; then
  echo "missing Homebrew formula: $FORMULA" >&2
  exit 1
fi

if ! grep -Eq 'assert_match[[:space:]]+version\.to_s,' "$FORMULA"; then
  echo "Homebrew formula version matcher must compare a string" >&2
  exit 1
fi

if ! grep -Fq 'assert_predicate bin/"updatebar-tui", :executable?' "$TUI_FORMULA"; then
  echo "Homebrew TUI formula test must not launch the interactive UI" >&2
  exit 1
fi

shopt -s nullglob
casks=("$CASK_DIR"/*.rb)
if [[ ${#casks[@]} -eq 0 ]]; then
  echo "missing Homebrew cask in $CASK_DIR" >&2
  exit 1
fi

for cask in "${casks[@]}"; do
  token="$(awk -F'"' '/^[[:space:]]*cask "/ { print $2; exit }' "$cask")"
  if [[ -z "$token" ]]; then
    echo "missing cask token in $cask" >&2
    exit 1
  fi

  if [[ "$token" == "$FORMULA_TOKEN" ]]; then
    echo "cask token '$token' conflicts with formula token '$FORMULA_TOKEN'" >&2
    echo "use a distinct app cask token so 'brew install updatebar' can link the CLI" >&2
    exit 1
  fi

  if ! grep -Fqx "$EXPECTED_CASK_BINARY" "$cask"; then
    echo "app cask must link the bundled updatebar CLI: $cask" >&2
    exit 1
  fi

  if ! grep -Fq 'UpdateBar-#{version}-macos-arm64.app.tar.gz' "$cask"; then
    echo "current v0.5.0 app cask must remain on its published legacy archive: $cask" >&2
    exit 1
  fi
  if grep -Fq 'UpdateBar-#{version}-macos-arm64.dmg' "$cask"; then
    echo "current v0.5.0 cask must not point at the not-yet-published DMG: $cask" >&2
    exit 1
  fi
done

test_sparkle_bundle_replacement_updates_cli

echo "homebrew packaging ok"
