# UpdateBar Release Workflow

This document is the short operational guide for shipping UpdateBar. The detailed
contracts and recovery procedures live in [release.md](release.md).

## Normal release

1. Merge a release-relevant change into `main` with a new `version.env` version
   and matching `CHANGELOG.md` entry.
2. The `Automatic Release` workflow validates that the version strictly
   increases, creates the exact annotated `v<version>` tag, and dispatches the
   tag-specific `release.yml` workflow.
3. `release.yml` runs secret-free verification, builds and signs the app/CLI,
   notarizes the DMG, publishes GitHub Release and Sparkle/R2 assets, then
   optionally notifies `sonim1/homebrew-tap`.

The release workflow is serialized and does not cancel an earlier queued run.
Do not move or recreate an existing release tag.

## Release inputs

The protected `release` environment supplies Apple signing/notarization,
Sparkle, Cloudflare R2, and optional Homebrew notification credentials. Keep
`.env.release.local` local-only and never commit certificates, private keys,
or decoded secret exports.

Before pushing a release candidate:

```bash
bash Scripts/quality-gate.sh
bash Scripts/app-icon-test.sh
bash Scripts/homebrew-packaging-test.sh
```

## Homebrew installation

The app cask installs both `UpdateBar.app` and its bundled `updatebar` CLI:

```bash
brew tap sonim1/tap
brew install --cask sonim1/tap/updatebar-app
```

Use `brew install --formula sonim1/tap/updatebar` only for a CLI-only install.
The tap is updated after the GitHub Release is public and its checksums are
available.

## Recovery

If automatic planning succeeds but downstream publication fails, inspect the
existing tag, draft release, and published assets first. Prefer rerunning only
the failed workflow job; do not rebuild immutable versioned artifacts blindly.

```bash
gh run list --repo sonim1/UpdateBar
gh release list --repo sonim1/UpdateBar
gh workflow run release.yml --repo sonim1/UpdateBar --ref vX.Y.Z -f tag=vX.Y.Z
```

Only dispatch a recovery workflow after confirming the tag points to the
intended `main` commit and no active run is already publishing it.

