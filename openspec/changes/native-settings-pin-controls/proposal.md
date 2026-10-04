## Why

Preferences Save starts from default configuration and can reset CLI-configured concurrency. The native Items details display pin state but require a terminal to change it. These gaps affect the existing management workflow.

## What Changes

- Save only edited Preferences fields into the configuration loaded at save time. Preserve unrelated CLI changes made after opening the screen, and reload the saved values into the form.
- Expose the existing 1–8 parallel-update limit in Preferences. Make the optional CLI adapter read and write the existing concurrency contract.
- Add native pin/unpin controls backed by the existing Core and CLI operations. Keep tracking and pin state independent, reject overlapping mutations, and wait for the canonical snapshot before re-enabling actions.
- Resolve cached paused statuses as needing a check once the manifest is enabled and unpinned. A cached pin/disable result must not make a resumed recipe appear paused.

## Compatibility

No recipe schema, command approval semantics, CLI JSON/JSONL fields, exit codes, dependencies or packaging changes. Pinning continues to skip checks and updates; unpinning never executes a command. Current-version lookup remains owned by the existing RegistryService. Legacy config JSON without an update object retains the default concurrency.
