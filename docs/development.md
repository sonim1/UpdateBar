# Development

This guide covers local builds and verification. See
[CONTRIBUTING.md](../CONTRIBUTING.md) for repository rules and
[architecture.md](architecture.md) before changing boundaries between targets.

## Requirements

- Swift 6 toolchain
- Xcode 16 or later with Swift 6 for macOS development
- Node.js 22.13+ (22.x) or 24+ and npm for the optional Ink TUI
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
SPARKLE_PUBLIC_ED_KEY="MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=" Scripts/package-app.sh
Scripts/menubar-smoke-test.sh
open dist/UpdateBar.app
```

The example key is development-only. Local bundles are development artifacts;
public signing, notarization, Sparkle keys, and DMG publication are documented
in [release.md](release.md).

### Packaged App E2E

Use a logged-in macOS desktop session with Xcode 16 or later. Quit an existing
UpdateBar instance before testing; the suite refuses to terminate an app that
was already running. It launches the supplied bundle through XCUITest without
changing its executable, bundle identifier, or production service wiring.

```bash
SPARKLE_PUBLIC_ED_KEY="MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=" UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE=1 bash Scripts/package-app.sh
bash Scripts/app-e2e.sh dist/UpdateBar.app
```

The suite creates temporary profiles and shadows discovered tools with fixture
executables, including a synthetic Homebrew command. It
drives scan, registration, explicit command review, checking, updating, Logs,
and relaunch through the real UI. Read-only calls to the bundled CLI verify
the saved state. Registration alone must not approve or update a tool; an
exit-zero update that leaves the installed version unchanged must fail. A
repeated scan must not silently register or approve anything.

The suite removes its temporary profiles and terminates only its own app
instance. It preserves screenshots, UI trees, registry/state snapshots, command
calls, and history as attachments in the `.xcresult` bundle printed by the
runner. Pass a second argument to choose a new result bundle path; existing
results are never overwritten. The required `macos` CI job runs this against
the exact push/PR head after the quality gate packages the app, then uploads
results for seven days, including failed runs. A UI test failure blocks CI and
the release workflow.

The normal quality gate checks the E2E runner and workflow contracts without
requiring GUI access. The E2E command and the macOS CI job perform the actual
packaged UI tests. These checks do not require or exercise VoiceOver.

See the [runtime and packaged E2E report](runtime-packaged-e2e-2026-10-17.md)
for the covered scenarios, the Brew version regression, and verification limits.

## Run The Ink TUI

The TUI's runtime requirement is `^22.13.0 || >=24.0.0`, matching its locked
runtime and development dependencies. CI checks a strict clean install,
typechecking, tests, lint, build, and package contents on Node 22.13.0 and
the latest Node 22, 24, and 26 releases. Node 20 and 23 are unsupported.

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
