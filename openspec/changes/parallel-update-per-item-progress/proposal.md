## Why

Any menu bar action replaced the entire menu with one "Updating…" line plus
Cancel, so the whole app read as disabled while a single recipe was being
touched. Updates also ran strictly one at a time, making Update All slow on a
large registry.

## What Changes

- Run updates with bounded parallelism, capped by the new `update.max_concurrent`
  config key (default 3) and overridable per run with `updatebar update --jobs N`.
- Never run two recipes whose `update.cmd` invokes the same tool at the same
  time, because package managers hold a process-wide lock.
- Keep the menu bar menu fully rendered during an action, annotating individual
  rows as updating, queued, or done, and leaving Dashboard, Manage Items, Scan &
  Add, Open TUI, Open Config, View Logs, and Quit enabled.
- Replace the menu bar's Cancel Current Action with Stop After Current, which
  drains the queue instead of killing a running package manager. CLI Ctrl-C
  still hard-cancels.
- Lock `HistoryStore.append`, whose unsynchronised read-modify-write drops
  events once updates run in parallel.

## Compatibility

- `updatebar update` human and `--json` output keep their current shape:
  results are re-emitted in plan order regardless of finish order.
- `--json-stream` emits the same `MachineEvent` types and fields;
  `item_started` and `item_finished` now interleave across items.
- `updatebar config get --json` gains an additive `update` object.
- Config files written before this change lack the `[update]` section and fall
  back to `max_concurrent = 3`.
