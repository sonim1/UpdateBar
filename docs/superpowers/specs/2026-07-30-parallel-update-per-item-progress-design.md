# Parallel updates with per-item menu bar progress

Date: 2026-07-30
Status: approved (design), not yet implemented

## Problem

Running any menu bar action collapses the entire menu. `MenuBarMenuModelBuilder.makeMenu`
(`Sources/UpdateBarMenuBar/MenuBarMenuModel.swift:98`) returns early when an action is active,
replacing every entry with a single "Updating…" line plus "Cancel Current Action". The user sees
the whole app as disabled even though only one recipe is being touched.

Two contributing facts, both verified in the current code:

- `MenuBarActionCoordinator` (`Sources/UpdateBarMenuBar/MenuBarActionCoordinator.swift:26`) is a
  global mutex. `begin()` refuses a second action with "Already running: …".
- `UpdateRunner.update` (`Sources/UpdateBarCore/Update/UpdateRunner.swift:49`) iterates the plan
  strictly sequentially. Nothing runs in parallel today.

So "Update All" on a large registry is a long serial run behind an opaque, fully collapsed menu.

## Goals

1. The menu bar menu stays rendered during an action. Only genuinely busy rows are disabled.
2. Updates run with bounded parallelism (default 3) so "Update All" finishes faster.
3. Concurrency never lets two recipes driven by the same package manager run at once.
4. Machine-readable stdout keeps its current shape.

## Non-goals

- Multiple user-initiated actions in flight at the same time. One action at a time still holds the
  coordinator; only the *display* becomes per-item and the *execution* becomes internally parallel.
- Streaming progress across the CLI subprocess boundary. The shipped app uses `CoreMenuBarService`
  in-process; `UpdateBarCLIClient` is opt-in via `UPDATEBAR_MENUBAR_ADAPTER=cli`
  (`Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift:733`). Under that adapter the menu shows
  the coarse "running" state it shows today, with no per-item detail.

## Design

### 1. Lane keys

New `Sources/UpdateBarCore/Update/UpdateLane.swift`:

```swift
enum UpdateLane {
    /// The tool that will actually hold a package-manager lock, derived from update.cmd.
    static func key(forCommand cmd: String) -> String?
}
```

Tokenize on whitespace, skip leading `FOO=bar` environment assignments and wrapper commands
(`sudo`, `env`, `command`, `nice`, `nohup`), take the next token's last path component, lowercase
it. `brew`, `npm`, `pnpm`, `cargo`, `gh`, and so on. Return `nil` when nothing parses; the caller
gives such a recipe its own private lane, so it is unconstrained.

`update.cmd` is the right signal rather than `Recipe.source.kind`, because the lock belongs to the
tool being executed, not to where the version number came from. A recipe can perfectly well have
`source.kind = github_release` and `update.cmd = "brew upgrade foo"`.

### 2. Scheduler

New `Sources/UpdateBarCore/Update/UpdateScheduler.swift`. Pure scheduling, no I/O, independently
testable with synthetic work.

- A serial `DispatchQueue` guards scheduler state: pending items, busy lane set, in-flight count.
- Up to `maxConcurrent` workers dispatched on `DispatchQueue.global(qos: .userInitiated)`.
- Each worker loops: pull the next pending item whose lane is free, run it, release the lane,
  repeat. A worker exits when nothing is pullable and nothing is in flight.
- `DispatchGroup.wait()` joins.

This matches the GCD idiom already used in `ProcessRunner`
(`Sources/UpdateBarMenuBar/UpdateBarCLIClient.swift:312`) rather than introducing async/await into
a synchronous call path.

Before pulling each item a worker checks two stop signals (see §5).

### 3. Progress events

New `Sources/UpdateBarCore/Models/UpdateProgressEvent.swift`:

```swift
public enum UpdateProgressEvent: Equatable {
    case planned([UpdatePlanItem])
    case itemStarted(id: String, name: String)
    case itemFinished(UpdateResult)
}
```

This follows the existing `RegistryService.check(onEvent:)` precedent
(`Sources/UpdateBarCore/Registry/RegistryService.swift:44`). It is an enum rather than a struct
mirroring `CheckProgressEvent` because `.planned` carries a plan payload that the flat
struct-with-optional-result shape cannot express without dead fields.

### 4. UpdateRunner

```swift
public func update(
    ids: [String],
    all: Bool,
    assumeYes: Bool,
    onEvent: ((UpdateProgressEvent) throws -> Void)? = nil,
    stopSignal: UpdateStopSignal? = nil
) throws -> [UpdateResult]
```

`UpdateStopSignal` is a lock-guarded `@unchecked Sendable` final class mirroring `CancellationToken`
(`Sources/UpdateBarCore/Execution/ExecutionPolicy.swift:25`). A bare `() -> Bool` closure cannot
cross to worker threads under the package's Swift 6 language mode, and neither `CommandRunning` nor
`HTTPClient` is `Sendable`, so the stop signal has to be a shared reference type rather than a
closure.

Both new parameters default to `nil`, so every existing call site compiles unchanged.

- Concurrency comes from `config.update.maxConcurrent`.
- Plan classification (skipped / missing / not-confirmed) stays sequential and up front; it is pure
  and cheap. Only `.willUpdate` items enter the scheduler.
- Results are collected by plan index and re-emitted **in plan order**, so `--json` and human stdout
  are byte-identical to today for every non-stop path.

### 5. Stop semantics

Two distinct signals, deliberately not the same thing:

| | Trigger | Running command | Queued items | Outcome |
|---|---|---|---|---|
| Stop (drain) | Menu bar "Stop After Current" | runs to completion | never started | `.updated` / `.failed` |
| Hard cancel | CLI Ctrl-C (SIGINT) | process killed | never started | `.cancelled` |

Stop is `stopSignal`. Hard cancel is the existing `CancellationToken` threaded into
`CommandExecutor`, handled by `SignalCancellationHandler`
(`Sources/UpdateBarCLI/CLIExecutionSupport.swift:16`).

The menu bar no longer hard-cancels. Killing a half-finished `brew upgrade` can leave a package in
a partially installed state that UpdateBar cannot describe, and today's `.cancelled` outcome is a
hard failure that leaves item state untouched — the app ends up not knowing what happened. Draining
the queue is the safe version of the same user intent, and it only became a meaningful option once
parallelism introduced a queue.

**Accepted trade-off:** with hard cancel gone from the menu bar, a hung update command blocks the
action for up to the 30 minute `ExecutionPolicy` timeout
(`Sources/UpdateBarCore/Update/UpdateRunner.swift:98`). Quitting the app is the only escape. Owner
approved this on 2026-07-30.

Items that were never started produce no result, exactly as today's `break`
(`Sources/UpdateBarCore/Update/UpdateRunner.swift:67`) behaves.

### 6. History append race

`HistoryStore.append` (`Sources/UpdateBarCore/Status/HistoryStore.swift:62`) reads the whole file,
appends a line, and atomically rewrites it — with no lock. Sequential execution hid this. Under
parallel updates two concurrent appends race and the later write silently drops the earlier event.

Wrap the read-modify-write in a `FileLock` on `history.lock`, mirroring
`StateStore.withExclusiveLock` (`Sources/UpdateBarCore/Registry/StateStore.swift:54`). The lock
must cover the whole read-modify-write, not just the write.

State and manifest writes are already `flock`-protected and need no change
(`Sources/UpdateBarCore/Registry/RegistryService.swift:53`,
`Sources/UpdateBarCore/Update/UpdateRunner.swift:161`).

### 7. Config

```swift
public struct UpdateConfig: Equatable, Sendable {
    public var maxConcurrent: Int   // default 3, valid 1...8
}
```

- Key `update.max_concurrent`, added to `Config.knownKeys`, `set`, and `get`.
- Non-integer or out-of-range values throw `ConfigError.invalidValue`.
- `ConfigStore.render` gains an `[update]` section. Older `config.toml` files simply lack it and
  fall back to the default; the parser is already tolerant
  (`Sources/UpdateBarCore/Config/ConfigStore.swift:50`).

**Approved stdout changes.** Both approved explicitly per the stable-stdout rule, the first on
2026-07-30 and the second on 2026-07-31:

1. `updatebar config get --json` gains an `update` object.
2. The plain-text `updatebar config get` gains an `[update]` section. `ConfigStore.render` backs
   both the on-disk file and the display path, so writing the new key to disk necessarily shows it
   on screen. Keeping the two in step is the intended behavior; decoupling them was considered and
   rejected as needless machinery that would hide `max_concurrent` from the most obvious way to
   look at config.

Both are additive: no existing key, value format, or ordering changes.

**Known forward-compatibility risk (accepted).** A config file containing `[update]` throws
`ConfigError.corruptConfig` on a pre-0.5 binary, because `ConfigStore.parse`
(`Sources/UpdateBarCore/Config/ConfigStore.swift:50`) routes unknown keys through `Config.set`,
which throws `unknownKey`. Its skip-list only covers keys deprecated in the other direction, and
cannot list a key that did not exist when the older binary was built. So upgrade → any `config set`
(which rewrites the file) → downgrade produces a hard config error. This is inherent to the
parser's fail-closed design and predates this change; recorded here rather than fixed, since the
fix belongs in the parser and is a separate decision.

### 8. CLI

- `updatebar update --jobs N` overrides the config value for one run.
- `--json` and human stdout shapes are unchanged.
- `--json-stream` currently fakes per-item progress by calling `runner.update(ids: [item.id])` once
  per item (`Sources/UpdateBarCLI/CLIUpdateCommand.swift:135`), which would bypass the scheduler
  entirely. Rewrite it to drive a single `runner.update(…, onEvent:)` call and emit
  `MachineEvent`s from the callback. Event types and fields are unchanged; only the interleaving of
  `itemStarted` / `itemFinished` differs, which is inherent to a progress stream. The terminal
  `.finished` event still carries results in plan order.

### 9. Menu bar

`MenuBarActiveAction` gains, all mutated on the main queue only:

```swift
var plannedItemIDs: [String]      // from .planned
var inFlightItemIDs: Set<String>
var finishedItemIDs: Set<String>
var stopRequested: Bool
```

Progress callbacks hop to `DispatchQueue.main.async` before touching them.

`MenuBarMenuModelBuilder.makeMenu` drops the early return at
`Sources/UpdateBarMenuBar/MenuBarMenuModel.swift:98` and takes a new
`activeItemProgress: MenuBarItemProgress?` parameter. Rendering while an action is active:

| Row | Treatment |
|---|---|
| header | `Updating approved items… (2/7)` |
| stop | `Stop After Current`, or `Stopping…` disabled once requested |
| in-flight item | `name 1.2 -> 1.3 — updating…`, disabled, `arrow.triangle.2.circlepath` |
| planned, not started | `— queued`, disabled |
| finished | `— done`, disabled |
| other items | disabled, tooltip "Another action is running." |
| Check Now / Refresh Status / Update All | disabled |
| Overview / Manage / Scan / Open TUI / Preferences / Quit | **stay enabled** |

Disabled means `action: nil`, which is how `appendDisabled` already works. `MenuBarMenuItem` needs
no new field.

Menu rebuilds are throttled to roughly 300 ms. Rebuilding on every progress event replaces
`statusItem.menu` while the menu may be open, which flickers.

The status icon stays `.checking` while an action is active, as it does today.

## Testing

- `UpdateLaneTests` — `sudo brew upgrade x`, `FOO=1 npm i -g y`, `/opt/homebrew/bin/brew …`, empty
  string, unparseable command.
- `UpdateSchedulerTests` — lane exclusivity, observed concurrency never exceeds the limit, drain
  stops pulling new work, all items complete when unconstrained.
- `UpdateRunnerTests` — results in plan order, progress event sequence, and a mock command runner
  that records start/end timestamps to prove same-lane recipes never overlap.
- `HistoryStoreTests` — concurrent appends lose no events.
- `ConfigTests` — set/get, clamping, invalid values, TOML round-trip, missing `[update]` section.
- `MenuBarMenuModelTests` — menu is not collapsed during an action, per-item annotations, footer
  actions remain enabled, stop row states.
- Tests keep all writes inside their sandboxed test home directories, per existing convention.

## Rollout

Behavior-sized change, so it gets an OpenSpec entry under
`openspec/changes/parallel-update-per-item-progress/`.

`Scripts/quality-gate.sh` is the completion gate. If the CLI gains `--jobs`, the corresponding
`-test.sh` twin moves with it.
