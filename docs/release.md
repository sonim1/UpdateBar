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
Scripts/build-release.sh
bash Scripts/archive-smoke-test.sh
Scripts/package-app.sh
```

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
```

The app packaging script creates `dist/UpdateBar.app` with the menu bar executable
in `Contents/MacOS/UpdateBar` and the CLI in `Contents/Resources/updatebar`.
Tagged macOS releases also upload an unsigned
`UpdateBar-<version>-macos-arm64.app.tar.gz` archive. Signing/notarization are not
part of the CLI release.

The app bundle does not currently include the Ink TUI. The `Open TUI` menu item
launches `updatebar-tui` from the user's environment and exports `UPDATEBAR_BIN`
to the bundled Swift CLI path.

Ink TUI packaging:

```bash
cd tui
npm install
npm run build
npm pack --dry-run
```

Release identity:

- GitHub repo slug: `sonim1/UpdateBar`.
- Published `v0.1.0` prebuilt archives currently cover Apple Silicon macOS. The
  tag workflow targets Apple Silicon macOS and Linux x86_64 for the next release.
- Homebrew tap target: `sonim1/homebrew-tap`.
- Formula source lives in `Packaging/homebrew/updatebar.rb`; copy it to the tap as
  `Formula/updatebar.rb` when publishing a Homebrew release. The formula SHA must
  come from the final uploaded release asset's `.sha256`, not from a later local
  rebuild. The formula remains CLI-only; install the Ink TUI separately through
  npm until a separate formula or cask is justified.

Before tagging:

- `CHANGELOG.md` has an entry matching `version.env`.
- Git remote and formula URLs match `sonim1/UpdateBar`.
- Smoke test passes from a clean `UPDATEBAR_HOME`.
- Archive-install smoke passes: unpack the archive, run `updatebar version --json`,
  `updatebar guide agent`, and `updatebar template recipe --kind npm`.
- Clean source-copy release dry run passes.
- Formula URL/version match the tag and formula SHA matches the uploaded release
  asset's `.sha256`.
- `updatebar status --json` remains compatible with the documented menu bar contract.
- Recipe command errors and child environments do not expose common provider or GitHub tokens.
