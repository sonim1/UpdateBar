import Foundation
import UpdateBarCore

public protocol MenuBarServicing: Sendable {
    func status(refresh: Bool) throws -> StatusSnapshot
    func checkNow(cancellationToken: CancellationToken?) throws
    func update(id: String, cancellationToken: CancellationToken?) throws
    func updateAllApproved(cancellationToken: CancellationToken?) throws
    func approvals(id: String) throws -> [CommandApprovalStatus]
    func approve(id: String, field: String, cancellationToken: CancellationToken?) throws
    func revoke(id: String, field: String, cancellationToken: CancellationToken?) throws
}

public extension MenuBarServicing {
    func checkNow() throws {
        try checkNow(cancellationToken: nil)
    }

    func update(id: String) throws {
        try update(id: id, cancellationToken: nil)
    }

    func updateAllApproved() throws {
        try updateAllApproved(cancellationToken: nil)
    }

    func approve(id: String, field: String) throws {
        try approve(id: id, field: field, cancellationToken: nil)
    }

    func revoke(id: String, field: String) throws {
        try revoke(id: id, field: field, cancellationToken: nil)
    }
}

extension UpdateBarCLIClient: MenuBarServicing {}

public struct CoreMenuBarService: MenuBarServicing, @unchecked Sendable {
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

    public func approve(id: String, field: String, cancellationToken: CancellationToken? = nil) throws {
        _ = try registryService(cancellationToken: cancellationToken).approve(id: id, field: field)
    }

    public func revoke(id: String, field: String, cancellationToken: CancellationToken? = nil) throws {
        _ = try registryService(cancellationToken: cancellationToken).revokeApproval(id: id, field: field)
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
