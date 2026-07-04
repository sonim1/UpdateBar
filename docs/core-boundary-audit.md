# UpdateBar Core Boundary Audit

This audit supports the OpenSpec change `add-ink-tui-menubar-architecture`.
It records where UpdateBar business logic already lives, which presentation
logic can stay outside the core, and which CLI-only logic should move into
`UpdateBarCore` before Ink TUI and macOS Menu Bar features grow.

## Core-Owned Logic

`UpdateBarCore` already owns the main product behavior:

- `ConfigStore`, `ManifestStore`, and `StateStore` own config, manifest, state,
  atomic writes, and file locking.
- `RegistryService` owns add/import/export/remove/pin/enable/trust/approval and
  check workflows.
- `UpdatePlanner` and `UpdateRunner` own update eligibility, operation results,
  post-update checks, and state persistence.
- `ScanService` and `InitService` own scan detection, candidate generation, and
  selected candidate registration.
- `StatusSnapshot` owns the menu/status contract derived from manifest and
  state data.
- Trust, validation, versioning, latest-version resolution, execution policy,
  secret redaction, and atomic file utilities are core concerns.

## Presentation-Owned Logic

The Swift CLI should keep command parsing and presentation behavior:

- ArgumentParser command definitions and flag parsing.
- Human tables, interactive prompts, and terminal copy.
- JSON printing helpers and exit-code mapping.
- CLI-specific stderr diagnostics.

The Ink TUI and macOS Menu Bar should add their own presentation behavior on top
of stable Core or CLI machine contracts.

## Resolved Boundary Items

Resolved since the initial audit:

- `status --refresh` stale-state calculation and snapshot assembly moved into
  Core `StatusService`.
- Machine-readable JSONL event models are centralized in `UpdateBarCore` under
  `MachineEvent`; stdout writing remains in the CLI layer.
- Binary path resolution is documented and implemented for the Node/Ink TUI and
  Menu Bar subprocess fallback paths.
- Background LaunchAgent plist generation, install state detection, executable
  resolution, and uninstall behavior moved into Core
  `BackgroundLaunchAgentManager`; CLI command handling remains in the CLI layer.

## Output Boundary

Source review found no direct `print`, `readLine`, or `FileHandle.standard*`
usage in `Sources/UpdateBarCore`. Core APIs should continue to return values,
throw errors, or call injected callbacks instead of writing human output.
