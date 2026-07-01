#!/usr/bin/env bash
set -euo pipefail

SWIFT_BIN="${SWIFT_BIN:-swift}"

if [[ -n "${UPDATEBAR_BIN:-}" ]]; then
  if [[ ! -x "$UPDATEBAR_BIN" ]]; then
    echo "UPDATEBAR_BIN is not executable: $UPDATEBAR_BIN" >&2
    exit 1
  fi
  exec "$UPDATEBAR_BIN" "$@"
fi

exec "$SWIFT_BIN" run updatebar "$@"
