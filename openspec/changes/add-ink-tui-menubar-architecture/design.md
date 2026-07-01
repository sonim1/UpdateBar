## Context

UpdateBar is currently a Swift Package Manager project with a Swift CLI executable (`updatebar`), a Swift core library (`UpdateBarCore`), a Menu Bar executable (`updatebar-menubar`), and a Menu Bar library (`UpdateBarMenuBar`). `UpdateBarCore` already owns durable state, manifest handling, command execution policy, trust/approval rules, check/update behavior, and scan/init behavior.

The next product step is richer presentation: an Ink/React terminal TUI for interactive terminal users and a native macOS Menu Bar app for always-on status and lightweight actions. These surfaces must not fork business logic. The architecture must preserve the CLI as a stable automation/headless interface and make JSON/JSONL contracts strong enough for the Ink TUI to consume.

Stakeholders:

- CLI users and automation scripts that depend on stable output and exit codes.
- Interactive terminal users who want selection, progress, logs, and keyboard navigation.
- macOS users who want Menu Bar status, background checks, and quick actions.
- Maintainers who need one business-rule implementation and testable UI adapters.

## Goals / Non-Goals

**Goals:**

- Keep `UpdateBarCore` as the single source of truth for update/check/config/registry business logic.
- Keep the Swift CLI focused on command parsing, stable machine-readable output, exit codes, and subprocess-safe behavior.
- Add an Ink/React TUI as a Node presentation layer that invokes `updatebar` via subprocess and consumes JSON/JSONL.
- Keep the macOS Menu Bar as a native Swift presentation layer, with direct `UpdateBarCore` imports as the preferred long-term path.
- Document a fast MVP option where Menu Bar continues to use CLI subprocesses while contracts stabilize.
- Define streaming JSONL event behavior for long-running commands.
- Define cancellation, binary path resolution, and packaging expectations before implementation.
- Define test strategy across Swift, Node/Ink, Menu Bar, docs, and packaging.

**Non-Goals:**

- Rewriting `UpdateBarCore` in Node.
- Moving business logic into Ink, React, or Menu Bar presentation code.
- Replacing the Swift CLI with the Ink TUI.
- Implementing the Ink TUI or Menu Bar redesign in this proposal.
- Requiring a full-screen terminal UI for all CLI users.
- Changing existing JSON command shapes without compatibility review.

## Decisions

### Decision 1: Keep `UpdateBarCore` as the business-rule owner

`UpdateBarCore` remains the only layer allowed to implement manifest parsing, state writes, trust policy, command approval, check/update planning, version comparison, command execution policy, scan discovery, and init registration rules.

Alternatives considered:

- **Duplicate logic in Node TUI**: faster UI iteration, but creates trust/update divergence and more security risk.
- **Expose Swift library directly to Node**: possible via native bindings, but adds build complexity and packaging fragility.
- **Keep core in Swift and invoke CLI from Node**: chosen because it preserves one business implementation and uses a portable process boundary.

### Decision 2: Treat Swift CLI as the machine contract for external presenters

The CLI remains the automation surface. It provides `--json` for single-result commands and `--json-stream` for long-running operations where progress/logs matter. In machine modes, stdout is reserved for JSON or JSONL only; human diagnostics go to stderr or structured JSONL events.

Alternatives considered:

- **Let TUI parse human text**: rejected because it is brittle and blocks UI polish.
- **Add a local daemon API first**: deferred because it adds lifecycle and security concerns before demand is proven.
- **Use subprocess + JSON/JSONL**: chosen as the smallest stable bridge between Swift and Node.

### Decision 3: Add JSONL event contracts for long-running commands

Long-running commands such as `check` and `update` need progress, logs, item-level results, and cancellation visibility. JSONL is line-delimited, easy for Node to stream, easy for shell tools to inspect, and compatible with subprocess stdout.

Recommended event envelope:

```json
{"type":"started","operation":"update","run_id":"...","timestamp":"..."}
{"type":"item_started","operation":"update","run_id":"...","item_id":"brew.jq","timestamp":"..."}
{"type":"log","operation":"update","run_id":"...","item_id":"brew.jq","stream":"stderr","message":"...","timestamp":"..."}
{"type":"item_finished","operation":"update","run_id":"...","item_id":"brew.jq","status":"updated","timestamp":"..."}
{"type":"finished","operation":"update","run_id":"...","status":"success","timestamp":"..."}
```

All events include `type`, `operation`, `run_id`, and `timestamp`. Item-specific events include `item_id`. Failure events include a stable `code` and human-readable `message`.

### Decision 4: Implement Ink TUI as a Node presentation layer

The Ink TUI owns terminal layout, keyboard navigation, selection state, progress bars, and log panes. It does not read or write `manifest.json`, `state.json`, config, or approval stores directly. It calls the Swift `updatebar` binary and renders machine output.

The TUI subprocess adapter resolves a binary in this order:

1. Explicit config or environment override such as `UPDATEBAR_BIN`.
2. Bundled binary path when distributed with a package.
3. `updatebar` on `PATH`.
4. Development fallback such as repo-local `.build/debug/updatebar`.

This resolution order keeps source development, Homebrew installs, release archives, and packaged TUI builds testable.

### Decision 5: Keep Menu Bar native; prefer direct `UpdateBarCore` over CLI subprocess long term

The macOS Menu Bar app is native Swift/AppKit or SwiftUI. The long-term architecture imports `UpdateBarCore` and calls core services directly for status, background check/update actions, approval state, config, and logs. This gives better performance, avoids process parsing, and allows shared model types.

Fast MVP trade-off: Menu Bar can continue using CLI subprocesses if that ships faster, but it must consume the same JSON/JSONL contracts as the Ink TUI and avoid reimplementing business rules. The MVP path is acceptable only while the direct-core adapter is incomplete.

### Decision 6: Open TUI from Menu Bar by launching Terminal with the TUI entrypoint

Menu Bar `Open TUI` launches a terminal application with the configured TUI command. It passes enough environment to locate the same `updatebar` binary and `UPDATEBAR_HOME`. If no TUI command is installed, Menu Bar displays a clear install/configuration action instead of failing silently.

### Decision 7: Cancellation propagates across presentation boundaries

Ink TUI cancellation sends SIGINT to the active Swift CLI child process, waits a short grace period, then sends SIGTERM if needed. The Swift CLI handles SIGINT/SIGTERM by stopping new work, terminating active child commands it owns, recording any safe partial state, and emitting a final cancellation event in JSONL mode when possible.

Menu Bar cancellation uses the native task/cancellation path when using `UpdateBarCore` directly. If using CLI subprocesses, it follows the same SIGINT/SIGTERM behavior as Ink.

## Risks / Trade-offs

- **Two presentation stacks increase maintenance** -> Keep all business logic in `UpdateBarCore`, add shared machine contracts, and test adapters with snapshots.
- **JSONL contract churn can break TUI** -> Version event envelopes and add CLI contract snapshot tests before Ink depends on them.
- **Subprocess path resolution can fail in packaged installs** -> Define deterministic binary resolution order and add packaging smoke tests for source, Homebrew, and app bundle paths.
- **Menu Bar direct-core path may diverge from CLI behavior** -> Use shared `UpdateBarCore` services and add parity tests for Menu Bar actions against CLI-observed snapshots.
- **Cancellation can leave partial state** -> Treat cancellation as a first-class operation status, persist only atomic state updates, and emit item-level outcomes.
- **Node dependency footprint increases supply-chain surface** -> Keep Node dependencies isolated to the TUI package, pin lockfiles, and keep Swift CLI/Core usable without Node.

## Migration Plan

1. Define and test the CLI machine interface first, including JSONL event envelopes and cancellation behavior.
2. Add any missing `UpdateBarCore` APIs required by both CLI and Menu Bar without UI-specific printing.
3. Implement or adjust CLI commands to expose stable `--json` and `--json-stream` contracts.
4. Add the Ink TUI package with a subprocess adapter and contract tests against fixture JSON/JSONL.
5. Add Menu Bar actions using direct `UpdateBarCore` where practical; keep CLI subprocess adapters only as an MVP fallback.
6. Add packaging checks for Homebrew, release archive, source build, and macOS app bundle binary resolution.
7. Update docs with architecture boundaries and usage instructions.

Rollback strategy: Each implementation phase must preserve the existing Swift CLI. If Ink or Menu Bar changes regress, disable or remove the presentation package/app entrypoint without changing `UpdateBarCore` data formats.

## Open Questions

- Which package manager will own the Ink workspace (`npm`, `pnpm`, or another tool)?
- What command name should launch the TUI in packaged installs (`updatebar-tui`, `updatebar-ui`, or `updatebar tui`)?
- Should JSONL streaming be added to both `check` and `update` in the first implementation, or only `update` first?
- Which terminal application should Menu Bar prefer for `Open TUI` when multiple terminals are installed?
