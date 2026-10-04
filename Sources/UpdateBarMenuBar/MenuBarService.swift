import Foundation
import UpdateBarCore

public struct MenuBarRefreshSnapshot: Equatable {
    public let status: StatusSnapshot
    public let approvalsByItemID: [String: [CommandApprovalStatus]]

    public init(status: StatusSnapshot, approvalsByItemID: [String: [CommandApprovalStatus]]) {
        self.status = status
        self.approvalsByItemID = approvalsByItemID
    }
}

public protocol MenuBarServicing: Sendable {
    func status(refresh: Bool) throws -> StatusSnapshot
    func refreshSnapshot(refresh: Bool) throws -> MenuBarRefreshSnapshot
    func scan(category: String?) throws -> ScanReport
    func registerScannedCandidates(
        _ candidates: [ScanCandidate],
        selectedIDs: [String],
        replace: Bool
    ) throws -> InitSummary
    func loadConfig() throws -> Config
    func saveConfig(_ config: Config) throws
    func checkNow(cancellationToken: CancellationToken?) throws
    func update(
        ids: [String],
        cancellationToken: CancellationToken?,
        onEvent: UpdateProgressHandler?,
        stopSignal: UpdateStopSignal?
    ) throws
    func updateAllApproved(
        cancellationToken: CancellationToken?,
        onEvent: UpdateProgressHandler?,
        stopSignal: UpdateStopSignal?
    ) throws
    func approvals(id: String) throws -> [CommandApprovalStatus]
    func approve(id: String, field: String, cancellationToken: CancellationToken?) throws
    func revoke(id: String, field: String, cancellationToken: CancellationToken?) throws
    func setEnabled(id: String, enabled: Bool) throws
    func setPinned(id: String, pinned: Bool) throws
    func history(since: Date?) throws -> [HistoryEvent]
}

extension MenuBarServicing {
    public func refreshSnapshot(refresh: Bool = false) throws -> MenuBarRefreshSnapshot {
        let snapshot = try status(refresh: refresh)
        var rows: [String: [CommandApprovalStatus]] = [:]
        for item in snapshot.items {
            let statuses = try approvals(id: item.id)
            if !statuses.isEmpty {
                rows[item.id] = statuses
            }
        }
        return MenuBarRefreshSnapshot(status: snapshot, approvalsByItemID: rows)
    }

    public func scan() throws -> ScanReport {
        try scan(category: nil)
    }

    public func checkNow() throws {
        try checkNow(cancellationToken: nil)
    }

    public func update(id: String) throws {
        try update(ids: [id], cancellationToken: nil, onEvent: nil, stopSignal: nil)
    }

    public func update(id: String, cancellationToken: CancellationToken?) throws {
        try update(ids: [id], cancellationToken: cancellationToken, onEvent: nil, stopSignal: nil)
    }

    public func update(
        id: String,
        cancellationToken: CancellationToken?,
        onEvent: UpdateProgressHandler?,
        stopSignal: UpdateStopSignal?
    ) throws {
        try update(
            ids: [id],
            cancellationToken: cancellationToken,
            onEvent: onEvent,
            stopSignal: stopSignal
        )
    }

    public func update(ids: [String]) throws {
        try update(ids: ids, cancellationToken: nil, onEvent: nil, stopSignal: nil)
    }

    public func updateAllApproved() throws {
        try updateAllApproved(cancellationToken: nil, onEvent: nil, stopSignal: nil)
    }

    public func updateAllApproved(cancellationToken: CancellationToken?) throws {
        try updateAllApproved(cancellationToken: cancellationToken, onEvent: nil, stopSignal: nil)
    }

    public func approve(id: String, field: String) throws {
        try approve(id: id, field: field, cancellationToken: nil)
    }

    public func revoke(id: String, field: String) throws {
        try revoke(id: id, field: field, cancellationToken: nil)
    }
}

extension UpdateBarCLIClient: MenuBarServicing {}

public struct CoreMenuBarService: MenuBarServicing, @unchecked Sendable {
    private let paths: AppPaths
    private let scanHomeDirectory: URL
    private let manifestStore: ManifestStore
    private let stateStore: StateStore
    private let configStore: ConfigStore
    private let httpClient: HTTPClient
    private let injectedCommandRunner: (any CommandLaunching)?
    private let commandEnvironment: [String: String]
    private let now: @Sendable () -> Date
    private let githubToken: String?

    public init(
        paths: AppPaths = AppPaths(),
        scanHomeDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        commandRunner: (any CommandLaunching)? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        githubToken: String? = nil
    ) {
        self.paths = paths
        let userHome = scanHomeDirectory ?? Self.userHomeDirectory(environment: environment)
        self.scanHomeDirectory = userHome
        self.manifestStore = ManifestStore(paths: paths)
        self.stateStore = StateStore(paths: paths)
        self.configStore = ConfigStore(paths: paths)
        self.httpClient = httpClient
        self.injectedCommandRunner = commandRunner
        self.commandEnvironment = MenuBarCommandEnvironment.make(
            base: environment,
            homeDirectory: userHome
        )
        self.now = now
        self.githubToken = githubToken
    }

    public func status(refresh: Bool = false) throws -> StatusSnapshot {
        try StatusService(
            manifestStore: manifestStore,
            stateStore: stateStore,
            configStore: configStore,
            now: now
        ).snapshot(refresh: refresh)
    }

    public func refreshSnapshot(refresh: Bool = false) throws -> MenuBarRefreshSnapshot {
        let snapshot = try StatusService(
            manifestStore: manifestStore,
            stateStore: stateStore,
            configStore: configStore,
            now: now
        ).snapshotWithApprovals(refresh: refresh)
        return MenuBarRefreshSnapshot(
            status: snapshot.status,
            approvalsByItemID: snapshot.approvalsByItemID.mapValues {
                $0.map(Self.commandApprovalStatus)
            }
        )
    }

    public func scan(category: String? = nil) throws -> ScanReport {
        let categoryFilter = try ScanCategory.filterValue(for: category)
        let detectors = try ScanCategory.defaultDetectors(for: categoryFilter)
        return try ScanService(
            commandRunner: commandRunner(for: nil),
            homeDirectory: scanHomeDirectory
        )
        .scan(detectors: detectors)
        .filtered(category: categoryFilter)
    }

    public func registerScannedCandidates(
        _ candidates: [ScanCandidate],
        selectedIDs: [String],
        replace: Bool
    ) throws -> InitSummary {
        try InitService(registryService: registryService(cancellationToken: nil)).register(
            candidates: candidates,
            selectedIDs: selectedIDs,
            replace: replace
        )
    }

    public func loadConfig() throws -> Config {
        try configStore.loadExistingOrDefault()
    }

    public func saveConfig(_ config: Config) throws {
        try configStore.save(config)
    }

    public func checkNow(cancellationToken: CancellationToken? = nil) throws {
        _ = try registryService(cancellationToken: cancellationToken).check(force: true)
    }

    public func update(
        ids: [String],
        cancellationToken: CancellationToken? = nil,
        onEvent: UpdateProgressHandler? = nil,
        stopSignal: UpdateStopSignal? = nil
    ) throws {
        _ = try updateRunner(cancellationToken: cancellationToken).update(
            ids: ids,
            all: false,
            assumeYes: true,
            onEvent: onEvent,
            stopSignal: stopSignal
        )
    }

    public func updateAllApproved(
        cancellationToken: CancellationToken? = nil,
        onEvent: UpdateProgressHandler? = nil,
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

    public func approvals(id: String) throws -> [CommandApprovalStatus] {
        try registryService(cancellationToken: nil).approvals(id: id).map(
            Self.commandApprovalStatus)
    }

    private static func commandApprovalStatus(_ status: ApprovalStatus) -> CommandApprovalStatus {
        CommandApprovalStatus(
            field: status.field,
            approved: status.approved,
            fingerprint: status.fingerprint,
            command: status.command,
            cwd: status.cwd
        )
    }

    public func approve(id: String, field: String, cancellationToken: CancellationToken? = nil)
        throws
    {
        _ = try registryService(cancellationToken: cancellationToken).approve(id: id, field: field)
    }

    public func revoke(id: String, field: String, cancellationToken: CancellationToken? = nil)
        throws
    {
        _ = try registryService(cancellationToken: cancellationToken).revokeApproval(
            id: id, field: field)
    }

    public func setEnabled(id: String, enabled: Bool) throws {
        _ = try registryService(cancellationToken: nil).setEnabled(id: id, enabled: enabled)
    }

    public func setPinned(id: String, pinned: Bool) throws {
        let registry = try registryService(cancellationToken: nil)
        if pinned {
            _ = try registry.pin(id: id)
        } else {
            _ = try registry.unpin(id: id)
        }
    }

    public func history(since: Date?) throws -> [HistoryEvent] {
        try HistoryStore(paths: paths).events(since: since)
    }

    private func registryService(cancellationToken: CancellationToken?) throws -> RegistryService {
        RegistryService(
            manifestStore: manifestStore,
            stateStore: stateStore,
            config: try configStore.loadExistingOrDefault(),
            httpClient: httpClient,
            commandRunner: commandRunner(for: cancellationToken),
            now: now,
            githubToken: githubToken,
            historyStore: HistoryStore(paths: paths)
        )
    }

    private func updateRunner(cancellationToken: CancellationToken?) throws -> UpdateRunner {
        UpdateRunner(
            manifestStore: manifestStore,
            stateStore: stateStore,
            config: try configStore.loadExistingOrDefault(),
            httpClient: httpClient,
            commandRunner: commandRunner(for: cancellationToken),
            now: now,
            githubToken: githubToken,
            confirm: { _ in true },
            historyStore: HistoryStore(paths: paths)
        )
    }

    private func commandRunner(for cancellationToken: CancellationToken?) -> any CommandLaunching {
        injectedCommandRunner
            ?? CommandExecutor(
                environment: commandEnvironment,
                cancellationToken: cancellationToken
            )
    }

    private static func userHomeDirectory(environment: [String: String]) -> URL {
        guard let home = environment["HOME"], !home.isEmpty else {
            return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        }
        return URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL
    }
}
