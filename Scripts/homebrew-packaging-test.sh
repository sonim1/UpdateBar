#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORMULA="$ROOT/Packaging/homebrew/updatebar.rb"
CASK_DIR="$ROOT/Packaging/homebrew/Casks"
FORMULA_TOKEN="$(basename "$FORMULA" .rb)"

if [[ ! -f "$FORMULA" ]]; then
  echo "missing Homebrew formula: $FORMULA" >&2
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

  if grep -Eq '^[[:space:]]*binary[[:space:]]' "$cask"; then
    echo "app cask must not link the CLI binary: $cask" >&2
    exit 1
  fi
done

echo "homebrew packaging ok"
