# Changelog

## Unreleased

## 0.4.0 - 2026-07-10

### Added

- `Overview` menu entry: a dashboard panel with pending-update and
  awaiting-approval tiles, last check/update times, and a four-week bar chart
  of successful updates.
- `Manage Items...` menu entry: a panel listing every registered item grouped
  by category with per-item enable/disable toggles.
- Update/check history recorded to `~/.updatebar/history.jsonl` and exposed
  via the new `updatebar history [--json] [--since <iso8601>]` subcommand.

### Changed

- The Scan & Add panel no longer scans on open; scanning starts from the Scan
  button, and already-registered candidates are marked and cannot be
  re-imported.

## 0.3.2 - 2026-07-10

### Changed

- Merged the terminal picker into `Open TUI`: with multiple supported
  terminals installed the item expands into a submenu of terminals (with app
  icons) and picking one opens the TUI there directly, instead of a separate
  `TUI Terminal` selection submenu.

## 0.3.1 - 2026-07-10

### Fixed

- Fixed arrow keys echoing as escape sequences in `updatebar tui`: the CLI
  now replaces itself with the TUI via exec instead of spawning it in a new
  process group, so the terminal raw mode request is honored.

## 0.3.0 - 2026-07-09

### Changed

- Simplified the menu bar `Open TUI` action to run a single `updatebar tui`
  command in Terminal; TUI discovery and install guidance now live in the CLI.
- Added a `TUI Terminal` picker submenu with app icons for choosing which
  terminal (Terminal, iTerm, Ghostty, kitty, Alacritty, WezTerm, Warp, Rio)
  opens the TUI; the app now launches it via a `.command` file instead of
  AppleScript, removing the Terminal automation permission prompt. Warp is
  driven through a generated launch configuration and its `warp://launch/`
  URI since it has no exec flag.
- Pointed the missing-TUI CLI error at the new `updatebar-tui` Homebrew
  formula, keeping source-build guidance for contributors.
- Added a `updatebar-tui` Homebrew formula so end users can install the
  terminal UI with `brew install sonim1/tap/updatebar-tui`.
- Signed and notarized macOS app archives in the release workflow when
  signing secrets are configured; unsigned builds remain the fallback.
- Linked libcurl explicitly for statically linked Linux release binaries and
  installed its dev package in the release workflow, fixing undefined curl
  symbol link failures.
- Relaxed strict release metadata verification to skip committed formula/cask
  SHA equality (`UPDATEBAR_VERIFY_SKIP_SHA_EQUALITY=1`): notarization stapling
  and toolchain drift make rebuilt archives differ from published assets.
  Structural checks and archive checksum integrity remain strict.
- Removed the hidden prompt-based `updatebar add` wizard; use `updatebar add --from <file>` or `updatebar add --from -` for explicit recipe input.
- Clarified CLI help for required recipe input, headless JSON confirmations,
  hidden automation exit behavior, and background install confirmation.
- Clarified install, upgrade, uninstall, Apple Silicon support, and unsigned
  macOS launch guidance.
- Added release workflow dry runs, Swift test gating, and CHANGELOG-backed
  GitHub Release notes.

### Fixed

- Ran the Ink TUI in the alternate screen buffer so arrow keys work in Warp
  (its block editor was capturing input for primary-screen programs) and
  scrollback stays clean everywhere.
- Made macOS app archives reproducible enough for pre-tag Homebrew cask SHA
  verification by normalizing mtimes, tar metadata, and gzip headers.
- Statically linked the Swift standard library into Linux release binaries.
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

### Security

- Added private vulnerability reporting guidance and Dependabot monitoring for
  GitHub Actions, npm, and Swift package dependencies.

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
  item management, import/export, explicit add, edit.
- Smoke tests and release packaging scripts.
