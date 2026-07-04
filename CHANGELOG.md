# Changelog

## Unreleased

### Fixed

- Improved release installer errors for failed GitHub metadata, archive,
  checksum downloads, and release archive extraction failures.
- Improved local installer output with copyable PATH guidance.
- Strengthened app archive smoke checks to verify the bundle remains a menu bar
  app.
- Guarded release installer, menu bar launch, app archive, and quality gate
  checks against accidental removal from the local release gate.
- Hardened TUI subprocess cancellation by refusing already-aborted launches and
  cleaning abort listeners after command exit.
- Kept JSON and JSONL failure modes machine-readable by avoiding duplicate
  human stderr after structured error payloads or failed events.
- Enforced explicit-any linting in the TUI TypeScript source.

## 0.2.0 - 2026-07-01

### Breaking

- Removed built-in AI recipe generation (`add --ai`) and the OpenRouter provider.
- Removed `auth` commands, provider credential stores, and the plaintext secret fallback.
- UpdateBar no longer generates recipes or commands itself. External agents author
  recipe JSON; UpdateBar validates, gates, and executes approved commands only.

### Added

- macOS menu bar app with native status item, check/update actions, approval controls,
  config/log shortcuts, and local app bundle packaging.
- Ink/React TUI for terminal status, check, update, logs, and keyboard-driven selection.
- `scan` and selective `init` flows for discovering locally installed tools and adding
  selected candidates as untrusted recipes.
- `guide agent` and recipe `template` commands for external-agent workflows.
- `validate` for manifest or single-recipe JSON.
- Per-command `approve` / `approvals` / `revoke`.
- `--exit-zero-on-outdated` on `check` and `status`.
- `manifest.lock` / `state.lock` cross-process file locks.
- Stable JSON/JSONL status, check, and update contracts for automation and presentation
  layers.
- GitHub Actions release workflow now builds CLI archives for macOS/Linux and an
  unsigned macOS app archive.

### Fixed

- Menu bar status no longer reports `Up to date` when errors or unapproved commands
  need attention.
- Menu bar long-running actions can be cancelled and overlapping actions are blocked.
- Menu bar CLI fallback now surfaces structured JSON error messages.
- Menu bar error state now exposes `Open TUI` and `View Logs` recovery actions.

### Security

- Recipe child processes now receive an allowlisted environment
  (`PATH`, `HOME`, `LANG`, `LC_ALL`, `LC_CTYPE`, `TMPDIR`, `USER`) instead of a denylist.
- Recipe commands run via `/bin/sh -c` with no login shell; shell startup files
  cannot re-inject secrets.

## 0.1.0

- Initial CLI: manifest validation, config, check/status/list/update,
  item management, import/export, manual add, edit.
- Smoke tests and release packaging scripts.
