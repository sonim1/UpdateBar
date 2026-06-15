# Release

Release checklist:

```bash
swift build
swift build -c release --product updatebar
swift build -c release --product updatebar-menubar
swift test
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
builds a reproducible archive payload, normalizes timestamps, and uses `gzip -n`
so repeated clean builds produce the same SHA. By default, the binary is kept
unstripped to preserve runtime compatibility; if you need stripping in a known-good
toolchain, run with `UPDATEBAR_STRIP_BINARY=1`. Set
`UPDATEBAR_AD_HOC_CODESIGN=1` only for local experiments; M4 handles real
Developer ID signing for the app.

Archive smoke test:

```bash
bash Scripts/archive-smoke-test.sh
```

Local unsigned app package:

```bash
Scripts/package-app.sh
```

The app packaging script creates `dist/UpdateBar.app` with the menu bar executable
in `Contents/MacOS/UpdateBar` and the CLI in `Contents/Resources/updatebar`.
Signing/notarization are not part of the CLI release.

Release identity:

- GitHub repo slug: `sonim1/UpdateBar`.
- Homebrew tap target: `sonim1/homebrew-tap`.
- Formula source lives in `Packaging/homebrew/updatebar.rb`; copy it to the tap as
  `Formula/updatebar.rb` when publishing the first Homebrew release.

Before tagging:

- `CHANGELOG.md` has an entry matching `version.env`.
- Git remote and formula URLs match `sonim1/UpdateBar`. This working tree may not
  have `origin` configured yet; create/push the GitHub repo before tagging.
- Smoke test passes from a clean `UPDATEBAR_HOME`.
- Archive-install smoke passes: unpack the archive, run `updatebar version --json`,
  `updatebar guide agent`, and `updatebar template recipe --kind npm`.
- Clean source-copy release dry run passes and the formula SHA matches the built archive.
- `updatebar status --json` remains compatible with the documented menu bar contract.
- Recipe command errors and child environments do not expose common provider or GitHub tokens.
