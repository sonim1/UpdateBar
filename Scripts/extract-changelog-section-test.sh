#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUTPUT="$(bash Scripts/extract-changelog-section.sh v0.2.0)"

if ! grep -Fq "Removed built-in AI recipe generation" <<<"$OUTPUT"; then
  echo "changelog extractor did not print the requested release section" >&2
  exit 1
fi

if grep -Fq "Initial CLI" <<<"$OUTPUT"; then
  echo "changelog extractor included the next release section" >&2
  exit 1
fi

set +e
MISSING_OUTPUT="$(bash Scripts/extract-changelog-section.sh v999.0.0 2>&1)"
MISSING_STATUS=$?
set -e

if [[ "$MISSING_STATUS" -eq 0 ]]; then
  echo "changelog extractor accepted a missing release section" >&2
  exit 1
fi

if ! grep -Fq "missing CHANGELOG.md section for 999.0.0" <<<"$MISSING_OUTPUT"; then
  echo "changelog extractor did not explain missing release section" >&2
  echo "$MISSING_OUTPUT" >&2
  exit 1
fi

echo "changelog extraction ok"
