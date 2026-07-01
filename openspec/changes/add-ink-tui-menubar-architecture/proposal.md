## Why

UpdateBar needs richer interactive surfaces without weakening its current Swift core and automation-first CLI contract. This change defines how a Node Ink/React terminal TUI and native macOS Menu Bar app can coexist while keeping `UpdateBarCore` as the single source of truth for update/check/config behavior.

## What Changes

- Define a presentation architecture that separates business logic from CLI, Ink TUI, and macOS Menu Bar presentation layers.
- Define stable machine-readable CLI contracts for JSON output, JSONL streaming events, stdout/stderr separation, exit codes, and cancellation.
- Define an Ink/React TUI as a Node presentation layer that invokes the Swift `updatebar` binary through subprocess calls.
- Define the macOS Menu Bar app as a native Swift/AppKit or SwiftUI presentation layer, with a long-term preference for direct `UpdateBarCore` imports and a documented CLI-subprocess MVP option.
- Define packaging and binary resolution expectations for source builds, Homebrew installs, release archives, and bundled macOS app usage.
- Define test coverage expectations across Swift core/CLI tests, Node/Ink tests, Menu Bar tests, documentation, and packaging checks.

No breaking CLI changes are intended. Existing human CLI commands and JSON commands must remain compatible unless a later implementation change explicitly marks a breaking change.

## Capabilities

### New Capabilities

- `presentation-architecture`: Responsibility boundaries for `UpdateBarCore`, Swift CLI, Ink TUI, and macOS Menu Bar, including a requirement to avoid duplicated business logic.
- `cli-machine-interface`: JSON/JSONL output contracts, exit codes, stdout/stderr separation, cancellation, and machine-readable progress/log events.
- `ink-tui`: Ink/React terminal TUI requirements for subprocess use, status views, progress, logs, selection, keyboard navigation, and error handling.
- `macos-menubar`: Native macOS Menu Bar requirements for status display, background control, actions, Open TUI, config/log access, and packaging behavior.

### Modified Capabilities

- None.

## Impact

- Swift targets: `UpdateBarCore`, `UpdateBarCLI`, `UpdateBarMenuBar`, and `UpdateBarMenuBarApp`.
- Future Node/Ink workspace or package for terminal TUI presentation.
- CLI machine contracts for `status --json`, `check --json`, update streaming, logs, cancellation, and exit codes.
- Packaging flows for Homebrew formulae, release archives, and macOS app bundles that need reliable `updatebar` binary discovery.
- Test suites for Swift core/CLI/Menu Bar behavior, Node/Ink rendering and subprocess adapters, JSON/JSONL contract snapshots, and packaging smoke checks.
