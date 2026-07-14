---
name: release
description: Prepare an UpdateBar release (changelog section, version, archives, checksums, Homebrew metadata) feeding the release.yml pipeline. Publishing steps only on explicit request.
---

# Release (UpdateBar)

Releases are scripted + workflow-driven (`.github/workflows/release.yml`); signed/notarized since v0.3.0; formula+cask live in `sonim1/tap`; published asset SHAs are recorded in-repo afterward.

## Prepare (with release approval)

1. `Scripts/quality-gate.sh` → 0.
2. `CHANGELOG.md`: add the version section (script `Scripts/extract-changelog-section.sh` must be able to extract it — its `-test.sh` shows the expected format). Update `version.env`.
3. Local archive sanity:
   ```bash
   Scripts/build-release.sh          # or build-app-archive.sh path
   Scripts/verify-archive-checksum.sh
   Scripts/verify-homebrew-metadata.sh
   ```
4. Install-path smoke: `Scripts/install-release-smoke.sh` (it's the big one — 18K) or at minimum `install-local-smoke-test.sh`.

## Publish (explicit request only)

Tag/push per `release-plan.md` conventions → `release.yml` runs. After assets publish: record asset SHAs in-repo the way "Record published v0.4.0 asset SHAs" did; verify `brew install sonim1/tap/updatebar` metadata matches (`verify-homebrew-metadata.sh`).

Missing signing/notary credentials at any step → ask; never improvise identities.
