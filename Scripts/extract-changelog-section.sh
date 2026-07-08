#!/usr/bin/env bash
set -euo pipefail

if [[ "${1-}" == "--help" || "$#" -ne 1 ]]; then
  cat <<'EOF'
Usage: Scripts/extract-changelog-section.sh <version-or-tag>

Print the matching CHANGELOG.md section body for a release tag or version.
Fails when the section is missing or empty.
EOF
  if [[ "${1-}" == "--help" ]]; then
    exit 0
  fi
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1#v}"

awk -v version="$VERSION" '
  /^## / {
    if (found) exit
    heading = $0
    sub(/^##[[:space:]]+/, "", heading)
    split(heading, parts, /[[:space:]]+-[[:space:]]+/)
    if (parts[1] == version) {
      found = 1
      next
    }
  }
  found {
    print
    printed = 1
  }
  END {
    if (!found) {
      printf "missing CHANGELOG.md section for %s\n", version > "/dev/stderr"
      exit 1
    }
    if (!printed) {
      printf "empty CHANGELOG.md section for %s\n", version > "/dev/stderr"
      exit 1
    }
  }
' "$ROOT/CHANGELOG.md"
