# Parallel Updates With Per-Item Menu Bar Progress — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run UpdateBar's updates with bounded parallelism (default 3, never two recipes on the same package manager at once) and stop the menu bar from collapsing into a single "Updating…" line while an action runs.

**Architecture:** `UpdateBarCore` gains a lane-keyed worker pool inside `UpdateRunner`, plus a progress-event callback. The menu bar consumes those events to annotate individual rows instead of replacing the whole menu. Hard cancel stays a CLI-only (Ctrl-C) capability; the menu bar gets a "Stop After Current" drain instead.

**Tech Stack:** Swift 6 (language mode 6, strict concurrency), SwiftPM, XCTest, GCD (`DispatchQueue`/`DispatchGroup`), AppKit for the menu bar. Only existing dependencies — swift-argument-parser and Sparkle. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-07-30-parallel-update-per-item-progress-design.md`

## Global Constraints

- Swift tools version 6.0, platform floor macOS 13. `Package.swift` sets no `swiftLanguageMode`, so **Swift 6 strict concurrency is in force**. `CommandRunning` and `HTTPClient` are NOT `Sendable`; cross-thread state uses the codebase's existing `final class … @unchecked Sendable` + lock idiom (see `CancellationToken` in `Sources/UpdateBarCore/Execution/ExecutionPolicy.swift:25`, `LockedData` in `Sources/UpdateBarMenuBar/UpdateBarCLIClient.swift:410`).
- **No new package dependencies.**
- `UpdateBarCore` must stay free of `print()`, CLI formatting, and UI concerns. Presentation lives in `UpdateBarCLI` / `UpdateBarMenuBar` / `UpdateBarMenuBarApp`.
- Machine-readable **stdout shapes are a stable contract**. The only approved change in this plan is `updatebar config get --json` gaining an `update` object (approved by the owner on 2026-07-30). Everything else must stay byte-identical.
- Tests never write outside a temporary test home directory. Use the existing `temporaryDirectory()` + `AppPaths(homeDirectory:)` pattern.
- `.swift-format` governs formatting. Run `swift format --in-place` (or the repo's configured invocation) rather than hand-styling.
- `Scripts/quality-gate.sh` is THE completion gate. Any `Scripts/foo.sh` change moves together with its `Scripts/foo-test.sh` twin.
- Commit subjects in this repo are plain imperative sentences ("Fix singular menu attention copy"), not Conventional Commits. Match that. End commit messages with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

---

## File Structure

**Create**
| Path | Responsibility |
|---|---|
| `Sources/UpdateBarCore/Update/UpdateLane.swift` | Pure function: `update.cmd` → package-manager lane key |
| `Sources/UpdateBarCore/Update/UpdateStopSignal.swift` | Lock-guarded drain flag, Sendable across threads |
| `Sources/UpdateBarCore/Update/UpdateScheduler.swift` | Bounded-concurrency worker pool with lane exclusivity |
| `Sources/UpdateBarCore/Models/UpdateProgressEvent.swift` | `planned` / `itemStarted` / `itemFinished` events |
| `Sources/UpdateBarMenuBar/MenuBarItemProgress.swift` | Value type the menu builder reads to annotate rows |
| `Tests/UpdateBarCoreTests/UpdateLaneTests.swift` | |
| `Tests/UpdateBarCoreTests/UpdateSchedulerTests.swift` | |
| `openspec/changes/parallel-update-per-item-progress/` | proposal / design / tasks / spec delta |

**Modify**
| Path | Change |
|---|---|
| `Sources/UpdateBarTestSupport/MockCommandExecutor.swift` | Make thread-safe (parallel tests hit it from many threads) |
| `Sources/UpdateBarCore/Status/HistoryStore.swift` | Lock the append read-modify-write |
| `Sources/UpdateBarCore/Config/Config.swift` | Add `UpdateConfig.maxConcurrent` |
| `Sources/UpdateBarCore/Config/ConfigStore.swift` | Render/parse `[update]` section |
| `Sources/UpdateBarCore/Update/UpdateRunner.swift` | Three-phase parallel `update(…)` |
| `Sources/UpdateBarCLI/CLIPayloads.swift` | `ConfigDumpPayload` gains `update` |
| `Sources/UpdateBarCLI/CLIUpdateCommand.swift` | `--jobs`, callback-driven `--json-stream` |
| `Sources/UpdateBarMenuBar/MenuBarActionCoordinator.swift` | Per-item tracking + stop instead of cancel |
| `Sources/UpdateBarMenuBar/MenuBarMenuModel.swift` | Remove the collapse; annotate rows |
| `Sources/UpdateBarMenuBar/MenuBarMenuAction.swift` | Rename the cancel action |
| `Sources/UpdateBarMenuBar/MenuBarService.swift` | Protocol gains progress/stop parameters |
| `Sources/UpdateBarMenuBar/UpdateBarCLIClient.swift` | Conform to the widened protocol |
| `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift` | Wire progress → main queue → throttled rebuild |
| `docs/cli.md`, `docs/menu-bar.md` | Document `--jobs`, `update.max_concurrent`, stop semantics |
| Existing tests listed per task | |

---

### Task 1: Make the test command runners thread-safe

Parallel updates call the injected `CommandRunning` from several worker threads at once. Both test doubles — `MockCommandExecutor` and the private `RecordingCommandRunner` in `Tests/UpdateBarMenuBarTests/CoreMenuBarServiceTests.swift:297` — do an unsynchronised `commands.append`, which becomes a data race the moment Task 6 lands. Fix them first so later tasks have sound doubles.

**Files:**
- Modify: `Sources/UpdateBarTestSupport/MockCommandExecutor.swift`
- Modify: `Tests/UpdateBarMenuBarTests/CoreMenuBarServiceTests.swift:297-312`
- Test: no new test; verify via `swift build` and the existing suite.

**Interfaces:**
- Consumes: nothing.
- Produces: `MockCommandExecutor` is `@unchecked Sendable`; `commands: [ShellCommand]` is a computed snapshot; new `var recordedCommandTexts: [String]` returns `commands.map(\.command)` sorted for order-independent assertions; new `func setDelay(_:forCommand:)` makes a command block so tests can observe overlap. `RecordingCommandRunner` gains the same lock and snapshot semantics but no delay hook.

- [ ] **Step 1: Rewrite the mock with a lock**

Replace the whole body of `Sources/UpdateBarTestSupport/MockCommandExecutor.swift`:

```swift
import Foundation
import UpdateBarCore

/// Thread-safe because UpdateRunner executes recipes on a worker pool; several
/// threads call `run` concurrently.
public final class MockCommandExecutor: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResults: [String: CommandResult]
    private var recorded: [ShellCommand] = []
    private var delays: [String: TimeInterval] = [:]

    public init(results: [String: CommandResult]) {
        self.storedResults = results
    }

    public var results: [String: CommandResult] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedResults
        }
        set {
            lock.lock()
            storedResults = newValue
            lock.unlock()
        }
    }

    /// Commands in the order they were observed. Under parallel execution the
    /// order across different recipes is not deterministic; prefer
    /// `recordedCommandTexts` when asserting on a multi-item run.
    public var commands: [ShellCommand] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// Sorted command texts, safe to assert on regardless of scheduling order.
    public var recordedCommandTexts: [String] {
        commands.map(\.command).sorted()
    }

    /// Makes a command block for `seconds` so tests can observe overlap.
    public func setDelay(_ seconds: TimeInterval, forCommand command: String) {
        lock.lock()
        delays[command] = seconds
        lock.unlock()
    }

    public func run(_ command: ShellCommand, policy: ExecutionPolicy) throws -> CommandResult {
        lock.lock()
        recorded.append(command)
        let result = storedResults[command.command]
        let delay = delays[command.command]
        lock.unlock()

        if let delay {
            Thread.sleep(forTimeInterval: delay)
        }
        guard let result else {
            throw MockError.missingCommand(command.command)
        }
        return result
    }

    public enum MockError: Error {
        case missingCommand(String)
    }
}
```

- [ ] **Step 2: Give `RecordingCommandRunner` the same treatment**

In `Tests/UpdateBarMenuBarTests/CoreMenuBarServiceTests.swift`, replace the private class at line 297:

```swift
private final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResults: [String: CommandResult]
    private var recorded: [ShellCommand] = []

    init(results: [String: CommandResult]) {
        self.storedResults = results
    }

    var results: [String: CommandResult] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedResults
        }
        set {
            lock.lock()
            storedResults = newValue
            lock.unlock()
        }
    }

    var commands: [ShellCommand] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func run(_ command: ShellCommand, policy: ExecutionPolicy) throws -> CommandResult {
        lock.lock()
        recorded.append(command)
        let result = storedResults[command.command]
        lock.unlock()

        guard let result else {
            throw MissingCommandError(command.command)
        }
        return result
    }
}
```

Add `import Foundation` to the top of the file if it is missing.

- [ ] **Step 3: Build and run the full suite to confirm nothing regressed**

Run: `swift build && swift test 2>&1 | tail -20`
Expected: build succeeds; the suite passes exactly as it did before this task. `MockError` changed from internal to `public`, which is additive.

- [ ] **Step 4: Commit**

```bash
git add Sources/UpdateBarTestSupport/MockCommandExecutor.swift Tests/UpdateBarMenuBarTests/CoreMenuBarServiceTests.swift
git commit -m "$(cat <<'EOF'
Make the test command runners thread-safe

Parallel update execution calls the injected CommandRunning from several
worker threads. Guard the recorded-command list and results map with a
lock in both doubles, and add an optional per-command delay to
MockCommandExecutor so tests can observe overlap.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `UpdateLane` — derive the package-manager lane from `update.cmd`

Two recipes driven by the same tool must never run at once, because Homebrew and friends hold a process-wide lock. The tool being executed — not `Recipe.source.kind` — is what holds that lock, so the key comes from `update.cmd`.

**Files:**
- Create: `Sources/UpdateBarCore/Update/UpdateLane.swift`
- Test: `Tests/UpdateBarCoreTests/UpdateLaneTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum UpdateLane { static func key(forCommand command: String) -> String? }`. Internal (not `public`) — only `UpdateRunner` uses it, and `UpdateLaneTests` reaches it via `@testable import UpdateBarCore`.

- [ ] **Step 1: Write the failing test**

Create `Tests/UpdateBarCoreTests/UpdateLaneTests.swift`:

```swift
@testable import UpdateBarCore
import XCTest

final class UpdateLaneTests: XCTestCase {
    func testUsesFirstCommandToken() {
        XCTAssertEqual(UpdateLane.key(forCommand: "brew upgrade ripgrep"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "npm"), "npm")
    }

    func testStripsDirectoryAndLowercases() {
        XCTAssertEqual(UpdateLane.key(forCommand: "/opt/homebrew/bin/brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "/usr/local/bin/NPM install -g y"), "npm")
    }

    func testSkipsWrapperCommands() {
        XCTAssertEqual(UpdateLane.key(forCommand: "sudo brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "sudo -u kendrick brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "env brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "nohup nice cargo install-update -a"), "cargo")
    }

    func testBooleanWrapperFlagsDoNotSwallowTheToolName() {
        XCTAssertEqual(UpdateLane.key(forCommand: "sudo -n brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "sudo -E brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "sudo -S brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "env -i brew upgrade x"), "brew")
        XCTAssertEqual(
            UpdateLane.key(forCommand: "sudo --non-interactive brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "nice -n 10 brew upgrade x"), "brew")
        XCTAssertEqual(UpdateLane.key(forCommand: "exec -a foo brew upgrade x"), "brew")
    }

    func testValueTakingWrapperFlagsSkipTheirArgument() {
        XCTAssertEqual(UpdateLane.key(forCommand: "sudo -u kendrick -n brew upgrade x"), "brew")
        // `env -S` genuinely takes a string, unlike `sudo -S`.
        XCTAssertEqual(UpdateLane.key(forCommand: "env -S brew upgrade x"), "upgrade")
    }

    func testSkipsLeadingEnvironmentAssignments() {
        XCTAssertEqual(UpdateLane.key(forCommand: "FOO=1 npm install -g y"), "npm")
        XCTAssertEqual(UpdateLane.key(forCommand: "A=1 B=2 env brew upgrade x"), "brew")
    }

    func testTreatsNonAssignmentEqualsAsCommand() {
        XCTAssertEqual(UpdateLane.key(forCommand: "9bad=x brew upgrade"), "9bad=x")
    }

    func testReturnsNilWhenNothingUsableRemains() {
        XCTAssertNil(UpdateLane.key(forCommand: ""))
        XCTAssertNil(UpdateLane.key(forCommand: "   "))
        XCTAssertNil(UpdateLane.key(forCommand: "sudo env"))
        XCTAssertNil(UpdateLane.key(forCommand: "FOO=1"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter UpdateLaneTests 2>&1 | tail -20`
Expected: FAIL — compile error, `cannot find 'UpdateLane' in scope`.

- [ ] **Step 3: Implement `UpdateLane`**

Create `Sources/UpdateBarCore/Update/UpdateLane.swift`:

```swift
import Foundation

/// Derives the package manager an update command will contend on.
///
/// Homebrew, npm, and similar tools take a process-wide lock, so two recipes
/// that resolve to the same lane must never run at the same time. The lane is
/// read from `update.cmd` rather than `Recipe.source.kind` because the lock
/// belongs to the tool being executed, not to where the version came from: a
/// recipe can have `source.kind == .githubRelease` and
/// `update.cmd == "brew upgrade foo"`.
enum UpdateLane {
    private static let wrappers: Set<String> = [
        "sudo", "env", "command", "nice", "nohup", "time", "exec",
    ]

    /// Flags that consume the following token, scoped to the wrapper that owns
    /// them. A flat set cannot work: `sudo -S` is boolean while `env -S` takes
    /// a string, and guessing from token shape swallows the tool name whenever
    /// a boolean flag precedes it (`sudo -n brew upgrade x` -> "upgrade").
    private static let wrapperValueFlags: [String: Set<String>] = [
        "sudo": ["-u", "-g", "-h", "-p", "-r", "-t", "-C", "-D", "-R", "-T", "-U"],
        "env": ["-u", "-S"],
        "nice": ["-n"],
        "time": ["-o", "-f"],
        "exec": ["-a"],
    ]

    /// Returns `nil` when no tool name can be read.
    static func key(forCommand command: String) -> String? {
        let tokens = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var index = 0
        var currentWrapper: String?

        while index < tokens.count {
            let text = tokens[index]

            if isEnvironmentAssignment(text) {
                index += 1
                continue
            }

            if text.hasPrefix("-") {
                if let currentWrapper,
                    wrapperValueFlags[currentWrapper]?.contains(text) == true,
                    index + 1 < tokens.count
                {
                    index += 2
                } else {
                    index += 1
                }
                continue
            }

            let name = URL(fileURLWithPath: text).lastPathComponent.lowercased()
            if name.isEmpty || name == "/" {
                index += 1
                continue
            }
            if wrappers.contains(name) {
                currentWrapper = name
                index += 1
                continue
            }
            return name
        }
        return nil
    }

    private static func isEnvironmentAssignment(_ token: String) -> Bool {
        guard let equals = token.firstIndex(of: "=") else { return false }
        let name = token[token.startIndex..<equals]
        guard let first = name.first, first == "_" || first.isLetter else { return false }
        return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter UpdateLaneTests 2>&1 | tail -20`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/UpdateBarCore/Update/UpdateLane.swift Tests/UpdateBarCoreTests/UpdateLaneTests.swift
git commit -m "$(cat <<'EOF'
Add UpdateLane to derive package manager from update.cmd

Bounded-parallel updates must not run two recipes on the same package
manager at once. The lane key comes from the update command's tool name,
skipping wrapper commands and leading environment assignments.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `UpdateStopSignal` and `UpdateScheduler`

The scheduler is pure coordination — no file or process I/O — so it is testable on its own with synthetic work.

Why a class and not a `() -> Bool` closure for the stop flag: under Swift 6 language mode a bare closure cannot be shared across worker threads. `UpdateStopSignal` mirrors `CancellationToken` (`Sources/UpdateBarCore/Execution/ExecutionPolicy.swift:25`) exactly.

**Files:**
- Create: `Sources/UpdateBarCore/Update/UpdateStopSignal.swift`
- Create: `Sources/UpdateBarCore/Update/UpdateScheduler.swift`
- Test: `Tests/UpdateBarCoreTests/UpdateSchedulerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public final class UpdateStopSignal: @unchecked Sendable` with `init()`, `var isStopRequested: Bool`, `func requestStop()`.
  - `final class UpdateScheduler<Payload, Output>: @unchecked Sendable` (internal) with
    - nested `struct Item { let index: Int; let lane: String; let payload: Payload }`
    - `init(items: [Item], stopSignal: UpdateStopSignal?, onStart: ((Payload) throws -> Void)?, onFinish: ((Output) throws -> Void)?, shouldStopAfter: ((Output) -> Bool)?, work: @escaping (Payload) throws -> Output)`
    - `func run(maxConcurrent: Int) throws -> [Int: Output]`
  - `run` blocks until every started item finishes. Items never started (because of stop) are absent from the returned dictionary. `onStart`, `onFinish`, and `shouldStopAfter` are delivered serially under the scheduler's internal queue, so callers do not need their own lock — but they are not delivered on any particular thread. Only `work` runs concurrently.

- [ ] **Step 1: Write the failing tests**

Create `Tests/UpdateBarCoreTests/UpdateSchedulerTests.swift`:

```swift
import Foundation
@testable import UpdateBarCore
import XCTest

final class UpdateSchedulerTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var running = 0
        private(set) var peak = 0
        private(set) var laneOverlaps: [String] = []
        private var busyLanes: [String: Int] = [:]

        func enter(lane: String) {
            lock.lock()
            running += 1
            peak = max(peak, running)
            let count = (busyLanes[lane] ?? 0) + 1
            busyLanes[lane] = count
            if count > 1 { laneOverlaps.append(lane) }
            lock.unlock()
        }

        func leave(lane: String) {
            lock.lock()
            running -= 1
            busyLanes[lane] = (busyLanes[lane] ?? 1) - 1
            lock.unlock()
        }
    }

    private func items(_ lanes: [String]) -> [UpdateScheduler<String, String>.Item] {
        lanes.enumerated().map { .init(index: $0.offset, lane: $0.element, payload: $0.element) }
    }

    func testRunsEveryItemAndKeysResultsByIndex() throws {
        let scheduler = UpdateScheduler<String, String>(
            items: items(["a", "b", "c"]),
            stopSignal: nil,
            onStart: nil,
            onFinish: nil,
            shouldStopAfter: nil,
            work: { "done-\($0)" }
        )

        let outputs = try scheduler.run(maxConcurrent: 3)

        XCTAssertEqual(outputs, [0: "done-a", 1: "done-b", 2: "done-c"])
    }

    func testDeliversStartAndFinishCallbacksSerially() throws {
        var log: [String] = []
        let scheduler = UpdateScheduler<String, String>(
            items: items(["a", "b", "c"]),
            stopSignal: nil,
            // No lock here on purpose: the scheduler must serialise these.
            onStart: { log.append("start-\($0)") },
            onFinish: { log.append("finish-\($0)") },
            shouldStopAfter: nil,
            work: { $0 }
        )

        _ = try scheduler.run(maxConcurrent: 3)

        XCTAssertEqual(log.count, 6)
        XCTAssertEqual(log.filter { $0.hasPrefix("start-") }.count, 3)
        XCTAssertEqual(log.filter { $0.hasPrefix("finish-") }.count, 3)
    }

    func testNeverExceedsMaxConcurrent() throws {
        let recorder = Recorder()
        let scheduler = UpdateScheduler<String, String>(
            items: items(["a", "b", "c", "d", "e", "f"]),
            stopSignal: nil,
            onStart: nil,
            onFinish: nil,
            shouldStopAfter: nil,
            work: { lane in
                recorder.enter(lane: lane)
                Thread.sleep(forTimeInterval: 0.05)
                recorder.leave(lane: lane)
                return lane
            }
        )

        _ = try scheduler.run(maxConcurrent: 2)

        XCTAssertLessThanOrEqual(recorder.peak, 2)
        XCTAssertGreaterThan(recorder.peak, 1, "expected actual parallelism")
    }

    func testSameLaneItemsNeverOverlap() throws {
        let recorder = Recorder()
        let scheduler = UpdateScheduler<String, String>(
            items: items(["brew", "brew", "brew", "npm"]),
            stopSignal: nil,
            onStart: nil,
            onFinish: nil,
            shouldStopAfter: nil,
            work: { lane in
                recorder.enter(lane: lane)
                Thread.sleep(forTimeInterval: 0.05)
                recorder.leave(lane: lane)
                return lane
            }
        )

        let outputs = try scheduler.run(maxConcurrent: 3)

        XCTAssertEqual(outputs.count, 4)
        XCTAssertEqual(recorder.laneOverlaps, [])
    }

    func testStopSignalPreventsNewItemsFromStarting() throws {
        let stopSignal = UpdateStopSignal()
        let scheduler = UpdateScheduler<String, String>(
            items: items(["a", "b", "c", "d"]),
            stopSignal: stopSignal,
            onStart: { _ in stopSignal.requestStop() },
            onFinish: nil,
            shouldStopAfter: nil,
            work: { $0 }
        )

        let outputs = try scheduler.run(maxConcurrent: 1)

        XCTAssertEqual(outputs, [0: "a"], "items after the stop request must not run")
    }

    func testShouldStopAfterDrainsRemainingItems() throws {
        let scheduler = UpdateScheduler<String, String>(
            items: items(["a", "b", "c"]),
            stopSignal: nil,
            onStart: nil,
            onFinish: nil,
            shouldStopAfter: { $0 == "a" },
            work: { $0 }
        )

        let outputs = try scheduler.run(maxConcurrent: 1)

        XCTAssertEqual(outputs, [0: "a"])
    }

    func testRethrowsWorkError() {
        struct Boom: Error {}
        let scheduler = UpdateScheduler<String, String>(
            items: items(["a"]),
            stopSignal: nil,
            onStart: nil,
            onFinish: nil,
            shouldStopAfter: nil,
            work: { _ in throw Boom() }
        )

        XCTAssertThrowsError(try scheduler.run(maxConcurrent: 2)) { error in
            XCTAssertTrue(error is Boom)
        }
    }

    func testRethrowsFinishCallbackError() {
        struct Boom: Error {}
        let scheduler = UpdateScheduler<String, String>(
            items: items(["a"]),
            stopSignal: nil,
            onStart: nil,
            onFinish: { _ in throw Boom() },
            shouldStopAfter: nil,
            work: { $0 }
        )

        XCTAssertThrowsError(try scheduler.run(maxConcurrent: 1)) { error in
            XCTAssertTrue(error is Boom)
        }
    }

    func testEmptyItemListReturnsEmpty() throws {
        let scheduler = UpdateScheduler<String, String>(
            items: [],
            stopSignal: nil,
            onStart: nil,
            onFinish: nil,
            shouldStopAfter: nil,
            work: { $0 }
        )

        XCTAssertEqual(try scheduler.run(maxConcurrent: 3), [:])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter UpdateSchedulerTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'UpdateScheduler' in scope`, `cannot find 'UpdateStopSignal' in scope`.

- [ ] **Step 3: Implement `UpdateStopSignal`**

Create `Sources/UpdateBarCore/Update/UpdateStopSignal.swift`:

```swift
import Foundation

/// Cooperative "finish what is running, start nothing new" flag.
///
/// Distinct from `CancellationToken`: cancelling kills the running process and
/// can leave a package half-installed, while stopping only drains the queue.
public final class UpdateStopSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    public init() {}

    public var isStopRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    public func requestStop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}
```

- [ ] **Step 4: Implement `UpdateScheduler`**

Create `Sources/UpdateBarCore/Update/UpdateScheduler.swift`:

```swift
import Foundation

/// Runs work items with bounded concurrency while guaranteeing that two items
/// sharing a lane never run at the same time.
///
/// `@unchecked Sendable` because every mutable field is only touched inside
/// `queue`, the same discipline `ProcessRunner` and `LockedData` use. The
/// stored `work` closure is invoked from worker threads by design.
final class UpdateScheduler<Payload, Output>: @unchecked Sendable {
    struct Item {
        let index: Int
        let lane: String
        let payload: Payload
    }

    private let queue = DispatchQueue(label: "com.updatebar.update-scheduler")
    private let stopSignal: UpdateStopSignal?
    private let onStart: ((Payload) throws -> Void)?
    private let onFinish: ((Output) throws -> Void)?
    private let shouldStopAfter: ((Output) -> Bool)?
    private let work: (Payload) throws -> Output

    private var pending: [Item]
    private var busyLanes: Set<String> = []
    private var outputs: [Int: Output] = [:]
    private var thrown: Error?
    private var drained = false

    init(
        items: [Item],
        stopSignal: UpdateStopSignal?,
        onStart: ((Payload) throws -> Void)?,
        onFinish: ((Output) throws -> Void)?,
        shouldStopAfter: ((Output) -> Bool)?,
        work: @escaping (Payload) throws -> Output
    ) {
        self.pending = items
        self.stopSignal = stopSignal
        self.onStart = onStart
        self.onFinish = onFinish
        self.shouldStopAfter = shouldStopAfter
        self.work = work
    }

    /// Blocks until every started item finishes. Items that were never started
    /// are absent from the result.
    func run(maxConcurrent: Int) throws -> [Int: Output] {
        let workerCount = min(max(1, maxConcurrent), max(1, pending.count))
        guard !pending.isEmpty else { return [:] }

        let group = DispatchGroup()
        for _ in 0..<workerCount {
            DispatchQueue.global(qos: .userInitiated).async(group: group) { [self] in
                drainLoop()
            }
        }
        group.wait()

        if let thrown { throw thrown }
        return outputs
    }

    private func drainLoop() {
        while let item = claimNextItem() {
            do {
                try queue.sync { try onStart?(item.payload) }
                let output = try work(item.payload)
                complete(item, output: output)
            } catch {
                fail(item, error: error)
            }
        }
    }

    /// Marks a lane busy and hands back the item, or returns nil when this
    /// worker has nothing left it is allowed to start.
    private func claimNextItem() -> Item? {
        queue.sync {
            if drained || thrown != nil { return nil }
            if stopSignal?.isStopRequested == true {
                drained = true
                return nil
            }
            guard
                let position = pending.firstIndex(where: { !busyLanes.contains($0.lane) })
            else {
                return nil
            }
            let item = pending.remove(at: position)
            busyLanes.insert(item.lane)
            return item
        }
    }

    private func complete(_ item: Item, output: Output) {
        queue.sync {
            busyLanes.remove(item.lane)
            outputs[item.index] = output
            if shouldStopAfter?(output) == true {
                drained = true
            }
            do {
                try onFinish?(output)
            } catch {
                if thrown == nil { thrown = error }
            }
        }
    }

    private func fail(_ item: Item, error: Error) {
        queue.sync {
            busyLanes.remove(item.lane)
            if thrown == nil { thrown = error }
        }
    }
}
```

A note on why no worker starves: a worker that finds every pending lane busy exits, but the worker that is holding that lane releases it in `complete` *before* its next `claimNextItem`, so it picks the remaining same-lane items up itself. Work is never lost, and there is no waiting, so there is no deadlock.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter UpdateSchedulerTests 2>&1 | tail -20`
Expected: PASS, 9 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/UpdateBarCore/Update/UpdateStopSignal.swift Sources/UpdateBarCore/Update/UpdateScheduler.swift Tests/UpdateBarCoreTests/UpdateSchedulerTests.swift
git commit -m "$(cat <<'EOF'
Add UpdateScheduler and UpdateStopSignal

UpdateScheduler runs items with bounded concurrency and guarantees two
items sharing a lane never overlap. UpdateStopSignal is the cooperative
drain flag: finish what is running, start nothing new. Both are pure
coordination with no process or file I/O.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Lock `HistoryStore.append`

`HistoryStore.append` reads the whole file, appends a line, and atomically rewrites it — with no lock (`Sources/UpdateBarCore/Status/HistoryStore.swift:62`). Sequential execution hid this. Once updates run in parallel, two concurrent appends race and the later write silently drops the earlier event.

**Files:**
- Modify: `Sources/UpdateBarCore/Status/HistoryStore.swift`
- Test: `Tests/UpdateBarCoreTests/HistoryStoreTests.swift`

**Interfaces:**
- Consumes: `FileLock` from `Sources/UpdateBarCore/Registry/FileLock.swift` (internal, same module).
- Produces: `HistoryStore.append` is unchanged in signature and now safe under concurrency. New internal init parameter `lockURL` is derived, not passed.

- [ ] **Step 1: Write the failing test**

Append to `Tests/UpdateBarCoreTests/HistoryStoreTests.swift`, inside the existing `HistoryStoreTests` class:

```swift
    func testConcurrentAppendsLoseNoEvents() throws {
        let store = try makeStore()
        let total = 40

        DispatchQueue.concurrentPerform(iterations: total) { index in
            try? store.append(
                HistoryEvent(
                    event: .updateFinished,
                    id: "tool-\(index)",
                    outcome: "updated",
                    at: now.addingTimeInterval(Double(index))
                ))
        }

        let ids = Set(try store.events().compactMap(\.id))
        XCTAssertEqual(ids.count, total)
    }
```

Add `import Foundation` at the top of the file if it is not already there (it is).

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter HistoryStoreTests/testConcurrentAppendsLoseNoEvents 2>&1 | tail -20`
Expected: FAIL — `XCTAssertEqual failed: ("N") is not equal to ("40")` with N well below 40, because concurrent read-modify-write loses events. If it passes by luck, raise `total` to 200 and re-run; it must fail before the fix.

- [ ] **Step 3: Wrap the read-modify-write in a file lock**

In `Sources/UpdateBarCore/Status/HistoryStore.swift`, add a `lockFileURL` stored property and wrap the body of `append`:

```swift
public struct HistoryStore {
    private let fileURL: URL
    private let lockFileURL: URL
    private let maxBytes: Int

    public init(paths: AppPaths = AppPaths(), maxBytes: Int = 512 * 1024) {
        self.fileURL = paths.historyFile
        self.lockFileURL = paths.homeDirectory.appendingPathComponent("history.lock")
        self.maxBytes = maxBytes
    }

    public func append(_ event: HistoryEvent) throws {
        // JSONL requires exactly one line per event; the shared updateBar
        // encoder pretty-prints, so use a compact encoder here.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let line = try encoder.encode(event) + Data("\n".utf8)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // The lock must span the whole read-modify-write: parallel updates
        // append concurrently, and an unlocked rewrite drops the other
        // writer's event.
        try FileLock(url: lockFileURL).withExclusiveLock {
            let existing = (try? Data(contentsOf: fileURL)) ?? Data()
            var combined = existing + line
            if combined.count > maxBytes {
                combined = Self.trimmedToWholeLines(combined.suffix(maxBytes))
            }
            try combined.write(to: fileURL, options: .atomic)
        }
    }
```

Leave `events(since:)`, `trimmedToWholeLines`, and `HistoryEvent` untouched.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter HistoryStoreTests 2>&1 | tail -20`
Expected: PASS, all tests in the class including the new one.

- [ ] **Step 5: Commit**

```bash
git add Sources/UpdateBarCore/Status/HistoryStore.swift Tests/UpdateBarCoreTests/HistoryStoreTests.swift
git commit -m "$(cat <<'EOF'
Lock history appends against concurrent writers

HistoryStore.append reads the whole file, adds a line, and rewrites it.
Sequential updates hid the race; parallel updates drop events. Wrap the
read-modify-write in a FileLock on history.lock.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `update.max_concurrent` config key

**Files:**
- Modify: `Sources/UpdateBarCore/Config/Config.swift`
- Modify: `Sources/UpdateBarCore/Config/ConfigStore.swift:90-99` (the `render` function)
- Modify: `Sources/UpdateBarCLI/CLIPayloads.swift:98-118` (`ConfigDumpPayload`)
- Test: `Tests/UpdateBarCoreTests/ConfigStoreTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `Config.update: UpdateConfig`, `UpdateConfig.maxConcurrent: Int` (default 3, valid 1...8). Config key string is `update.max_concurrent`. `ConfigDumpPayload` gains `update.max_concurrent` in `updatebar config get --json`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/UpdateBarCoreTests/ConfigStoreTests.swift`, inside the existing test class:

```swift
    func testUpdateMaxConcurrentDefaultsToThree() {
        XCTAssertEqual(Config.default.update.maxConcurrent, 3)
        XCTAssertEqual(Config.default.get("update.max_concurrent"), "3")
        XCTAssertTrue(Config.knownKeys.contains("update.max_concurrent"))
    }

    func testUpdateMaxConcurrentSetAcceptsValidRange() throws {
        var config = Config.default
        try config.set("update.max_concurrent", value: "1")
        XCTAssertEqual(config.update.maxConcurrent, 1)
        try config.set("update.max_concurrent", value: "8")
        XCTAssertEqual(config.update.maxConcurrent, 8)
    }

    func testUpdateMaxConcurrentRejectsOutOfRangeAndNonInteger() {
        var config = Config.default
        for value in ["0", "9", "-1", "three", "", "3.5"] {
            XCTAssertThrowsError(try config.set("update.max_concurrent", value: value)) { error in
                XCTAssertEqual(
                    error as? ConfigError,
                    .invalidValue(key: "update.max_concurrent", value: value)
                )
            }
        }
        XCTAssertEqual(config.update.maxConcurrent, 3)
    }

    func testUpdateSectionRoundTripsThroughStore() throws {
        let root = try temporaryDirectory()
        let store = ConfigStore(paths: AppPaths(homeDirectory: root))
        var config = Config.default
        try config.set("update.max_concurrent", value: "5")

        try store.save(config)
        let reloaded = try store.load()

        XCTAssertEqual(reloaded.update.maxConcurrent, 5)
        XCTAssertTrue(store.renderForDisplay(config).contains("[update]"))
        XCTAssertTrue(store.renderForDisplay(config).contains("max_concurrent = 5"))
    }

    func testConfigWithoutUpdateSectionFallsBackToDefault() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
            [refresh]
            interval = "6h"

            [security]
            require_https_source = true

            """.write(to: paths.configFile, atomically: true, encoding: .utf8)

        let config = try ConfigStore(paths: paths).load()

        XCTAssertEqual(config.update.maxConcurrent, 3)
    }
```

If `ConfigStoreTests` has no `temporaryDirectory()` helper, add this private method to the class (mirroring `UpdateRunnerTests.swift:320`):

```swift
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-config-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ConfigStoreTests 2>&1 | tail -20`
Expected: FAIL — `value of type 'Config' has no member 'update'`.

- [ ] **Step 3: Add `UpdateConfig` to `Config`**

In `Sources/UpdateBarCore/Config/Config.swift`:

```swift
public struct Config: Equatable, Sendable {
    public var refresh: RefreshConfig
    public var security: SecurityConfig
    public var update: UpdateConfig

    public static let knownKeys = [
        "refresh.interval",
        "security.require_https_source",
        "update.max_concurrent",
    ]

    public static let `default` = Config(
        refresh: RefreshConfig(interval: Duration(hours: 6)),
        security: SecurityConfig(requireHTTPSSource: true),
        update: UpdateConfig(maxConcurrent: 3)
    )
```

Add to `set`, before `default:`:

```swift
        case "update.max_concurrent":
            update.maxConcurrent = try parseConcurrency(key: key, value: value)
```

Add to `get`, before `default:`:

```swift
        case "update.max_concurrent": String(update.maxConcurrent)
```

Add the parser next to `parseBool`:

```swift
    private func parseConcurrency(key: String, value: String) throws -> Int {
        guard let parsed = Int(value), UpdateConfig.validRange.contains(parsed) else {
            throw ConfigError.invalidValue(key: key, value: value)
        }
        return parsed
    }
```

Add the struct next to `SecurityConfig`:

```swift
public struct UpdateConfig: Equatable, Sendable {
    /// How many recipes may update at once. Upper bound is deliberately small:
    /// each slot is a real package-manager subprocess.
    public static let validRange = 1...8

    public var maxConcurrent: Int
}
```

- [ ] **Step 4: Render and parse the `[update]` section**

In `Sources/UpdateBarCore/Config/ConfigStore.swift`, replace the `render` function body:

```swift
    private func render(_ config: Config) -> String {
        """
        [refresh]
        interval = "\(config.refresh.interval)"

        [security]
        require_https_source = \(config.security.requireHTTPSSource)

        [update]
        max_concurrent = \(config.update.maxConcurrent)

        """
    }
```

`parse` needs no change: it already routes `section.key` through `config.set`, and a file without an `[update]` section simply leaves the default in place.

- [ ] **Step 5: Add `update` to the CLI config dump payload**

In `Sources/UpdateBarCLI/CLIPayloads.swift`, extend `ConfigDumpPayload`:

```swift
struct ConfigDumpPayload: Encodable {
    var refresh: Refresh
    var security: Security
    var update: Update

    init(config: Config) {
        refresh = Refresh(interval: config.refresh.interval.description)
        security = Security(requireHTTPSSource: config.security.requireHTTPSSource)
        update = Update(maxConcurrent: config.update.maxConcurrent)
    }

    struct Refresh: Encodable {
        var interval: String
    }

    struct Security: Encodable {
        var requireHTTPSSource: Bool

        enum CodingKeys: String, CodingKey {
            case requireHTTPSSource = "require_https_source"
        }
    }

    struct Update: Encodable {
        var maxConcurrent: Int

        enum CodingKeys: String, CodingKey {
            case maxConcurrent = "max_concurrent"
        }
    }
}
```

This is the one approved additive stdout change.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter ConfigStoreTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 7: Verify the CLI output by hand**

Run:
```bash
swift build --product updatebar
UPDATEBAR_HOME=$(mktemp -d) ./.build/debug/updatebar config get --json
UPDATEBAR_HOME=$(mktemp -d) ./.build/debug/updatebar config set update.max_concurrent 9; echo "exit=$?"
```
Expected: the JSON contains `"update" : { "max_concurrent" : 3 }`; the invalid `set` exits non-zero with an `invalid value` message on stderr.

- [ ] **Step 8: Commit**

```bash
git add Sources/UpdateBarCore/Config/Config.swift Sources/UpdateBarCore/Config/ConfigStore.swift Sources/UpdateBarCLI/CLIPayloads.swift Tests/UpdateBarCoreTests/ConfigStoreTests.swift
git commit -m "$(cat <<'EOF'
Add update.max_concurrent config key

Controls how many recipes update at once, default 3, valid 1 through 8.
Configs written before this key exists fall back to the default.
config get --json gains an additive update object.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Parallel `UpdateRunner` with progress events

The heart of the change. `update(…)` becomes three phases: sequential pure classification, bounded-parallel execution, then re-emission in plan order so stdout stays byte-identical.

**Files:**
- Create: `Sources/UpdateBarCore/Models/UpdateProgressEvent.swift`
- Modify: `Sources/UpdateBarCore/Update/UpdateRunner.swift:41-71` (the `update` function) and the type declaration at line 3
- Test: `Tests/UpdateBarCoreTests/UpdateRunnerTests.swift`

**Interfaces:**
- Consumes: `UpdateLane.key(forCommand:)` (Task 2), `UpdateScheduler` / `UpdateStopSignal` (Task 3), `Config.update.maxConcurrent` (Task 5), thread-safe `MockCommandExecutor` (Task 1).
- Produces:
  - `public enum UpdateProgressEvent: Equatable { case planned([UpdatePlanItem]); case itemStarted(id: String, name: String); case itemFinished(UpdateResult) }`
  - `UpdateRunner.update(ids:all:assumeYes:onEvent:stopSignal:)` — both new parameters default to `nil`, so all existing call sites compile unchanged.
  - `UpdateRunner` becomes `@unchecked Sendable`.
  - Event delivery is serial but not on a fixed thread. Consumers that need the main thread must hop themselves.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/UpdateBarCoreTests/UpdateRunnerTests.swift`, inside the existing class:

```swift
    func testRunnerReturnsResultsInPlanOrderWhenRunningInParallel() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let ids = ["alpha", "bravo", "charlie", "delta"]
        try ManifestStore(paths: paths).save(manifest(items: ids.map { recipe(id: $0) }))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: Dictionary(uniqueKeysWithValues: ids.map { ($0, itemState(status: .outdated)) })
            ))
        var results: [String: CommandResult] = [:]
        for id in ids {
            results["\(id) update"] = CommandResult(exitCode: 0, stdout: "updated", stderr: "")
            results["\(id) current"] = CommandResult(exitCode: 0, stdout: "\(id) 1.1.0", stderr: "")
            results["\(id) latest"] = CommandResult(exitCode: 0, stdout: "\(id) 1.1.0", stderr: "")
        }
        let commands = MockCommandExecutor(results: results)
        let runner = updateRunner(paths: paths, commands: commands)

        let updates = try runner.update(ids: [], all: true, assumeYes: true)

        XCTAssertEqual(updates.map(\.id), ids, "results must follow plan order, not finish order")
        XCTAssertEqual(updates.map(\.outcome), [.updated, .updated, .updated, .updated])
    }

    func testRunnerSerializesRecipesSharingAPackageManagerLane() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let ids = ["one", "two", "three"]
        var recipes: [Recipe] = []
        for id in ids {
            var item = recipe(id: id)
            item.update = UpdateSpec(cmd: "brew upgrade \(id)", cwd: nil)
            TestApprovals.approveAllCommands(in: &item)
            recipes.append(item)
        }
        try ManifestStore(paths: paths).save(manifest(items: recipes))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: Dictionary(uniqueKeysWithValues: ids.map { ($0, itemState(status: .outdated)) })
            ))
        var results: [String: CommandResult] = [:]
        for id in ids {
            results["brew upgrade \(id)"] = CommandResult(exitCode: 0, stdout: "ok", stderr: "")
            results["\(id) current"] = CommandResult(exitCode: 0, stdout: "\(id) 1.1.0", stderr: "")
            results["\(id) latest"] = CommandResult(exitCode: 0, stdout: "\(id) 1.1.0", stderr: "")
        }
        let commands = MockCommandExecutor(results: results)
        for id in ids {
            commands.setDelay(0.1, forCommand: "brew upgrade \(id)")
        }
        let runner = updateRunner(paths: paths, commands: commands)

        let started = Date()
        let updates = try runner.update(ids: [], all: true, assumeYes: true)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(updates.map(\.outcome), [.updated, .updated, .updated])
        XCTAssertGreaterThanOrEqual(
            elapsed, 0.3, "three 0.1s brew commands sharing a lane must not overlap")
    }

    func testRunnerEmitsPlannedStartedAndFinishedEvents() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        var pinned = recipe(id: "pinned")
        pinned.pin = "1.0.0"
        try ManifestStore(paths: paths).save(manifest(items: [recipe(id: "tool"), pinned]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": itemState(status: .outdated),
                    "pinned": itemState(status: .outdated),
                ]))
        let commands = MockCommandExecutor(results: [
            "tool update": CommandResult(exitCode: 0, stdout: "updated", stderr: ""),
            "tool current": CommandResult(exitCode: 0, stdout: "tool 1.1.0", stderr: ""),
            "tool latest": CommandResult(exitCode: 0, stdout: "tool 1.1.0", stderr: ""),
        ])
        let runner = updateRunner(paths: paths, commands: commands)

        let lock = NSLock()
        var events: [UpdateProgressEvent] = []
        _ = try runner.update(ids: [], all: true, assumeYes: true) { event in
            lock.lock()
            events.append(event)
            lock.unlock()
        }

        guard case .planned(let plan)? = events.first else {
            return XCTFail("expected a planned event first, got \(String(describing: events.first))")
        }
        XCTAssertEqual(plan.map(\.id), ["tool", "pinned"])

        var startedIDs: [String] = []
        var finished: [UpdateResult] = []
        for event in events {
            switch event {
            case .planned: continue
            case .itemStarted(let id, _): startedIDs.append(id)
            case .itemFinished(let result): finished.append(result)
            }
        }
        XCTAssertEqual(Set(startedIDs), ["tool", "pinned"])
        XCTAssertEqual(finished.count, 2)
        XCTAssertEqual(finished.first(where: { $0.id == "tool" })?.outcome, .updated)
        XCTAssertEqual(finished.first(where: { $0.id == "pinned" })?.outcome, .skippedPinned)
    }

    func testStopSignalPreventsUnstartedItemsFromRunning() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let ids = ["alpha", "bravo", "charlie"]
        try ManifestStore(paths: paths).save(manifest(items: ids.map { recipe(id: $0) }))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: Dictionary(uniqueKeysWithValues: ids.map { ($0, itemState(status: .outdated)) })
            ))
        var results: [String: CommandResult] = [:]
        for id in ids {
            results["\(id) update"] = CommandResult(exitCode: 0, stdout: "updated", stderr: "")
            results["\(id) current"] = CommandResult(exitCode: 0, stdout: "\(id) 1.1.0", stderr: "")
            results["\(id) latest"] = CommandResult(exitCode: 0, stdout: "\(id) 1.1.0", stderr: "")
        }
        let commands = MockCommandExecutor(results: results)
        var config = Config.default
        try config.set("update.max_concurrent", value: "1")
        let runner = updateRunner(paths: paths, commands: commands, config: config)
        let stopSignal = UpdateStopSignal()

        let updates = try runner.update(
            ids: [], all: true, assumeYes: true,
            onEvent: { event in
                if case .itemStarted = event { stopSignal.requestStop() }
            },
            stopSignal: stopSignal
        )

        XCTAssertEqual(updates.map(\.id), ["alpha"])
        XCTAssertEqual(updates.map(\.outcome), [.updated])
    }
```

The last test needs a `config` parameter on the existing private helper. Change `updateRunner` at `Tests/UpdateBarCoreTests/UpdateRunnerTests.swift:251`:

```swift
    private func updateRunner(
        paths: AppPaths,
        commands: MockCommandExecutor,
        environment: [String: String] = [:],
        config: Config = .default
    ) -> UpdateRunner {
        UpdateRunner(
            manifestStore: ManifestStore(paths: paths),
            stateStore: StateStore(paths: paths),
            config: config,
            httpClient: MockHTTPClient(responses: [:]),
            commandRunner: commands,
            now: { self.now },
            environment: environment,
            confirm: { _ in true },
            historyStore: HistoryStore(paths: paths)
        )
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter UpdateRunnerTests 2>&1 | tail -30`
Expected: FAIL — `cannot find 'UpdateProgressEvent' in scope`, and `extra argument 'onEvent' in call`.

- [ ] **Step 3: Add `UpdateProgressEvent`**

Create `Sources/UpdateBarCore/Models/UpdateProgressEvent.swift`:

```swift
/// Live progress from an update run.
///
/// An enum rather than a struct mirroring `CheckProgressEvent` because
/// `.planned` carries a plan payload the flat shape cannot express without
/// dead fields.
public enum UpdateProgressEvent: Equatable {
    /// The full plan, in order, before anything runs.
    case planned([UpdatePlanItem])
    case itemStarted(id: String, name: String)
    case itemFinished(UpdateResult)
}
```

- [ ] **Step 4: Rewrite `UpdateRunner.update` in three phases**

In `Sources/UpdateBarCore/Update/UpdateRunner.swift`, mark the type `@unchecked Sendable` and replace `update(ids:all:assumeYes:)`:

```swift
/// `@unchecked Sendable` so recipes can execute on a worker pool. The stored
/// dependencies are only read during execution; `confirm` may block on stdin
/// and is therefore called exclusively from the sequential planning phase,
/// never from a worker.
public struct UpdateRunner: @unchecked Sendable {
```

```swift
    struct WorkItem {
        let recipe: Recipe
        let planItem: UpdatePlanItem
    }

    public func update(
        ids: [String],
        all: Bool,
        assumeYes: Bool,
        onEvent: ((UpdateProgressEvent) throws -> Void)? = nil,
        stopSignal: UpdateStopSignal? = nil
    ) throws -> [UpdateResult] {
        let planDate = now()
        let manifest = try manifestStore.loadExistingOrEmpty(now: planDate)
        try validate(manifest)
        let state = try stateStore.loadExistingOrEmpty(now: planDate)
        let plan = UpdatePlanner(manifest: manifest, state: state).plan(ids: ids, all: all)
        try onEvent?(.planned(plan))

        // Phase 1: pure classification, strictly sequential. `confirm` can
        // block on stdin, so it must never run on a worker thread.
        var settled: [Int: UpdateResult] = [:]
        var runnable: [UpdateScheduler<WorkItem, UpdateResult>.Item] = []
        for (index, planItem) in plan.enumerated() {
            func settle(_ outcome: UpdateOutcome) throws {
                let result = UpdateResult(planItem: planItem, outcome: outcome)
                settled[index] = result
                try onEvent?(.itemStarted(id: planItem.id, name: planItem.name))
                try onEvent?(.itemFinished(result))
            }

            guard planItem.decision == .willUpdate else {
                try settle(planItem.decision.outcome)
                continue
            }
            guard let recipe = manifest.item(id: planItem.id) else {
                try settle(.missing)
                continue
            }
            guard assumeYes || confirm(planItem) else {
                try settle(.cancelled)
                continue
            }
            runnable.append(
                UpdateScheduler<WorkItem, UpdateResult>.Item(
                    index: index,
                    lane: UpdateLane.key(forCommand: recipe.update.cmd) ?? "recipe:\(recipe.id)",
                    payload: WorkItem(recipe: recipe, planItem: planItem)
                ))
        }

        // Phase 2: bounded-parallel execution, one recipe per lane at a time.
        // Only `work` runs concurrently; the scheduler delivers onStart and
        // onFinish serially, so `onEvent` needs no lock of its own.
        let scheduler = UpdateScheduler<WorkItem, UpdateResult>(
            items: runnable,
            stopSignal: stopSignal,
            onStart: { item in
                try onEvent?(.itemStarted(id: item.planItem.id, name: item.planItem.name))
            },
            onFinish: { result in
                try onEvent?(.itemFinished(result))
            },
            // A cancelled command means the whole run is being torn down, which
            // is what the old sequential `break` expressed.
            shouldStopAfter: { $0.outcome == .cancelled },
            work: { item in
                try runUpdate(recipe: item.recipe, planItem: item.planItem)
            }
        )
        let executed = try scheduler.run(maxConcurrent: config.update.maxConcurrent)

        // Phase 3: plan order, so machine-readable output is unchanged.
        // Items that never started are absent, matching the old `break`.
        return plan.indices.compactMap { settled[$0] ?? executed[$0] }
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter UpdateRunnerTests 2>&1 | tail -30`
Expected: PASS, including the four new tests and every pre-existing one. `testRunnerUpdatesItemAndChecksItAfterSuccess` still asserts exact command order — it has a single item, so ordering is deterministic.

- [ ] **Step 6: Run the whole Core suite**

Run: `swift test --filter UpdateBarCoreTests 2>&1 | tail -20`
Expected: PASS. If `testRunnerReturnsPartialFailureAndRedactsErrors` fails on command ordering, switch its assertion to `commands.recordedCommandTexts` (sorted) — that test now runs two lanes in parallel.

- [ ] **Step 7: Commit**

```bash
git add Sources/UpdateBarCore/Models/UpdateProgressEvent.swift Sources/UpdateBarCore/Update/UpdateRunner.swift Tests/UpdateBarCoreTests/UpdateRunnerTests.swift
git commit -m "$(cat <<'EOF'
Run updates with bounded parallelism and emit progress events

UpdateRunner now classifies the plan sequentially, executes willUpdate
items on a lane-keyed worker pool capped by update.max_concurrent, then
re-emits results in plan order so machine-readable output is unchanged.
New onEvent and stopSignal parameters default to nil.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: CLI `--jobs` and callback-driven `--json-stream`

`--json-stream` currently fakes per-item progress by calling `runner.update(ids: [item.id])` once per item (`Sources/UpdateBarCLI/CLIUpdateCommand.swift:135`), which would bypass the scheduler entirely.

**Files:**
- Modify: `Sources/UpdateBarCLI/CLIUpdateCommand.swift`
- Modify: `docs/cli.md:247` (the `updatebar update` section)
- Test: `Tests/UpdateBarCLITests/` — add `CLIUpdateJobsTests.swift`

**Interfaces:**
- Consumes: `UpdateRunner.update(ids:all:assumeYes:onEvent:stopSignal:)`, `UpdateConfig.validRange`.
- Produces: `updatebar update [--jobs N]`. `--json` and human stdout are unchanged. `--json-stream` emits the same `MachineEvent` types with the same fields.

- [ ] **Step 1: Write the failing test**

Create `Tests/UpdateBarCLITests/CLIUpdateJobsTests.swift`:

```swift
import UpdateBarCore
import XCTest

/// Guards the --jobs bounds, which mirror UpdateConfig.validRange.
final class CLIUpdateJobsTests: XCTestCase {
    func testValidRangeMatchesConfig() {
        XCTAssertEqual(UpdateConfig.validRange, 1...8)
    }

    func testConfigRejectsJobsValuesOutsideRange() {
        var config = Config.default
        XCTAssertThrowsError(try config.set("update.max_concurrent", value: "0"))
        XCTAssertThrowsError(try config.set("update.max_concurrent", value: "9"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails or passes trivially**

Run: `swift test --filter CLIUpdateJobsTests 2>&1 | tail -20`
Expected: PASS (it only pins Task 5's contract). The real verification for this task is Step 6's binary exercise.

- [ ] **Step 3: Add the `--jobs` option**

In `Sources/UpdateBarCLI/CLIUpdateCommand.swift`, after the `jsonStream` flag:

```swift
    @Option(
        name: .long,
        help: "How many items to update at once. Overrides update.max_concurrent for this run."
    )
    var jobs: Int?
```

In `run()`, right after `let config = try ConfigStore().loadExistingOrDefault()`:

```swift
        var config = try ConfigStore().loadExistingOrDefault()
        if let jobs {
            guard UpdateConfig.validRange.contains(jobs) else {
                throw ValidationError(
                    "--jobs must be between \(UpdateConfig.validRange.lowerBound) and "
                        + "\(UpdateConfig.validRange.upperBound)"
                )
            }
            config.update.maxConcurrent = jobs
        }
```

(Change `let config` to `var config` on that line.)

- [ ] **Step 4: Drive `--json-stream` from the progress callback**

Replace the body of `runJSONStream` between the `.started` event and the `catch`:

```swift
        var results: [UpdateResult] = []
        do {
            results = try runner.update(ids: ids, all: all, assumeYes: yes) { event in
                switch event {
                case .planned(let plan):
                    try writer.write(
                        MachineEvent(
                            event: .log,
                            operation: .update,
                            timestamp: Date(),
                            message: "planned \(plan.count) item(s)",
                            level: .info
                        ))
                case .itemStarted(let id, let name):
                    try writer.write(
                        MachineEvent(
                            event: .itemStarted,
                            operation: .update,
                            timestamp: Date(),
                            itemId: id,
                            message: name
                        ))
                case .itemFinished(let result):
                    try writer.write(
                        MachineEvent(
                            event: .itemFinished,
                            operation: .update,
                            timestamp: Date(),
                            itemId: result.id,
                            result: result
                        ))
                }
            }
        } catch {
```

Delete the old `let plan = try runner.plan(...)` block and the `for item in plan { … }` loop it replaced, including the `missing update result` fallback and the trailing `if result.outcome == .cancelled { break }`. The runner now owns both concerns.

`JSONLWriter` is written from the callback, which the scheduler delivers serially, so no additional locking is needed.

- [ ] **Step 5: Update `docs/cli.md`**

Change the heading at `docs/cli.md:247` and append two paragraphs to that section:

```markdown
### `updatebar update [id...] [--yes] [--jobs <n>] [--json|--json-stream]`
```

```markdown
Updates run in parallel, capped by `update.max_concurrent` (default `3`).
`--jobs <n>` overrides that cap for one run and must be between 1 and 8.
Two items whose `update.cmd` invokes the same tool — two `brew` recipes, say —
never run at the same time, because package managers hold a process-wide lock.

`--json` and human output list results in plan order regardless of the order
items finished. In `--json-stream`, `item_started` and `item_finished` events
interleave across items as work completes; the terminal `finished` event still
carries results in plan order.
```

Also add to the `config` section of `docs/cli.md`, wherever `security.require_https_source` is documented, a line for the new key:

```markdown
- `update.max_concurrent` — how many items update at once (1–8, default `3`).
```

- [ ] **Step 6: Exercise the built binary**

Run:
```bash
swift build --product updatebar
HOME_DIR=$(mktemp -d)
UPDATEBAR_HOME="$HOME_DIR" ./.build/debug/updatebar update --jobs 9 --yes --json; echo "exit=$?"
UPDATEBAR_HOME="$HOME_DIR" ./.build/debug/updatebar update --jobs 2 --yes --json; echo "exit=$?"
UPDATEBAR_HOME="$HOME_DIR" ./.build/debug/updatebar update --yes --json-stream; echo "exit=$?"
```
Expected: `--jobs 9` exits non-zero with the validation message on stderr; `--jobs 2` on an empty registry exits 0 with `[]`; `--json-stream` emits `started` then `log` then `finished` NDJSON lines and exits 0. Paste the output into the task report.

- [ ] **Step 7: Commit**

```bash
git add Sources/UpdateBarCLI/CLIUpdateCommand.swift Tests/UpdateBarCLITests/CLIUpdateJobsTests.swift docs/cli.md
git commit -m "$(cat <<'EOF'
Add updatebar update --jobs and stream progress from the runner

--jobs overrides update.max_concurrent for one run. --json-stream now
drives its events from the runner's progress callback instead of calling
update once per item, which had bypassed the scheduler entirely. Event
types and fields are unchanged.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Menu bar action coordinator tracks items and stops instead of cancelling

**Files:**
- Modify: `Sources/UpdateBarMenuBar/MenuBarActionCoordinator.swift`
- Modify: `Sources/UpdateBarMenuBar/MenuBarMenuModel.swift:63-70` (`MenuBarMenuItemAction`)
- Create: `Sources/UpdateBarMenuBar/MenuBarItemProgress.swift`
- Test: `Tests/UpdateBarMenuBarTests/MenuBarActionCoordinatorTests.swift`

**Interfaces:**
- Consumes: `UpdateStopSignal`, `UpdateProgressEvent` from `UpdateBarCore`.
- Produces:
  - `MenuBarActiveAction` gains `let stopSignal: UpdateStopSignal`, `private(set) var progress: MenuBarItemProgress`, `var isStopRequested: Bool`, `func requestStop()`, `func apply(_ event: UpdateProgressEvent)`.
  - `public struct MenuBarItemProgress: Equatable, Sendable { public var plannedIDs: [String]; public var inFlightIDs: Set<String>; public var finishedIDs: Set<String>; public var isEmpty: Bool; public var completedCount: Int; public var totalCount: Int }`
  - `MenuBarActionCoordinator.stopActive() -> MenuBarActiveAction?` replaces `cancelActive()`.
  - `MenuBarMenuItemAction.cancelCurrentAction` is renamed to `.stopCurrentAction`.

All mutation happens on the main queue only; the app hops before calling `apply`.

- [ ] **Step 1: Write the failing tests**

Replace the contents of `Tests/UpdateBarMenuBarTests/MenuBarActionCoordinatorTests.swift`:

```swift
import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class MenuBarActionCoordinatorTests: XCTestCase {
    func testRejectsSecondActionWhileOneIsActive() {
        let coordinator = MenuBarActionCoordinator()

        let first = coordinator.begin("Check Now")
        let second = coordinator.begin("Run Updates")

        XCTAssertNotNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(coordinator.activeAction?.title, "Check Now")
        XCTAssertEqual(coordinator.lastActionNotice, "Already running: Check Now")
        XCTAssertFalse(first?.token.isCancelled ?? true)
    }

    func testStopRequestsDrainWithoutCancellingTheRunningCommand() {
        let coordinator = MenuBarActionCoordinator()
        guard let action = coordinator.begin("Run Updates") else {
            XCTFail("expected action to start")
            return
        }

        XCTAssertNotNil(coordinator.stopActive())

        XCTAssertTrue(action.isStopRequested)
        XCTAssertTrue(action.stopSignal.isStopRequested)
        XCTAssertFalse(action.token.isCancelled, "stop must not kill the running command")
        XCTAssertEqual(coordinator.lastActionNotice, "Stopping after current: Run Updates")

        coordinator.finish(action, outcome: .finished)

        XCTAssertNil(coordinator.activeAction)
        XCTAssertEqual(coordinator.lastActionNotice, "Finished: Run Updates")
    }

    func testProgressTracksPlannedInFlightAndFinishedItems() {
        let coordinator = MenuBarActionCoordinator()
        guard let action = coordinator.begin("Run Updates") else {
            XCTFail("expected action to start")
            return
        }

        XCTAssertTrue(action.progress.isEmpty)

        action.apply(.planned([planItem(id: "alpha"), planItem(id: "bravo")]))
        XCTAssertEqual(action.progress.plannedIDs, ["alpha", "bravo"])
        XCTAssertEqual(action.progress.totalCount, 2)
        XCTAssertEqual(action.progress.completedCount, 0)

        action.apply(.itemStarted(id: "alpha", name: "alpha"))
        XCTAssertEqual(action.progress.inFlightIDs, ["alpha"])

        action.apply(.itemFinished(updateResult(id: "alpha")))
        XCTAssertEqual(action.progress.inFlightIDs, [])
        XCTAssertEqual(action.progress.finishedIDs, ["alpha"])
        XCTAssertEqual(action.progress.completedCount, 1)
    }

    private func planItem(id: String) -> UpdatePlanItem {
        UpdatePlanItem(
            id: id,
            name: id,
            decision: .willUpdate,
            current: "1.0.0",
            latest: "1.1.0",
            commandFingerprint: nil
        )
    }

    private func updateResult(id: String) -> UpdateResult {
        UpdateResult(
            id: id,
            name: id,
            outcome: .updated,
            current: "1.1.0",
            latest: "1.1.0",
            error: nil,
            commandFingerprint: nil
        )
    }
}
```

Both helper initialisers above match the real signatures — `UpdatePlanItem.init` at `Sources/UpdateBarCore/Update/UpdatePlanner.swift:70` and `UpdateResult.init` at `Sources/UpdateBarCore/Update/UpdateRunner.swift:192`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter MenuBarActionCoordinatorTests 2>&1 | tail -20`
Expected: FAIL — `value of type 'MenuBarActiveAction' has no member 'progress'`, `has no member 'stopActive'`.

- [ ] **Step 3: Add `MenuBarItemProgress`**

Create `Sources/UpdateBarMenuBar/MenuBarItemProgress.swift`:

```swift
import UpdateBarCore

/// Per-item state of the running action, so the menu can annotate individual
/// rows instead of collapsing into a single "Updating…" line.
public struct MenuBarItemProgress: Equatable, Sendable {
    public var plannedIDs: [String] = []
    public var inFlightIDs: Set<String> = []
    public var finishedIDs: Set<String> = []

    public init() {}

    public var isEmpty: Bool {
        plannedIDs.isEmpty && inFlightIDs.isEmpty && finishedIDs.isEmpty
    }

    public var totalCount: Int { plannedIDs.count }
    public var completedCount: Int { finishedIDs.count }

    public mutating func apply(_ event: UpdateProgressEvent) {
        switch event {
        case .planned(let plan):
            plannedIDs = plan.map(\.id)
        case .itemStarted(let id, _):
            inFlightIDs.insert(id)
        case .itemFinished(let result):
            inFlightIDs.remove(result.id)
            finishedIDs.insert(result.id)
        }
    }
}
```

- [ ] **Step 4: Extend `MenuBarActiveAction` and swap cancel for stop**

Replace `Sources/UpdateBarMenuBar/MenuBarActionCoordinator.swift`:

```swift
import Foundation
import UpdateBarCore

public final class MenuBarActiveAction: @unchecked Sendable {
    public let title: String
    public let token: CancellationToken
    public let stopSignal: UpdateStopSignal
    /// Main-queue only. The app hops before applying progress events.
    public private(set) var progress = MenuBarItemProgress()

    init(title: String, token: CancellationToken) {
        self.title = title
        self.token = token
        self.stopSignal = UpdateStopSignal()
    }

    public var isStopRequested: Bool { stopSignal.isStopRequested }

    public func requestStop() {
        stopSignal.requestStop()
    }

    public func apply(_ event: UpdateProgressEvent) {
        progress.apply(event)
    }
}

public enum MenuBarActionOutcome {
    case finished
    case cancelled
    case failed
}

public final class MenuBarActionCoordinator {
    public private(set) var activeAction: MenuBarActiveAction?
    public private(set) var lastActionNotice: String?

    public init() {}

    public func begin(_ title: String) -> MenuBarActiveAction? {
        if let activeAction {
            lastActionNotice = "Already running: \(activeAction.title)"
            return nil
        }
        let action = MenuBarActiveAction(title: title, token: CancellationToken())
        activeAction = action
        lastActionNotice = nil
        return action
    }

    /// Drains the queue: the running command finishes, nothing new starts.
    /// Deliberately not a cancel — killing a half-finished package manager
    /// leaves state UpdateBar cannot describe.
    @discardableResult
    public func stopActive() -> MenuBarActiveAction? {
        guard let activeAction else { return nil }
        activeAction.requestStop()
        lastActionNotice = "Stopping after current: \(activeAction.title)"
        return activeAction
    }

    public func finish(_ action: MenuBarActiveAction, outcome: MenuBarActionOutcome) {
        guard activeAction === action else { return }
        activeAction = nil
        switch outcome {
        case .finished:
            lastActionNotice = "Finished: \(action.title)"
        case .cancelled:
            lastActionNotice = "Cancelled: \(action.title)"
        case .failed:
            lastActionNotice = "Failed: \(action.title)"
        }
    }
}
```

`.cancelled` stays in `MenuBarActionOutcome` because the CLI adapter can still surface `UpdateBarCLIClientError.cancelled` on timeout.

- [ ] **Step 5: Rename the menu action case**

In `Sources/UpdateBarMenuBar/MenuBarMenuModel.swift`, rename the enum case:

```swift
public enum MenuBarMenuItemAction: Equatable, Sendable {
    case menu(MenuBarMenuAction)
    case stopCurrentAction
    case update(id: String)
    case approve(id: String, field: String)
    case revoke(id: String, field: String)
    case openTUIInTerminal(bundleID: String)
}
```

Then fix every compile error the rename produces:
```bash
grep -rn "cancelCurrentAction" Sources Tests
```
Update `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift` (the `@objc` handler at line 171, the switch at line 534, and the switch at line 672) and any test references. Task 9 rewrites the builder call site.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift build && swift test --filter MenuBarActionCoordinatorTests 2>&1 | tail -20`
Expected: PASS, 3 tests.

- [ ] **Step 7: Commit**

```bash
git add Sources/UpdateBarMenuBar/MenuBarItemProgress.swift Sources/UpdateBarMenuBar/MenuBarActionCoordinator.swift Sources/UpdateBarMenuBar/MenuBarMenuModel.swift Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift Tests/UpdateBarMenuBarTests/MenuBarActionCoordinatorTests.swift
git commit -m "$(cat <<'EOF'
Track per-item progress and replace menu bar cancel with stop

The active action now carries planned, in-flight, and finished item ids,
plus an UpdateStopSignal. Stopping drains the queue instead of killing a
running package manager, which can leave a half-installed package the
app cannot describe. CLI Ctrl-C still hard-cancels.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Menu keeps its rows during an action

This is the user-visible fix. `makeMenu` returns early at `Sources/UpdateBarMenuBar/MenuBarMenuModel.swift:98` and replaces every entry; that early return goes away.

**Files:**
- Modify: `Sources/UpdateBarMenuBar/MenuBarMenuModel.swift`
- Test: `Tests/UpdateBarMenuBarTests/MenuBarMenuModelTests.swift`

**Interfaces:**
- Consumes: `MenuBarItemProgress` (Task 8), `MenuBarMenuItemAction.stopCurrentAction` (Task 8).
- Produces: `makeMenu(state:approvalStatuses:activeActionTitle:activeItemProgress:isStopRequested:lastActionNotice:installedTerminals:selectedTerminalID:)`. `activeItemProgress` defaults to `nil` and `isStopRequested` to `false`, so existing test call sites keep compiling.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/UpdateBarMenuBarTests/MenuBarMenuModelTests.swift`, inside the existing class:

```swift
    func testActiveActionKeepsItemRowsAndFooterVisible() {
        var progress = MenuBarItemProgress()
        progress.plannedIDs = ["alpha", "bravo"]
        progress.inFlightIDs = ["alpha"]

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: stateWithOutdated(ids: ["alpha", "bravo"]),
            approvalStatuses: [:],
            activeActionTitle: "Updating approved items",
            activeItemProgress: progress
        )

        let titles = model.entries.compactMap { entry -> String? in
            if case .item(let item) = entry { return item.title }
            return nil
        }
        XCTAssertTrue(titles.contains { $0.contains("Updating approved items… (0/2)") })
        XCTAssertTrue(titles.contains("Stop After Current"))
        XCTAssertTrue(titles.contains { $0.contains("alpha") && $0.hasSuffix("— updating…") })
        XCTAssertTrue(titles.contains { $0.contains("bravo") && $0.hasSuffix("— queued") })
        XCTAssertTrue(titles.contains("Quit"), "footer actions must stay visible")
    }

    func testActiveActionDisablesItemAndRefreshRowsButNotFooter() {
        var progress = MenuBarItemProgress()
        progress.plannedIDs = ["alpha"]
        progress.inFlightIDs = ["alpha"]

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: stateWithOutdated(ids: ["alpha"]),
            approvalStatuses: [:],
            activeActionTitle: "Updating approved items",
            activeItemProgress: progress
        )

        var actionsByTitle: [String: MenuBarMenuItemAction?] = [:]
        for entry in model.entries {
            if case .item(let item) = entry { actionsByTitle[item.title] = item.action }
        }
        XCTAssertNil(actionsByTitle["Check Now"] ?? nil)
        XCTAssertNil(actionsByTitle["Refresh Status"] ?? nil)
        XCTAssertNotNil(actionsByTitle["Quit"] ?? nil)
        XCTAssertEqual(
            actionsByTitle["Stop After Current"] ?? nil, .stopCurrentAction)
    }

    func testStopRequestedShowsStoppingAndDisablesTheStopRow() {
        var progress = MenuBarItemProgress()
        progress.plannedIDs = ["alpha"]
        progress.inFlightIDs = ["alpha"]

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: stateWithOutdated(ids: ["alpha"]),
            approvalStatuses: [:],
            activeActionTitle: "Updating approved items",
            activeItemProgress: progress,
            isStopRequested: true
        )

        var stopRow: MenuBarMenuItem?
        for entry in model.entries {
            if case .item(let item) = entry, item.title.hasPrefix("Stopping") { stopRow = item }
        }
        XCTAssertEqual(stopRow?.title, "Stopping after current…")
        XCTAssertNil(stopRow?.action)
    }

    func testFinishedItemsAreMarkedDone() {
        var progress = MenuBarItemProgress()
        progress.plannedIDs = ["alpha"]
        progress.finishedIDs = ["alpha"]

        let model = MenuBarMenuModelBuilder().makeMenu(
            state: stateWithOutdated(ids: ["alpha"]),
            approvalStatuses: [:],
            activeActionTitle: "Updating approved items",
            activeItemProgress: progress
        )

        let titles = model.entries.compactMap { entry -> String? in
            if case .item(let item) = entry { return item.title }
            return nil
        }
        XCTAssertTrue(titles.contains { $0.contains("alpha") && $0.hasSuffix("— done") })
    }
```

Add this helper to the class. It reuses the file's existing private `statusItem(id:name:current:latest:status:error:)` builder at line 823 and `MenuBarState`'s real memberwise initialiser (`Sources/UpdateBarMenuBar/MenuBarStatusFormatter.swift:4`):

```swift
    private func stateWithOutdated(ids: [String]) -> MenuBarState {
        MenuBarState(
            title: "\(ids.count) update(s) available",
            badgeValue: String(ids.count),
            outdatedItems: ids.map {
                statusItem(id: $0, name: $0, current: "1.0.0", latest: "1.1.0", status: .outdated)
            },
            approvalItems: [],
            errorItems: [],
            okItems: []
        )
    }
```

The new tests can also use the file's existing `entries.item(titled:)` and `entries.labels` extensions instead of hand-rolling the `compactMap` shown above; prefer them where they read more clearly.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter MenuBarMenuModelTests 2>&1 | tail -30`
Expected: FAIL — `extra argument 'activeItemProgress' in call`.

- [ ] **Step 3: Replace the collapse with per-row annotation**

In `Sources/UpdateBarMenuBar/MenuBarMenuModel.swift`, change `makeMenu`'s signature and delete the early-return block at lines 98-112:

```swift
    public func makeMenu(
        state: MenuBarState,
        approvalStatuses: [String: [CommandApprovalStatus]],
        activeActionTitle: String? = nil,
        activeItemProgress: MenuBarItemProgress? = nil,
        isStopRequested: Bool = false,
        lastActionNotice: String? = nil,
        installedTerminals: [TUITerminal] = [],
        selectedTerminalID: String? = nil
    ) -> MenuBarMenuModel {
        var entries: [MenuBarMenuEntry] = []
        let progress = activeActionTitle == nil ? nil : (activeItemProgress ?? MenuBarItemProgress())

        if let activeActionTitle {
            let counted = progress.map { " (\($0.completedCount)/\($0.totalCount))" } ?? ""
            appendDisabled(
                "\(SecretRedactor.redact(activeActionTitle))…\(counted)",
                to: &entries
            )
            if isStopRequested {
                appendDisabled("Stopping after current…", to: &entries)
            } else {
                appendAction(
                    "Stop After Current",
                    action: .stopCurrentAction,
                    toolTip: "Lets the running command finish and starts nothing new.",
                    to: &entries
                )
            }
            appendSeparator(to: &entries)
        }

        if let lastActionNotice {
            appendDisabled(SecretRedactor.redact(lastActionNotice), to: &entries)
            appendSeparator(to: &entries)
        }

        appendDisabled(state.title, to: &entries)
        if let needsAttentionSummary = state.needsAttentionSummary {
            appendDisabled(needsAttentionSummary, to: &entries)
        }
        appendSeparator(to: &entries)

        let busyToolTip = "Another action is running."
        if progress == nil {
            appendAction(MenuBarMenuAction.checkNow.title, action: .menu(.checkNow), to: &entries)
            appendAction(
                MenuBarMenuAction.refreshStatus.title, action: .menu(.refreshStatus), to: &entries)
        } else {
            appendDisabled(
                MenuBarMenuAction.checkNow.title, toolTip: busyToolTip, to: &entries)
            appendDisabled(
                MenuBarMenuAction.refreshStatus.title, toolTip: busyToolTip, to: &entries)
        }

        let updateAllAction = MenuBarMenuAction.updateAllApprovedOutdated
        if progress != nil {
            appendDisabled(updateAllAction.title, toolTip: busyToolTip, to: &entries)
        } else if state.outdatedItems.isEmpty {
            appendDisabled(updateAllAction.title, toolTip: "No updates available.", to: &entries)
        } else {
            appendAction(
                updateAllAction.title,
                action: .menu(updateAllAction),
                toolTip: "Updates all \(state.outdatedItems.count) approved outdated items.",
                to: &entries
            )
        }
        appendSeparator(to: &entries)

        appendUpdates(state.outdatedItems, progress: progress, to: &entries)
        appendApprovals(
            state.approvalItems,
            approvalStatuses: approvalStatuses,
            isBusy: progress != nil,
            to: &entries
        )
        appendErrors(state.errorItems, to: &entries)
        appendInstalled(state.okItems, to: &entries)

        appendSeparator(to: &entries)
        appendFooterActions(
            installedTerminals: installedTerminals,
            selectedTerminalID: selectedTerminalID,
            to: &entries
        )

        return MenuBarMenuModel(entries: entries)
    }
```

Rewrite `appendUpdates` to annotate rows:

```swift
    private func appendUpdates(
        _ items: [StatusItem],
        progress: MenuBarItemProgress?,
        to entries: inout [MenuBarMenuEntry]
    ) {
        appendSection("Updates (\(items.count))", items: items, to: &entries) { item in
            let name = SecretRedactor.redact(item.name)
            let current = item.current.map(SecretRedactor.redact) ?? "?"
            let latest = item.latest.map(SecretRedactor.redact) ?? "?"
            let base = "\(name) \(current) -> \(latest)"

            guard let progress else {
                return MenuBarMenuItem(
                    title: base,
                    action: .update(id: item.id),
                    toolTip: "Updates \(SecretRedactor.redact(item.id)) immediately."
                )
            }
            if progress.inFlightIDs.contains(item.id) {
                return MenuBarMenuItem(
                    title: "\(base) — updating…",
                    systemSymbolName: "arrow.triangle.2.circlepath"
                )
            }
            if progress.finishedIDs.contains(item.id) {
                return MenuBarMenuItem(title: "\(base) — done")
            }
            if progress.plannedIDs.contains(item.id) {
                return MenuBarMenuItem(title: "\(base) — queued")
            }
            return MenuBarMenuItem(title: base, toolTip: "Another action is running.")
        }
    }
```

Add an `isBusy` parameter to `appendApprovals` and pass `nil` for the action when busy:

```swift
    private func appendApprovals(
        _ items: [StatusItem],
        approvalStatuses: [String: [CommandApprovalStatus]],
        isBusy: Bool,
        to entries: inout [MenuBarMenuEntry]
    ) {
```

and inside `approvalMenuItem`, thread `isBusy` through so the returned item uses `action: isBusy ? nil : action`. Change its signature to
`private func approvalMenuItem(for item: StatusItem, approval: CommandApprovalStatus, isBusy: Bool) -> MenuBarMenuItem`
and update the call site in `appendApprovals`.

Leave `makeLoadingMenu` and `makeErrorMenu` alone.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter MenuBarMenuModelTests 2>&1 | tail -30`
Expected: PASS. Pre-existing tests in this 28K file assert on the old collapsed shape — find them with `grep -n "Cancel Current Action" Tests/UpdateBarMenuBarTests/MenuBarMenuModelTests.swift` and update each to the new expectations rather than deleting them.

- [ ] **Step 5: Commit**

```bash
git add Sources/UpdateBarMenuBar/MenuBarMenuModel.swift Tests/UpdateBarMenuBarTests/MenuBarMenuModelTests.swift
git commit -m "$(cat <<'EOF'
Keep menu rows visible while an action runs

The menu no longer collapses to a single line. Items being updated read
"updating…", queued items read "queued", finished ones read "done", and
footer actions stay enabled so the dashboard and TUI remain reachable.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Wire progress through the service protocol into the app

**Files:**
- Modify: `Sources/UpdateBarMenuBar/MenuBarService.swift`
- Modify: `Sources/UpdateBarMenuBar/UpdateBarCLIClient.swift:141-157`
- Modify: `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`
- Test: `Tests/UpdateBarMenuBarTests/CoreMenuBarServiceTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 6, 8, 9.
- Produces:
  - `MenuBarServicing.updateAllApproved(cancellationToken:onEvent:stopSignal:)` and `update(id:cancellationToken:onEvent:stopSignal:)`. Convenience extensions keep the old short forms working.
  - `UpdateBarCLIClient` conforms by ignoring `onEvent` and `stopSignal` — the subprocess adapter has no progress channel. It is opt-in via `UPDATEBAR_MENUBAR_ADAPTER=cli`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/UpdateBarMenuBarTests/CoreMenuBarServiceTests.swift`, inside the existing class:

```swift
    func testUpdateAllApprovedForwardsProgressEvents() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        try ManifestStore(paths: paths).save(
            manifest(items: [
                recipe(id: "tool", updateCommand: "tool update", currentCommand: "tool current")
            ]))
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: [
                    "tool": ItemState(
                        current: "1.0.0",
                        latest: "1.1.0",
                        status: .outdated,
                        lastChecked: now,
                        error: nil,
                        backoffUntil: nil
                    )
                ]))
        let commands = RecordingCommandRunner(results: [
            "tool update": CommandResult(exitCode: 0, stdout: "updated", stderr: ""),
            "tool current": CommandResult(exitCode: 0, stdout: "tool 1.1.0", stderr: ""),
            "tool latest": CommandResult(exitCode: 0, stdout: "tool 1.1.0", stderr: ""),
        ])
        let service = CoreMenuBarService(paths: paths, commandRunner: commands, now: { self.now })

        var startedIDs: [String] = []
        var finishedIDs: [String] = []
        try service.updateAllApproved(
            cancellationToken: nil,
            onEvent: { event in
                switch event {
                case .planned: break
                case .itemStarted(let id, _): startedIDs.append(id)
                case .itemFinished(let result): finishedIDs.append(result.id)
                }
            },
            stopSignal: nil
        )

        XCTAssertEqual(startedIDs, ["tool"])
        XCTAssertEqual(finishedIDs, ["tool"])
    }
```

This mirrors the existing `testCoreServiceReadsStatusApprovalsAndRunsUpdate` at line 78, reusing the file's private `manifest(items:)`, `recipe(id:updateCommand:currentCommand:)`, `temporaryDirectory()`, and `RecordingCommandRunner`. No new fixtures.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CoreMenuBarServiceTests 2>&1 | tail -20`
Expected: FAIL — `extra argument 'onEvent' in call`.

- [ ] **Step 3: Widen the protocol**

In `Sources/UpdateBarMenuBar/MenuBarService.swift`:

```swift
    func update(
        id: String,
        cancellationToken: CancellationToken?,
        onEvent: ((UpdateProgressEvent) throws -> Void)?,
        stopSignal: UpdateStopSignal?
    ) throws
    func updateAllApproved(
        cancellationToken: CancellationToken?,
        onEvent: ((UpdateProgressEvent) throws -> Void)?,
        stopSignal: UpdateStopSignal?
    ) throws
```

Update the convenience extension so existing short call sites still compile:

```swift
    public func update(id: String) throws {
        try update(id: id, cancellationToken: nil, onEvent: nil, stopSignal: nil)
    }

    public func update(id: String, cancellationToken: CancellationToken?) throws {
        try update(id: id, cancellationToken: cancellationToken, onEvent: nil, stopSignal: nil)
    }

    public func updateAllApproved() throws {
        try updateAllApproved(cancellationToken: nil, onEvent: nil, stopSignal: nil)
    }

    public func updateAllApproved(cancellationToken: CancellationToken?) throws {
        try updateAllApproved(cancellationToken: cancellationToken, onEvent: nil, stopSignal: nil)
    }
```

Implement in `CoreMenuBarService`:

```swift
    public func update(
        id: String,
        cancellationToken: CancellationToken? = nil,
        onEvent: ((UpdateProgressEvent) throws -> Void)? = nil,
        stopSignal: UpdateStopSignal? = nil
    ) throws {
        _ = try updateRunner(cancellationToken: cancellationToken).update(
            ids: [id],
            all: false,
            assumeYes: true,
            onEvent: onEvent,
            stopSignal: stopSignal
        )
    }

    public func updateAllApproved(
        cancellationToken: CancellationToken? = nil,
        onEvent: ((UpdateProgressEvent) throws -> Void)? = nil,
        stopSignal: UpdateStopSignal? = nil
    ) throws {
        _ = try updateRunner(cancellationToken: cancellationToken).update(
            ids: [],
            all: true,
            assumeYes: true,
            onEvent: onEvent,
            stopSignal: stopSignal
        )
    }
```

In `Sources/UpdateBarMenuBar/UpdateBarCLIClient.swift`, widen both methods and ignore the new parameters:

```swift
    /// The subprocess adapter has no progress channel; `onEvent` and
    /// `stopSignal` are accepted for protocol conformance and ignored. This
    /// adapter is opt-in via UPDATEBAR_MENUBAR_ADAPTER=cli.
    public func update(
        id: String,
        cancellationToken: CancellationToken? = nil,
        onEvent: ((UpdateProgressEvent) throws -> Void)? = nil,
        stopSignal: UpdateStopSignal? = nil
    ) throws {
        let result = try runner.run(
            executablePath: executablePath,
            arguments: ["update", id, "--yes", "--json"],
            cancellationToken: cancellationToken
        )
        try ensureSuccess(result, allowedExitCodes: [0, 2, 3])
    }
```

Apply the same treatment to `updateAllApproved`.

- [ ] **Step 4: Wire the app**

In `Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift`:

Replace `cancelCurrentAction` (line 171) with:

```swift
        @objc private func stopCurrentAction() {
            guard actionCoordinator.stopActive() != nil else { return }
            rebuildMenu()
        }
```

Change `runAction` to hand the active action to its closure so update actions can forward progress:

```swift
        private func runAction(
            _ title: String,
            _ action: @escaping @Sendable (MenuBarActiveAction) throws -> Void
        ) {
            guard let activeAction = actionCoordinator.begin(title) else {
                rebuildMenu()
                return
            }
            refreshGenerationGate.invalidate()
            rebuildMenu()
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try action(activeAction)
                    DispatchQueue.main.async {
                        let wasCancelled = activeAction.token.isCancelled
                        self.actionCoordinator.finish(
                            activeAction,
                            outcome: wasCancelled ? .cancelled : .finished
                        )
                        self.refreshStatus(refresh: false)
                    }
                } catch let error as ExecutionError where error.isCancellation {
                    DispatchQueue.main.async {
                        self.actionCoordinator.finish(activeAction, outcome: .cancelled)
                        self.refreshStatus(refresh: false)
                    }
                } catch let error as UpdateBarCLIClientError where error == .cancelled {
                    DispatchQueue.main.async {
                        self.actionCoordinator.finish(activeAction, outcome: .cancelled)
                        self.refreshStatus(refresh: false)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.actionCoordinator.finish(activeAction, outcome: .failed)
                        self.showError(error)
                    }
                }
            }
        }

        /// Progress arrives on a worker thread; menu state is main-queue only.
        private func progressHandler(
            for activeAction: MenuBarActiveAction
        ) -> @Sendable (UpdateProgressEvent) -> Void {
            { event in
                DispatchQueue.main.async {
                    activeAction.apply(event)
                    self.scheduleThrottledMenuRebuild()
                }
            }
        }
```

Update the non-update call sites to the new closure shape:

```swift
        @objc private func checkNow() {
            runAction("Checking for updates") { [service] action in
                try service?.checkNow(cancellationToken: action.token)
            }
        }

        @objc private func updateAllApproved() {
            runAction("Updating approved items") { [service] action in
                try service?.updateAllApproved(
                    cancellationToken: action.token,
                    onEvent: self.progressHandler(for: action),
                    stopSignal: action.stopSignal
                )
            }
        }

        private func update(id: String) {
            runAction("Updating \(id)") { [service] action in
                try service?.update(
                    id: id,
                    cancellationToken: action.token,
                    onEvent: self.progressHandler(for: action),
                    stopSignal: action.stopSignal
                )
            }
        }
```

`setApproval`'s `runAction` closure takes `action` and uses `action.token` in place of `token`.

Add the throttle next to `rebuildMenu` (main queue only, so a plain stored property is safe):

```swift
        private var pendingMenuRebuild = false

        /// Progress events arrive faster than a menu is worth rebuilding, and
        /// replacing statusItem.menu while it is open flickers.
        private func scheduleThrottledMenuRebuild() {
            guard !pendingMenuRebuild else { return }
            pendingMenuRebuild = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                self.pendingMenuRebuild = false
                self.rebuildMenu()
            }
        }
```

Update `rebuildMenu` (line 467) to pass the new arguments:

```swift
            let model = menuBuilder.makeMenu(
                state: latestState,
                approvalStatuses: approvalStatuses,
                activeActionTitle: activeAction?.title,
                activeItemProgress: activeAction?.progress,
                isStopRequested: activeAction?.isStopRequested ?? false,
                lastActionNotice: activeAction == nil ? actionCoordinator.lastActionNotice : nil,
                installedTerminals: installedTerminals(),
                selectedTerminalID: selectedTerminal().id
            )
```

Update the two `MenuBarMenuItemAction` switches (lines ~534 and ~672) so `.cancelCurrentAction` becomes `.stopCurrentAction` and targets `#selector(stopCurrentAction)`.

- [ ] **Step 5: Run the full test suite**

Run: `swift build && swift test 2>&1 | tail -30`
Expected: PASS across all three test targets.

- [ ] **Step 6: Commit**

```bash
git add Sources/UpdateBarMenuBar/MenuBarService.swift Sources/UpdateBarMenuBar/UpdateBarCLIClient.swift Sources/UpdateBarMenuBarApp/UpdateBarMenuBarApp.swift Tests/UpdateBarMenuBarTests/CoreMenuBarServiceTests.swift
git commit -m "$(cat <<'EOF'
Forward update progress from the service into the menu

MenuBarServicing carries an onEvent callback and a stop signal. The app
applies events on the main queue and rebuilds the menu on a 300ms
throttle so an open menu does not flicker. The CLI subprocess adapter
accepts both parameters and ignores them; it has no progress channel.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Docs, OpenSpec entry, and the quality gate

**Files:**
- Create: `openspec/changes/parallel-update-per-item-progress/.openspec.yaml`
- Create: `openspec/changes/parallel-update-per-item-progress/proposal.md`
- Create: `openspec/changes/parallel-update-per-item-progress/tasks.md`
- Create: `openspec/changes/parallel-update-per-item-progress/specs/macos-menubar/spec.md`
- Modify: `docs/menu-bar.md:28-30`

**Interfaces:**
- Consumes: the finished implementation.
- Produces: nothing code-facing.

- [ ] **Step 1: Update `docs/menu-bar.md`**

Replace the two bullets at `docs/menu-bar.md:28-30` (the ones describing the collapse and Cancel Current Action) with:

```markdown
- keeps every row rendered while an action is in flight. Items being updated
  read `— updating…`, items still queued read `— queued`, and finished items
  read `— done`. Check Now, Refresh Status, Update All, and the per-item update
  and approval actions are disabled for the duration; Dashboard, Manage Items,
  Scan & Add, Open TUI, Preferences, and Quit stay available
- shows the active title with a completed/total count plus `Stop After Current`,
  which lets the running command finish and starts nothing new. There is no
  hard cancel in the menu bar: killing a half-finished package manager leaves
  state UpdateBar cannot describe. A hung update command therefore blocks the
  action until the 30 minute execution timeout, and quitting the app is the
  only earlier escape. `updatebar update` in a terminal still hard-cancels on
  Ctrl-C
- updates several items at once, capped by `update.max_concurrent` (default 3).
  Two recipes whose `update.cmd` invokes the same tool never run at the same
  time
```

- [ ] **Step 2: Write the OpenSpec entry**

`openspec/changes/parallel-update-per-item-progress/.openspec.yaml`:

```yaml
schema: spec-driven
created: 2026-07-30
```

`openspec/changes/parallel-update-per-item-progress/proposal.md`:

```markdown
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
  Add, Open TUI, Preferences, and Quit enabled.
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
```

`openspec/changes/parallel-update-per-item-progress/tasks.md`:

```markdown
## Verification

- [ ] `Scripts/quality-gate.sh` exits 0
- [ ] `swift test` passes across UpdateBarCoreTests, UpdateBarCLITests, and
      UpdateBarMenuBarTests
- [ ] `updatebar update --jobs 9` is rejected; `--jobs 2` is accepted
- [ ] `updatebar config get --json` reports `update.max_concurrent`
```

`openspec/changes/parallel-update-per-item-progress/specs/macos-menubar/spec.md`:

```markdown
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
Preferences, and Quit SHALL remain enabled.

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
```

- [ ] **Step 3: Format everything**

Run:
```bash
xcrun swift-format format --in-place --recursive Sources Tests Package.swift
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
```
Expected: the lint pass exits 0 with no output. This is the same invocation `CONTRIBUTING.md:28` documents and `Scripts/quality-gate.sh:96` runs.

- [ ] **Step 4: Run the quality gate**

Run: `Scripts/quality-gate.sh 2>&1 | tail -40`
Expected: exit 0. Paste the tail into the task report. If the menu bar smoke test needs skipping because of a headless environment, record `SKIP_MENUBAR_SMOKE=1` and the reason explicitly — do not skip silently. If XCTest fails to launch, work through `docs/troubleshooting.md` rather than skipping tests.

- [ ] **Step 5: Confirm the diff touches only task files**

Run: `git diff --stat main...HEAD`
Expected: only the files listed in this plan's File Structure section, plus the spec and plan documents. No `Package.swift` change — no new dependencies.

- [ ] **Step 6: Commit**

```bash
git add docs/menu-bar.md openspec/changes/parallel-update-per-item-progress
git commit -m "$(cat <<'EOF'
Document parallel updates and per-item menu progress

Records the concurrency cap, the lane rule, the stop-versus-cancel
distinction and its 30 minute timeout trade-off, and adds the OpenSpec
change entry.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Notes For The Implementer

**A known limitation, not a bug to chase.** `RegistryService.check` holds the state file lock for its whole body (`Sources/UpdateBarCore/Registry/RegistryService.swift:53`), and `UpdateRunner.runUpdate` calls it after every successful update (`Sources/UpdateBarCore/Update/UpdateRunner.swift:111`). Post-update checks therefore serialise on `flock` even though the expensive part — `update.cmd` itself — runs fully in parallel. That is acceptable and out of scope. Do not restructure `RegistryService`; it sits on the trust boundary and any change there needs the owner's sign-off.

**No recursive locking.** `runUpdate` acquires the state lock only through `check` and `markFailure`, and neither is called while the other holds it. Keep it that way — a nested `withExclusiveLock` on the same path would deadlock, since each `open()` creates its own file description and `flock` blocks between them even inside one process.

**Escalate rather than guess** on: anything touching trust or approval semantics, any further stdout shape change, adding a dependency, or a version bump.
