#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUALITY_GATE="$ROOT/Scripts/quality-gate.sh"

if ! grep -Fq 'bash Scripts/tui-smoke-test.sh' "$QUALITY_GATE"; then
  echo "quality-gate.sh must run the TUI smoke/package checks" >&2
  exit 1
fi

if grep -Fq 'skipping tui smoke test on non-macOS' "$QUALITY_GATE"; then
  echo "quality-gate.sh must not skip Node/Ink TUI checks on non-macOS" >&2
  exit 1
fi

if ! grep -Fq 'UPDATEBAR_VERIFY_STATIC_ONLY=1 bash Scripts/verify-homebrew-metadata.sh' "$QUALITY_GATE"; then
  echo "quality-gate.sh must verify Homebrew release metadata" >&2
  exit 1
fi

if ! grep -Fq 'bash Scripts/verify-homebrew-metadata-test.sh' "$QUALITY_GATE"; then
  echo "quality-gate.sh must run Homebrew metadata behavior checks" >&2
  exit 1
fi

if ! grep -Fq 'bash Scripts/install-local-smoke-test.sh' "$QUALITY_GATE"; then
  echo "quality-gate.sh must run local installer smoke checks" >&2
  exit 1
fi
