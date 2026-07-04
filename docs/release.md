# Release

Release checklist:

```bash
swift build
swift build -c release --product updatebar
swift build -c release --product updatebar-menubar
swift test
npm --prefix tui test
npm --prefix tui run typecheck
npm --prefix tui run lint
bash Scripts/smoke-test.sh
rm -f dist/*.tar.gz dist/*.sha256
Scripts/build-release.sh
bash Scripts/archive-version-smoke-test.sh
bash Scripts/archive-smoke-test.sh
bash Scripts/install-release-smoke-test.sh
bash Scripts/homebrew-packaging-test.sh
Scripts/package-app.sh
bash Scripts/build-app-archive.sh
bash Scripts/app-archive-smoke-test.sh
bash Scripts/install-release.sh --help
bash Scripts/verify-homebrew-metadata.sh
```

On macOS, `Scripts/quality-gate.sh` prefers `/Applications/Xcode.app` when it is
available so `swift test` can find `XCTest`. Set `DEVELOPER_DIR` explicitly if
you need a different toolchain.

Build a local release archive:

```bash
Scripts/build-release.sh
```

`Scripts/build-release.sh` regenerates `Sources/UpdateBarCLI/UpdateBarVersion.swift`
from `version.env` before compiling. If `version.env` changes during development, run
`Scripts/generate-version-source.sh` before tests.

The CLI archive is intentionally unsigned in M2. `Scripts/build-release.sh`
normalizes archive metadata and uses `gzip -n`; the final SHA is still the SHA
of the exact binary built by that runner and toolchain. By default, the binary
is kept unstripped to preserve runtime compatibility; if you need stripping in
a known-good toolchain, run with `UPDATEBAR_STRIP_BINARY=1`. Set
`UPDATEBAR_AD_HOC_CODESIGN=1` only for local experiments. Future signed app
distribution will use Developer ID signing, notarization, and stapling.

The Swift CLI release archive is intentionally independent from Node and Ink.
`Scripts/build-release.sh`, `Scripts/archive-smoke-test.sh`, and the Homebrew
formula install only `updatebar`.

Archive smoke test:

```bash
bash Scripts/archive-smoke-test.sh
```

Edge-case CLI checks:

```bash
Scripts/e2e-edgecases.sh
```

This runs an intentionally strict import/add/validate/remove/check flow against a temp home
directory and asserts expected success/failure exit codes for risky paths (including
`config` unknown key handling, duplicate prevention, and missing-item removal failures).
Use a prebuilt binary if needed:

```bash
UPDATEBAR_BIN=.build/debug/updatebar Scripts/e2e-edgecases.sh
```

Local unsigned app package:

```bash
Scripts/package-app.sh
bash Scripts/build-app-archive.sh
bash Scripts/app-archive-smoke-test.sh
```

The app packaging script creates `dist/UpdateBar.app` with the menu bar executable
in `Contents/MacOS/UpdateBar` and the CLI in `Contents/Resources/updatebar`.
Tagged macOS releases also upload an unsigned
`UpdateBar-<version>-macos-arm64.app.tar.gz` archive. Signing/notarization are not
part of the CLI release.

For future signed releases, `Scripts/package-app.sh` also supports optional
environment-based signing/notarization when `UPDATEBAR_SIGN_APP=1` and
`UPDATEBAR_NOTARIZE_APP=1` are set. Provide these when running on macOS with
Apple tooling:

- `UPDATEBAR_SIGN_IDENTITY`: Developer ID application identity string
- `UPDATEBAR_NOTARYTOOL_KEYCHAIN_PROFILE`: keychain profile name for `xcrun notarytool`
- optional `UPDATEBAR_SIGN_ENTITLEMENTS_FILE`: entitlements file path for `codesign`

When signing is enabled, the script signs inside-out: bundled CLI first, menu bar
executable second, app bundle last. It intentionally does not use
`codesign --deep`.

The app bundle does not currently include the Ink TUI. The `Open TUI` menu item
prefers launching `UPDATEBAR_BIN tui` when the bundled CLI is available, and
falls back to `updatebar-tui` from the user's `PATH`.

Ink TUI packaging:

```bash
Scripts/tui-smoke-test.sh
```

Release identity:

- GitHub repo slug: `sonim1/UpdateBar`.
- Published `v0.2.0` prebuilt CLI archives cover Apple Silicon macOS and Linux
  x86_64. Release tags also publish an unsigned Apple Silicon macOS app archive.
- Homebrew tap target: `sonim1/homebrew-tap`.
- Formula source lives in `Packaging/homebrew/updatebar.rb`; copy it to the tap as
  `Formula/updatebar.rb` when publishing a Homebrew release. The formula SHA must
  come from the final uploaded release asset's `.sha256`, not from a later local
  rebuild.
- App cask source lives in `Packaging/homebrew/Casks/updatebar-app.rb`; copy it to
  the tap as `Casks/updatebar-app.rb`. The cask installs `UpdateBar.app` only and
  must not link the bundled CLI. The CLI remains owned by the `updatebar` formula.
- Install the Ink TUI separately through npm until a dedicated formula is justified.

Before tagging:

- `CHANGELOG.md` has an entry matching `version.env`.
- Git remote and formula URLs match `sonim1/UpdateBar`.
- Smoke test passes from a clean `UPDATEBAR_HOME`.
- TUI smoke test passes and verifies the npm package contents.
- Archive-install smoke passes: unpack the archive, run `updatebar --version`,
  `updatebar guide agent`, and `updatebar template recipe --kind npm`.
- Clean source-copy release dry run passes.
- Formula URL/version match the tag and formula SHA matches the uploaded release
  asset's `.sha256`.
- Cask URL/version match the tag and cask SHA matches the uploaded app archive's
  `.sha256`.
- `UPDATEBAR_VERIFY_STRICT=1 Scripts/verify-homebrew-metadata.sh` verifies release
  metadata checksums for a prepared dist directory.
- `bash Scripts/homebrew-packaging-test.sh` passes.
- `updatebar status --json` remains compatible with the documented menu bar contract.
- Recipe command errors and child environments do not expose common provider or GitHub tokens.
