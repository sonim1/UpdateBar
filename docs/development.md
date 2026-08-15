# Development

This guide covers local builds and verification. See
[CONTRIBUTING.md](../CONTRIBUTING.md) for repository rules and
[architecture.md](architecture.md) before changing boundaries between targets.

## Requirements

- Swift 6 toolchain
- Xcode 16 or later with Swift 6 for macOS development
- Node.js and npm for the optional Ink TUI
- Apple Silicon macOS for packaging the distributed app DMG

The Swift package supports macOS 13 or later. CLI tests and release builds also
run on Linux x86_64.

## Build And Test

Build all Swift targets and run the test suite:

```bash
swift build
swift test
```

Run the repository quality gate before submitting a change:

```bash
Scripts/quality-gate.sh
```

On macOS, the gate prefers `/Applications/Xcode.app` when available. If SwiftPM
cannot find `XCTest`, select Xcode explicitly:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

See [troubleshooting.md](troubleshooting.md) for Xcode license, toolchain, and
binary resolution failures.

## Run The CLI

```bash
swift build --product updatebar
.build/debug/updatebar --version
.build/debug/updatebar doctor
```

Use an isolated data directory for manual development when you do not want to
read or modify your normal UpdateBar state:

```bash
UPDATEBAR_HOME=/tmp/updatebar-dev .build/debug/updatebar status
```

## Run The Menu Bar App

Build and run the executable directly:

```bash
swift build --product updatebar
swift build --product updatebar-menubar
UPDATEBAR_BIN=$PWD/.build/debug/updatebar .build/debug/updatebar-menubar
```

Build the local app bundle and run its smoke test:

```bash
Scripts/package-app.sh
Scripts/menubar-smoke-test.sh
open dist/UpdateBar.app
```

Local bundles are development artifacts. Public signing, notarization, and DMG
publication are documented in [release.md](release.md).

## Run The Ink TUI

```bash
swift build --product updatebar
npm --prefix tui install
npm --prefix tui run build
UPDATEBAR_BIN=$PWD/.build/debug/updatebar UPDATEBAR_TUI=$PWD/tui/dist/index.js .build/debug/updatebar tui
```

For focused TUI checks:

```bash
npm --prefix tui run typecheck
npm --prefix tui run lint
npm --prefix tui run test
```

See the [TUI README](../tui/README.md) for additional setup and runtime details.

## Focused Verification

Use the smallest relevant check during development, then run the full quality
gate before handoff.

```bash
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swift test
npm --prefix tui run typecheck
npm --prefix tui run lint
npm --prefix tui run test
npm --prefix tui run build
```

Packaging and release metadata changes also require:

```bash
bash Scripts/homebrew-packaging-test.sh
UPDATEBAR_VERIFY_STATIC_ONLY=1 bash Scripts/verify-homebrew-metadata.sh
```
