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
- Human tables, wizard prompts, and terminal copy.
- JSON printing helpers and exit-code mapping.
- CLI-specific stderr diagnostics.

The Ink TUI and macOS Menu Bar should add their own presentation behavior on top
of stable Core or CLI machine contracts.

## CLI-Only Logic To Move Or Share

The audit found these non-presentation concerns outside `UpdateBarCore`:

- `status --refresh` stale-state calculation and snapshot assembly lived in
  `StatusCommand`. This should move into a Core `StatusService` so CLI and Menu
  Bar can share the same status behavior.
- `BackgroundLaunchAgentManager` currently lives in the CLI source file. If Menu
  Bar owns background checks or launch-at-login behavior, this should move to a
  shared macOS support module or a dedicated Core-facing adapter.
- Machine-readable JSONL event models are not yet centralized. The event schema
  should become a shared contract, with stdout writing kept in the CLI layer.
- Binary path resolution is duplicated between CLI packaging expectations and
  the Menu Bar app. It should become a documented resolver used by Node/Ink and
  app bundling code.

## Output Boundary

Source review found no direct `print`, `readLine`, or `FileHandle.standard*`
usage in `Sources/UpdateBarCore`. Core APIs should continue to return values,
throw errors, or call injected callbacks instead of writing human output.
