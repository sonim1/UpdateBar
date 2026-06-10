# UpdateBar Release Required Follow-ups

These items are intentionally not automated in the local build. Resolve them before a public v0.1.0 release.

## Repository And Release Coordinates

- Confirm the public GitHub repository slug. The current Homebrew formula, release workflow, and release docs assume `kendrick/UpdateBar`.
- Rebuild release archives from the final tagged commit and update the Homebrew formula SHA256 from the actual uploaded artifact. Local `dist/` archives are ignored and should not be treated as canonical.
- Run the release workflow from a real `v*` tag and verify both macOS arm64 and Linux x86_64 artifacts upload successfully.
- Confirm the repository allows `swift-actions/setup-swift@v2` and GitHub release creation from workflow `contents: write` permissions.

## Local Toolchain

- Local verification required the full Xcode toolchain:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcrun swift ...`
- Command Line Tools Swift was not sufficient in this workspace because XCTest could not be resolved correctly.

## Manual CLI Smoke

- Run the external-agent authoring flow:
  `updatebar guide agent`, `updatebar template recipe --kind npm`, `updatebar validate <recipe> --json`, and `updatebar add --from <recipe> --dry-run --json`.
- Run the separated approval flow:
  `updatebar add --from <recipe>`, `updatebar approvals <id>`, `updatebar approve <id> --field update.cmd`, and `updatebar revoke <id> --field update.cmd`.
- Confirm recipe command errors and child environments do not expose common provider or GitHub tokens.

## Distribution Notes

- Homebrew formula syntax has been checked locally, but `brew install`/`brew test` requires the final public release archive URL.
- Current release archives are CLI-only and ad-hoc signed on macOS when possible. Developer ID signing and notarization are deferred unless direct-download distribution requires them.
