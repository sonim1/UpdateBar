## ADDED Requirements

### Requirement: Updates run with bounded, lane-exclusive parallelism

UpdateBar SHALL update at most `update.max_concurrent` items at once, defaulting
to 3 and constrained to 1 through 8. Two items whose `update.cmd` resolves to the
same tool name SHALL NOT execute at the same time. `updatebar update --jobs <n>`
SHALL override the configured value for one run and SHALL exit non-zero for
values outside 1 through 8.

#### Scenario: Two Homebrew recipes are serialised

- **WHEN** two outdated items both have `update.cmd` beginning with `brew`
- **THEN** their update commands SHALL NOT overlap in time

#### Scenario: Results keep plan order

- **WHEN** `updatebar update --json` updates several items in parallel
- **THEN** the emitted results SHALL be ordered by the update plan, not by the
  order items finished

### Requirement: The menu bar shows per-item progress instead of collapsing

While an action is in flight the menu SHALL keep every section rendered. Items
currently updating SHALL be marked as updating, items not yet started SHALL be
marked as queued, and completed items SHALL be marked as done. Check Now,
Refresh Status, Update All, per-item update actions, and approval actions SHALL
be disabled for the duration. Dashboard, Manage Items, Scan & Add, Open TUI,
Open Config, View Logs, and Quit SHALL remain enabled.

#### Scenario: Update All is running

- **WHEN** the user opens the menu while Update All is running
- **THEN** the menu SHALL list the item rows with per-item progress and SHALL
  keep the footer actions enabled

### Requirement: The menu bar stops rather than cancels

The menu bar SHALL offer Stop After Current, which SHALL let the running update
command finish and SHALL prevent any queued item from starting. The menu bar
SHALL NOT terminate a running update command.

#### Scenario: Stop is requested mid-run

- **WHEN** the user selects Stop After Current during a multi-item update
- **THEN** the in-flight command SHALL run to completion and no queued item
  SHALL start
