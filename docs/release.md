# Release

Release checklist:

```bash
bash Scripts/quality-gate.sh
rm -f dist/*.tar.gz dist/*.sha256
Scripts/build-release.sh
Scripts/package-app.sh
bash Scripts/build-app-archive.sh
bash Scripts/install-release.sh --help
UPDATEBAR_VERIFY_STRICT=1 bash Scripts/verify-homebrew-metadata.sh
```

Before pushing a tag, run the GitHub Actions `Release` workflow manually from
the Actions tab. Manual dispatch is a dry run: it builds and verifies release
artifacts, but does not publish a GitHub Release.

`Scripts/install-release.sh` installs published CLI archives with `curl`,
`tar`, and `install`. It verifies each archive against the uploaded `.sha256`
checksum using `shasum` or `sha256sum`, and fails before download/extraction if
a required tool is missing.

On macOS, `Scripts/quality-gate.sh` prefers `/Applications/Xcode.app` when it is
available so `swift test` can find `XCTest`. Before running Swift tests, the
gate checks that the selected developer directory contains `XCTest.framework`;
if it prints `Swift XCTest not found`, set `DEVELOPER_DIR` explicitly or follow
the recovery steps in `docs/troubleshooting.md`.
The quality gate also builds the debug `updatebar` executable before Swift
tests and sets `UPDATEBAR_TEST_BIN` so CLI integration tests run the freshly
built binary instead of an older `.build/debug/updatebar`. When running Swift
tests manually after CLI changes, use:

```bash
swift build --product updatebar
UPDATEBAR_TEST_BIN=$PWD/.build/debug/updatebar swift test
```

The quality gate runs Homebrew metadata verification with
`UPDATEBAR_VERIFY_STATIC_ONLY=1`, which checks formula/cask metadata without
comparing local `dist` checksums. Use strict verification before publishing.

Build a local release archive:

```bash
Scripts/build-release.sh
```

`Scripts/build-release.sh` regenerates `Sources/UpdateBarCLI/UpdateBarVersion.swift`
from `version.env` before compiling. If `version.env` changes during development, run
`Scripts/generate-version-source.sh` before tests.

Linux release archives pass `--static-swift-stdlib` to SwiftPM so the published
binary does not require a Swift toolchain on user machines.

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
`UpdateBar-<version>-macos-<arch>.app.tar.gz` archive for the host architecture.
`Scripts/build-app-archive.sh` normalizes app bundle mtimes, tar owner/group
metadata, and gzip headers so cask SHA values can be reproduced before tagging.
The published Homebrew cask currently targets the arm64 app asset.
Signing/notarization are not part of the CLI release.

`Scripts/package-app.sh` supports environment-based signing/notarization when
`UPDATEBAR_SIGN_APP=1` and `UPDATEBAR_NOTARIZE_APP=1` are set. Provide these
when running on macOS with Apple tooling:

- `UPDATEBAR_SIGN_IDENTITY`: Developer ID application identity string
- `UPDATEBAR_NOTARYTOOL_KEYCHAIN_PROFILE`: keychain profile name for `xcrun notarytool`
- optional `UPDATEBAR_NOTARYTOOL_KEYCHAIN`: keychain file path holding the
  notary profile (used by CI, which stores credentials in a temporary keychain)
- optional `UPDATEBAR_SIGN_ENTITLEMENTS_FILE`: entitlements file path for `codesign`

When signing is enabled, the script signs inside-out: bundled CLI first, menu bar
executable second, app bundle last. It intentionally does not use
`codesign --deep`.

### Signed releases in CI

The release workflow signs and notarizes the macOS app when the following
repository secrets are configured. If `MACOS_SIGNING_CERT_P12` is absent, the
workflow builds an unsigned app as before; if only the notary secrets are
absent, the app is signed but not notarized.

- `MACOS_SIGNING_CERT_P12`: base64-encoded PKCS#12 export of the
  "Developer ID Application" certificate (with private key)
- `MACOS_SIGNING_CERT_PASSWORD`: password protecting the `.p12`
- `NOTARY_APPLE_ID`: Apple ID email for notarization
- `NOTARY_TEAM_ID`: Apple Developer team ID
- `NOTARY_PASSWORD`: app-specific password for the Apple ID
  (create at <https://account.apple.com>, Sign-In and Security >
  App-Specific Passwords)

One-time secret setup from a machine that has the certificate:

```bash
# Export the signing certificate + private key (Keychain Access GUI also works)
security export -t identities -f pkcs12 -o /tmp/updatebar-signing.p12 -P "<p12-password>"

gh secret set MACOS_SIGNING_CERT_P12 --body "$(base64 -i /tmp/updatebar-signing.p12)"
gh secret set MACOS_SIGNING_CERT_PASSWORD --body "<p12-password>"
gh secret set NOTARY_APPLE_ID --body "<apple-id-email>"
gh secret set NOTARY_TEAM_ID --body "<team-id>"
gh secret set NOTARY_PASSWORD --body "<app-specific-password>"
rm /tmp/updatebar-signing.p12
```

Local signed + notarized package (requires a one-time
`xcrun notarytool store-credentials updatebar-notary --apple-id <email> --team-id <team-id>`):

```bash
UPDATEBAR_SIGN_APP=1 \
UPDATEBAR_SIGN_IDENTITY="Developer ID Application: <name> (<team-id>)" \
UPDATEBAR_NOTARIZE_APP=1 \
UPDATEBAR_NOTARYTOOL_KEYCHAIN_PROFILE=updatebar-notary \
Scripts/package-app.sh
```

Signing and stapling happen before `Scripts/build-app-archive.sh`, so the
stapled ticket is included in the released archive and its cask SHA.

The app bundle does not currently include the Ink TUI. The `Open TUI` menu item
first honors an executable `UPDATEBAR_TUI` override, then prefers launching
`UPDATEBAR_BIN tui` when the bundled CLI is available, and finally falls back to
`updatebar-tui` from the user's `PATH`.

Ink TUI packaging:

```bash
Scripts/tui-smoke-test.sh
```

Release identity:

- GitHub repo slug: `sonim1/UpdateBar`.
- Published `v0.2.0` prebuilt CLI archives cover Apple Silicon macOS and Linux
  x86_64. Release tags also publish an unsigned macOS app archive for the build
  host architecture.
- Homebrew tap target: `sonim1/homebrew-tap`.
- Formula source lives in `Packaging/homebrew/updatebar.rb`; copy it to the tap as
  `Formula/updatebar.rb` when publishing a Homebrew release. The formula SHA must
  come from the final uploaded release asset's `.sha256`, not from a later local
  rebuild.
- App cask source lives in `Packaging/homebrew/Casks/updatebar-app.rb`; copy it to
  the tap as `Casks/updatebar-app.rb`. The cask installs `UpdateBar.app` only and
  must not link the bundled CLI. The CLI remains owned by the `updatebar` formula.
- Build or install the Ink TUI from source with npm until a published package or
  dedicated formula is justified:

```bash
npm --prefix tui run build
```

Before tagging:

- `CHANGELOG.md` has an entry matching `version.env`.
- `Scripts/extract-changelog-section.sh v<version>` prints non-empty release
  notes; release.yml publishes this section as the GitHub Release body.
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
