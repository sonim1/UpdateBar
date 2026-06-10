# Release

Release checklist:

```bash
swift build
swift build -c release --product updatebar
swift test
bash Scripts/smoke-test.sh
Scripts/build-release.sh
bash Scripts/archive-smoke-test.sh
```

Build a local release archive:

```bash
Scripts/build-release.sh
```

`Scripts/build-release.sh` regenerates `Sources/UpdateBarCLI/UpdateBarVersion.swift`
from `version.env` before compiling. If `version.env` changes during development, run
`Scripts/generate-version-source.sh` before tests.

Archive smoke test:

```bash
bash Scripts/archive-smoke-test.sh
```

Homebrew formula source lives in `Packaging/homebrew/updatebar.rb`.

Before tagging:

- `CHANGELOG.md` has an entry matching `version.env`.
- Git remote and formula URLs match the final GitHub repo slug. The current formula
  uses `kendrick/UpdateBar`; verify this before publishing because no `origin`
  remote is configured in this working tree.
- Smoke test passes from a clean `UPDATEBAR_HOME`.
- Archive-install smoke passes: unpack the archive, run `updatebar version --json`,
  `updatebar guide agent`, and `updatebar template recipe --kind npm`.
- `updatebar status --json` remains compatible with the documented menu bar contract.
- Recipe command errors and child environments do not expose common provider or GitHub tokens.
