# Architecture

UpdateBar has one business-logic core and multiple presentation layers.

## UpdateBarCore

`UpdateBarCore` is the source of truth for file paths, config, manifest/state
stores, scan/init, validation, trust and approvals, check, status, update
planning, update execution, summaries, and machine event models.

Core code must not print human output or parse CLI text. It returns typed values,
throws typed errors, and accepts injected runners or callbacks where needed.

## Swift CLI

`updatebar` is the automation interface. It owns command parsing, human terminal
output, stable JSON/JSONL stdout contracts, stderr diagnostics, and process exit
codes. It calls `UpdateBarCore` for product behavior instead of rebuilding
business rules in command handlers.

## Ink TUI

The Ink TUI lives in `tui/` as a Node/React presentation layer. It does not
import Swift libraries. It resolves the Swift CLI binary, calls commands such as
`status --json`, `scan --json`, `init --select`, `check --json`, and
`update --json-stream`, then renders menu, selection, status, progress, logs,
and cancellation UI from machine-readable output.

## macOS Menu Bar

The macOS Menu Bar app is native Swift/AppKit. It prefers direct
`UpdateBarCore` calls through `CoreMenuBarService` and keeps
`UpdateBarCLIClient` as a subprocess fallback for packaged or diagnostic flows.
It can open the Ink TUI in Terminal with an explicit `UPDATEBAR_TUI` override,
or with `UPDATEBAR_BIN` pointing at the resolved Swift CLI.

## Boundary Rules

- Core owns business behavior.
- CLI/TUI/Menu Bar own presentation and process integration.
- TUI consumes only JSON/JSONL CLI contracts.
- Menu Bar can call Core directly because it is in the Swift package.
- Human logs never share stdout with JSON or JSONL machine output.
