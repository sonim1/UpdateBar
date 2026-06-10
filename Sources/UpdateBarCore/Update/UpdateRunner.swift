import Foundation

public struct UpdateRunner {
    private let manifestStore: ManifestStore
    private let stateStore: StateStore
    private let config: Config
    private let httpClient: HTTPClient
    private let commandRunner: CommandRunning
    private let now: () -> Date
    private let githubToken: String?
    private let confirm: (UpdatePlanItem) -> Bool

    public init(
        manifestStore: ManifestStore = ManifestStore(),
        stateStore: StateStore = StateStore(),
        config: Config = .default,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        commandRunner: CommandRunning = CommandExecutor(),
        now: @escaping () -> Date = { Date() },
        githubToken: String? = nil,
        confirm: @escaping (UpdatePlanItem) -> Bool = { _ in false }
    ) {
        self.manifestStore = manifestStore
        self.stateStore = stateStore
        self.config = config
        self.httpClient = httpClient
        self.commandRunner = commandRunner
        self.now = now
        self.githubToken = githubToken
        self.confirm = confirm
    }

    public func update(ids: [String], all: Bool, assumeYes: Bool) throws -> [UpdateResult] {
        let manifest = try manifestStore.load()
        let state = try stateStore.load(now: now())
        let plan = UpdatePlanner(manifest: manifest, state: state).plan(ids: ids, all: all)
        var results: [UpdateResult] = []

        for planItem in plan {
            guard planItem.decision == .willUpdate else {
                results.append(UpdateResult(planItem: planItem, outcome: planItem.decision.outcome))
                continue
            }
            guard let recipe = manifest.item(id: planItem.id) else {
                results.append(UpdateResult(planItem: planItem, outcome: .missing))
                continue
            }
            guard assumeYes || confirm(planItem) else {
                results.append(UpdateResult(planItem: planItem, outcome: .cancelled))
                continue
            }

            let result = try runUpdate(recipe: recipe, planItem: planItem)
            results.append(result)
        }

        return results
    }

    private func runUpdate(recipe: Recipe, planItem: UpdatePlanItem) throws -> UpdateResult {
        do {
            let commandResult = try commandRunner.run(
                ShellCommand(command: recipe.update.cmd, cwd: recipe.update.cwd),
                policy: ExecutionPolicy(timeout: 30 * 60, maxOutputBytes: 256 * 1024)
            )
            guard commandResult.exitCode == 0 else {
                let error = "update.cmd exited \(commandResult.exitCode): \(commandResult.stderr)"
                try markFailure(recipe: recipe, error: error)
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
                githubToken: githubToken
            ).check(ids: [recipe.id], force: true)
            let check = checks.first
            return UpdateResult(
                planItem: planItem,
                outcome: .updated,
                current: check?.current,
                latest: check?.latest,
                error: check?.error
            )
        } catch {
            try markFailure(recipe: recipe, error: String(describing: error))
            return UpdateResult(
                planItem: planItem,
                outcome: .failed,
                error: SecretRedactor.redact(String(describing: error))
            )
        }
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
}

public struct UpdateResult: Codable, Equatable {
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
        self.id = id
        self.name = name
        self.outcome = outcome
        self.current = current
        self.latest = latest
        self.error = error
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

public enum UpdateOutcome: String, Codable, Equatable {
    case updated
    case failed
    case skippedPinned = "skipped_pinned"
    case skippedDisabled = "skipped_disabled"
    case skippedUntrusted = "skipped_untrusted"
    case skippedNotOutdated = "skipped_not_outdated"
    case missing
    case cancelled
}

private extension UpdatePlanDecision {
    var outcome: UpdateOutcome {
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
