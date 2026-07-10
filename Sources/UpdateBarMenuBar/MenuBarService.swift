import Foundation
import UpdateBarCore

public protocol MenuBarServicing: Sendable {
    func status(refresh: Bool) throws -> StatusSnapshot
    func scan(category: String?) throws -> ScanReport
    func registerScannedCandidates(
        _ candidates: [ScanCandidate],
        selectedIDs: [String],
        replace: Bool
    ) throws -> InitSummary
    func loadConfig() throws -> Config
    func saveConfig(_ config: Config) throws
    func checkNow(cancellationToken: CancellationToken?) throws
    func update(id: String, cancellationToken: CancellationToken?) throws
    func updateAllApproved(cancellationToken: CancellationToken?) throws
    func approvals(id: String) throws -> [CommandApprovalStatus]
    func approve(id: String, field: String, cancellationToken: CancellationToken?) throws
    func revoke(id: String, field: String, cancellationToken: CancellationToken?) throws
    func setEnabled(id: String, enabled: Bool) throws
}

extension MenuBarServicing {
    public func scan() throws -> ScanReport {
        try scan(category: nil)
    }

    public func checkNow() throws {
        try checkNow(cancellationToken: nil)
    }

    public func update(id: String) throws {
        try update(id: id, cancellationToken: nil)
    }

    public func updateAllApproved() throws {
        try updateAllApproved(cancellationToken: nil)
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
    private let manifestStore: ManifestStore
    private let stateStore: StateStore
    private let configStore: ConfigStore
    private let httpClient: HTTPClient
    private let injectedCommandRunner: (any CommandRunning)?
    private let now: () -> Date
    private let githubToken: String?

    public init(
        paths: AppPaths = AppPaths(),
        httpClient: HTTPClient = URLSessionHTTPClient(),
        commandRunner: (any CommandRunning)? = nil,
        now: @escaping () -> Date = Date.init,
        githubToken: String? = nil
    ) {
        self.paths = paths
        self.manifestStore = ManifestStore(paths: paths)
        self.stateStore = StateStore(paths: paths)
        self.configStore = ConfigStore(paths: paths)
        self.httpClient = httpClient
        self.injectedCommandRunner = commandRunner
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

    public func scan(category: String? = nil) throws -> ScanReport {
        let categoryFilter = try ScanCategory.filterValue(for: category)
        let detectors = try ScanCategory.defaultDetectors(for: categoryFilter)
        return try ScanService(
            commandRunner: commandRunner(for: nil),
            homeDirectory: paths.homeDirectory
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

    public func update(id: String, cancellationToken: CancellationToken? = nil) throws {
        _ = try updateRunner(cancellationToken: cancellationToken).update(
            ids: [id],
            all: false,
            assumeYes: true
        )
    }

    public func updateAllApproved(cancellationToken: CancellationToken? = nil) throws {
        _ = try updateRunner(cancellationToken: cancellationToken).update(
            ids: [],
            all: true,
            assumeYes: true
        )
    }

    public func approvals(id: String) throws -> [CommandApprovalStatus] {
        try registryService(cancellationToken: nil).approvals(id: id).map { status in
            CommandApprovalStatus(
                field: status.field,
                approved: status.approved,
                fingerprint: status.fingerprint,
                command: status.command,
                cwd: status.cwd
            )
        }
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

    private func registryService(cancellationToken: CancellationToken?) throws -> RegistryService {
        RegistryService(
            manifestStore: manifestStore,
            stateStore: stateStore,
            config: try configStore.loadExistingOrDefault(),
            httpClient: httpClient,
            commandRunner: commandRunner(for: cancellationToken),
            now: now,
            githubToken: githubToken
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
            confirm: { _ in true }
        )
    }

    private func commandRunner(for cancellationToken: CancellationToken?) -> any CommandRunning {
        injectedCommandRunner ?? CommandExecutor(cancellationToken: cancellationToken)
    }
}
