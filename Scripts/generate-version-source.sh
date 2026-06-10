#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/version.env"

VERSION="${UPDATEBAR_VERSION:?UPDATEBAR_VERSION is required}"
OUT="$ROOT/Sources/UpdateBarCLI/UpdateBarVersion.swift"

cat >"$OUT" <<SWIFT
// Generated from version.env by Scripts/generate-version-source.sh.
enum UpdateBarVersion {
    static let current = "$VERSION"
}
SWIFT
