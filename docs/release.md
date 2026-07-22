# Release

Release checklist:

```bash
bash Scripts/quality-gate.sh
rm -f dist/*.tar.gz dist/*.dmg dist/*.sha256
Scripts/build-release.sh
APP_DMG="$( \
  SPARKLE_PUBLIC_ED_KEY="$UPDATEBAR_RELEASE_SPARKLE_PUBLIC_KEY" \
  DEVELOPER_ID_APPLICATION="$UPDATEBAR_RELEASE_SIGNING_IDENTITY" \
  NOTARYTOOL_KEYCHAIN_PROFILE="$UPDATEBAR_RELEASE_NOTARY_PROFILE" \
  Scripts/build-app-dmg.sh \
)"
bash Scripts/app-dmg-smoke-test.sh "$APP_DMG"
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

The CLI archive is intentionally unsigned. `Scripts/build-release.sh`
normalizes archive metadata and uses `gzip -n`; the final SHA is still the SHA
of the exact binary built by that runner and toolchain. By default, the binary
is kept unstripped to preserve runtime compatibility; if you need stripping in
a known-good toolchain, run with `UPDATEBAR_STRIP_BINARY=1`. Set
`UPDATEBAR_AD_HOC_CODESIGN=1` only for local experiments. The macOS app
distribution path requires Developer ID signing, notarization, stapling, and
Gatekeeper assessment before publishing.

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

Local app bundle for development:

```bash
SPARKLE_PUBLIC_ED_KEY="$UPDATEBAR_RELEASE_SPARKLE_PUBLIC_KEY" Scripts/package-app.sh
open dist/UpdateBar.app
```

The app packaging script creates `dist/UpdateBar.app` with the menu bar executable
in `Contents/MacOS/UpdateBar` and the CLI in `Contents/Resources/updatebar`.
The current `v0.5.0` app release remains the published legacy asset
`UpdateBar-0.5.0-macos-arm64.app.tar.gz`. Starting with the next published app
release, tagged macOS releases upload the canonical Apple Silicon asset
`UpdateBar-<version>-macos-arm64.dmg` and its `.sha256` checksum.
`Scripts/build-app-dmg.sh` verifies the selected Developer ID identity and
notary profile before packaging, then signs the app and DMG, notarizes, staples,
performs Gatekeeper assessments, and publishes the checksum first and the DMG
last as the commit marker under a same-release lock. Any interrupted publish
removes only outputs created by that invocation.
`Scripts/app-dmg-smoke-test.sh` mounts the DMG read-only and verifies its app,
Applications shortcut, Sparkle framework, feed URL, public key, and checksum.
Because notarization stapling and toolchain drift change rebuilt DMG contents,
the release workflow's temporary pre-release metadata check uses
`UPDATEBAR_VERIFY_STATIC_ONLY=1`. It validates the committed formula and cask
structure without comparing their SHAs to the fresh build. After the assets are
public, release manifest/tap automation performs the authoritative
post-publication SHA and DMG cask update from those published assets.
The in-repository `v0.5.0` Homebrew cask must keep targeting the published
legacy app archive until a canonical DMG and manifest for a later release are
public. Tap automation then updates the authoritative cask from those published
assets.
Signing/notarization are not part of the CLI release.

The DMG builder requires these environment values on Apple Silicon macOS:

- `SPARKLE_PUBLIC_ED_KEY`: canonical 32-byte Sparkle public key in Base64
- `DEVELOPER_ID_APPLICATION`: exact Developer ID Application identity string
- `NOTARYTOOL_KEYCHAIN_PROFILE`: keychain profile name for `xcrun notarytool`
- optional `NOTARYTOOL_KEYCHAIN`: keychain file path holding the
  notary profile (used by CI, which stores credentials in a temporary keychain)
- optional `UPDATEBAR_SIGN_ENTITLEMENTS_FILE`: entitlements file path for `codesign`

`Scripts/build-app-dmg.sh` passes the signing inputs to `package-app.sh`, which
signs inside-out. The builder refuses to start packaging if the identity or
notary profile cannot be verified.

### Signed releases in CI

The release workflow fails closed unless the Sparkle public key GitHub variable
and every signing/notary secret below are configured. It never publishes an
unsigned or unnotarized app fallback.

- repository variable `SPARKLE_PUBLIC_ED_KEY`: canonical Sparkle public key

- `MACOS_SIGNING_CERT_P12`: base64-encoded PKCS#12 export of the
  "Developer ID Application" certificate (with private key)
- `MACOS_SIGNING_CERT_PASSWORD`: password protecting the `.p12`
- `NOTARY_APPLE_ID`: Apple ID email for notarization
- `NOTARY_TEAM_ID`: Apple Developer team ID
- `NOTARY_PASSWORD`: app-specific password for the Apple ID
  (create at <https://account.apple.com>, Sign-In and Security >
  App-Specific Passwords)

Configure those values through protected GitHub repository settings; never put
private certificate material or notary credentials in the repository.

Local signed + notarized DMG, after its notary profile already exists in the
selected keychain:

```bash
SPARKLE_PUBLIC_ED_KEY="$UPDATEBAR_RELEASE_SPARKLE_PUBLIC_KEY" \
DEVELOPER_ID_APPLICATION="$UPDATEBAR_RELEASE_SIGNING_IDENTITY" \
NOTARYTOOL_KEYCHAIN_PROFILE="$UPDATEBAR_RELEASE_NOTARY_PROFILE" \
Scripts/build-app-dmg.sh
```

The printed path is the notarized, stapled DMG. Verify it with
`Scripts/app-dmg-smoke-test.sh <printed-path>` before release.

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
- Current release metadata in this repo targets `v0.6.1`.
- Published prebuilt CLI archives cover Apple Silicon macOS and Linux x86_64.
  The current app asset is `UpdateBar-0.5.0-macos-arm64.app.tar.gz`; starting
  with the next published app release, tags also publish
  `UpdateBar-<version>-macos-arm64.dmg`. The workflow fails if signing,
  notarization, or Sparkle public-key inputs are unavailable.
- Homebrew tap target: `sonim1/homebrew-tap`.
- Formula source lives in `Packaging/homebrew/updatebar.rb`; copy it to the tap as
  `Formula/updatebar.rb` when publishing a Homebrew release. The formula SHA must
  come from the final uploaded release asset's `.sha256`, not from a later local
  rebuild.
- App cask source lives in `Packaging/homebrew/Casks/updatebar-app.rb`; copy it to
  the tap as `Casks/updatebar-app.rb`. The cask installs `UpdateBar.app` only and
  must not link the bundled CLI. The CLI remains owned by the `updatebar` formula.
- Ink TUI formula source lives in `Packaging/homebrew/updatebar-tui.rb`; copy it
  to the tap as `Formula/updatebar-tui.rb` when publishing a TUI formula update.
  For source checkouts, build the Ink TUI with npm:

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
- For `v0.5.0`, the Cask URL and SHA still match the published legacy app
  archive. For the next app release, the Cask URL/version match the tag and its
  SHA matches the uploaded app DMG's `.sha256`.
- `UPDATEBAR_VERIFY_STRICT=1 Scripts/verify-homebrew-metadata.sh` verifies release
  metadata checksums for a prepared dist directory.
- `bash Scripts/homebrew-packaging-test.sh` passes.
- `updatebar status --json` remains compatible with the documented menu bar contract.
- Recipe command errors and child environments do not expose common provider or GitHub tokens.

## Rollback or Yank

Prefer a fixed patch release over rewriting a published tag. If a release must
be pulled back, keep the public trail clear:

1. Confirm the bad version, affected assets, and whether Homebrew tap metadata
   has already been updated.
2. Mark the GitHub Release notes as yanked or superseded, including the fixed
   version users should install.
3. Revert or update the tap formula/cask to a known-good version; do not leave
   Homebrew metadata pointing at missing assets.
4. Cut a patch release with a matching `version.env`, `CHANGELOG.md` entry,
   archives, checksums, formula, and cask metadata.
5. Avoid force-pushing or deleting tags unless the release was never consumed
   and every downstream reference has been checked.
