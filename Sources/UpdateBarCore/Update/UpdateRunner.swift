import Foundation

/// `@unchecked Sendable` so recipes can execute on a worker pool. The stored
/// dependencies are only read during execution; `confirm` may block on stdin
/// and is therefore called exclusively from the sequential planning phase,
/// never from a worker.
public struct UpdateRunner: @unchecked Sendable {
    private let manifestStore: ManifestStore
    private let stateStore: StateStore
    private let config: Config
    private let httpClient: HTTPClient
    private let commandRunner: CommandRunning
    private let now: () -> Date
    private let githubToken: String?
    private let environment: [String: String]
    private let userHomeDirectory: URL
    private let confirm: (UpdatePlanItem) -> Bool
    private let historyStore: HistoryStore

    public init(
        manifestStore: ManifestStore = ManifestStore(),
        stateStore: StateStore = StateStore(),
        config: Config = .default,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        commandRunner: CommandRunning = CommandExecutor(),
        now: @escaping () -> Date = { Date() },
        githubToken: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        confirm: @escaping (UpdatePlanItem) -> Bool = { _ in false },
        historyStore: HistoryStore? = nil
    ) {
        self.manifestStore = manifestStore
        self.stateStore = stateStore
        self.config = config
        self.httpClient = httpClient
        self.commandRunner = commandRunner
        self.now = now
        self.githubToken = githubToken
        self.environment = environment
        self.userHomeDirectory = UserPathExpander.homeDirectory(environment: environment)
        self.confirm = confirm
        self.historyStore = historyStore ?? HistoryStore(paths: AppPaths(environment: environment))
    }

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

    public func plan(ids: [String], all: Bool) throws -> [UpdatePlanItem] {
        let planDate = now()
        let manifest = try manifestStore.loadExistingOrEmpty(now: planDate)
        try validate(manifest)
        let state = try stateStore.loadExistingOrEmpty(now: planDate)
        return UpdatePlanner(manifest: manifest, state: state).plan(ids: ids, all: all)
    }

    public func updateReport(ids: [String], all: Bool, assumeYes: Bool) throws -> UpdateReport {
        let results = try update(ids: ids, all: all, assumeYes: assumeYes)
        return UpdateReport(results: results)
    }

    private func validate(_ manifest: Manifest) throws {
        let data = try JSONEncoder.updateBar.encode(manifest)
        let result = try ManifestValidator.validate(data: data)
        if !result.isValid {
            throw RegistryError.invalidManifest(result.errors)
        }
    }

    private func runUpdate(recipe: Recipe, planItem: UpdatePlanItem) throws -> UpdateResult {
        do {
            let commandResult = try commandRunner.run(
                ShellCommand(command: recipe.update.cmd, cwd: expandedPath(recipe.update.cwd)),
                policy: ExecutionPolicy(timeout: 30 * 60, maxOutputBytes: 256 * 1024)
            )
            guard commandResult.exitCode == 0 else {
                let error = "update.cmd exited \(commandResult.exitCode): \(commandResult.stderr)"
                try markFailure(recipe: recipe, error: error)
                recordHistory(planItem: planItem, outcome: "failed", to: nil)
                return UpdateResult(
                    planItem: planItem,
                    outcome: .failed,
                    error: SecretRedactor.redact(error)
                )
            }

            let checks = try RegistryService(
                manifestStore: manifestStore,
                stateStore: stateStore,
                config: config,
                httpClient: httpClient,
                commandRunner: commandRunner,
                now: now,
                githubToken: githubToken,
                environment: environment
            ).check(ids: [recipe.id], force: true)
            let check = checks.first
            recordHistory(planItem: planItem, outcome: "updated", to: check?.current)
            return UpdateResult(
                planItem: planItem,
                outcome: .updated,
                current: check?.current,
                latest: check?.latest,
                error: check?.error
            )
        } catch let error as ExecutionError where error.isCancellation {
            return UpdateResult(
                planItem: planItem,
                outcome: .cancelled,
                error: SecretRedactor.redact(String(describing: error))
            )
        } catch {
            try markFailure(recipe: recipe, error: String(describing: error))
            recordHistory(planItem: planItem, outcome: "failed", to: nil)
            return UpdateResult(
                planItem: planItem,
                outcome: .failed,
                error: SecretRedactor.redact(String(describing: error))
            )
        }
    }

    // History is telemetry for the dashboard; it must never fail an update.
    private func recordHistory(planItem: UpdatePlanItem, outcome: String, to: String?) {
        try? historyStore.append(
            HistoryEvent(
                event: .updateFinished,
                id: planItem.id,
                from: planItem.current,
                to: to ?? planItem.latest,
                outcome: outcome,
                at: now()
            ))
    }

    private func markFailure(recipe: Recipe, error: String) throws {
        try stateStore.withExclusiveLock {
            let timestamp = now()
            var state = try stateStore.load(now: timestamp)
            let existing = state.items[recipe.id]
            state.items[recipe.id] = ItemState(
                current: existing?.current,
                latest: existing?.latest,
                status: .error,
                lastChecked: existing?.lastChecked,
                error: SecretRedactor.redact(error),
                backoffUntil: nil
            )
            state.generatedAt = timestamp
            try stateStore.save(state)
        }
    }

    private func expandedPath(_ path: String?) -> String? {
        path.map { UserPathExpander.expandTilde(in: $0, homeDirectory: userHomeDirectory) }
    }
}

public struct UpdateResult: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var outcome: UpdateOutcome
    public var current: String?
    public var latest: String?
    public var error: String?
    public var commandFingerprint: String?

    public init(
        id: String,
        name: String,
        outcome: UpdateOutcome,
        current: String?,
        latest: String?,
        error: String?,
        commandFingerprint: String?
    ) {
        self.id = SecretRedactor.redact(id)
        self.name = SecretRedactor.redact(name)
        self.outcome = outcome
        self.current = current.map(SecretRedactor.redact)
        self.latest = latest.map(SecretRedactor.redact)
        self.error = error.map(SecretRedactor.redact)
        self.commandFingerprint = commandFingerprint
    }

    init(
        planItem: UpdatePlanItem,
        outcome: UpdateOutcome,
        current: String? = nil,
        latest: String? = nil,
        error: String? = nil
    ) {
        self.init(
            id: planItem.id,
            name: planItem.name,
            outcome: outcome,
            current: current ?? planItem.current,
            latest: latest ?? planItem.latest,
            error: error,
            commandFingerprint: planItem.commandFingerprint
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case outcome
        case current
        case latest
        case error
        case commandFingerprint = "command_fingerprint"
    }
}

public struct UpdateReport: Codable, Equatable {
    public var summary: UpdateSummary
    public var results: [UpdateResult]

    public init(results: [UpdateResult]) {
        self.summary = UpdateSummary(results: results)
        self.results = results
    }
}

public struct UpdateSummary: Codable, Equatable {
    public var total: Int
    public var updated: Int
    public var failed: Int
    public var skipped: Int
    public var skippedUntrusted: Int
    public var missing: Int
    public var cancelled: Int
    public var hardFailures: Int

    public init(results: [UpdateResult]) {
        self.total = results.count
        self.updated = results.filter { $0.outcome == .updated }.count
        self.failed = results.filter { $0.outcome == .failed }.count
        self.skipped = results.filter { $0.outcome.isSkipped }.count
        self.skippedUntrusted = results.filter { $0.outcome == .skippedUntrusted }.count
        self.missing = results.filter { $0.outcome == .missing }.count
        self.cancelled = results.filter { $0.outcome == .cancelled }.count
        self.hardFailures = results.filter { $0.outcome.isHardFailure }.count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.decode(Int.self, forKey: .total)
        updated = try container.decode(Int.self, forKey: .updated)
        failed = try container.decode(Int.self, forKey: .failed)
        skipped = try container.decode(Int.self, forKey: .skipped)
        skippedUntrusted = try container.decode(Int.self, forKey: .skippedUntrusted)
        missing = try container.decode(Int.self, forKey: .missing)
        cancelled = try container.decode(Int.self, forKey: .cancelled)
        hardFailures = try container.decode(Int.self, forKey: .hardFailures)
        try validateNonNegativeDecoded(total, forKey: .total, in: container)
        try validateNonNegativeDecoded(updated, forKey: .updated, in: container)
        try validateNonNegativeDecoded(failed, forKey: .failed, in: container)
        try validateNonNegativeDecoded(skipped, forKey: .skipped, in: container)
        try validateNonNegativeDecoded(skippedUntrusted, forKey: .skippedUntrusted, in: container)
        try validateNonNegativeDecoded(missing, forKey: .missing, in: container)
        try validateNonNegativeDecoded(cancelled, forKey: .cancelled, in: container)
        try validateNonNegativeDecoded(hardFailures, forKey: .hardFailures, in: container)
    }

    enum CodingKeys: String, CodingKey {
        case total
        case updated
        case failed
        case skipped
        case skippedUntrusted = "skipped_untrusted"
        case missing
        case cancelled
        case hardFailures = "hard_failures"
    }

}

public enum UpdateOutcome: String, Codable, Equatable, Sendable {
    case updated
    case failed
    case skippedPinned = "skipped_pinned"
    case skippedDisabled = "skipped_disabled"
    case skippedUntrusted = "skipped_untrusted"
    case skippedNotOutdated = "skipped_not_outdated"
    case missing
    case cancelled

    public var isHardFailure: Bool {
        switch self {
        case .failed, .missing, .cancelled:
            true
        case .updated, .skippedPinned, .skippedDisabled, .skippedUntrusted, .skippedNotOutdated:
            false
        }
    }

    public var isSkipped: Bool {
        switch self {
        case .skippedPinned, .skippedDisabled, .skippedUntrusted, .skippedNotOutdated:
            true
        case .updated, .failed, .missing, .cancelled:
            false
        }
    }
}

extension UpdatePlanDecision {
    fileprivate var outcome: UpdateOutcome {
        switch self {
        case .willUpdate:
            .updated
        case .skippedPinned:
            .skippedPinned
        case .skippedDisabled:
            .skippedDisabled
        case .skippedUntrusted:
            .skippedUntrusted
        case .skippedNotOutdated:
            .skippedNotOutdated
        case .missing:
            .missing
        }
    }
}
