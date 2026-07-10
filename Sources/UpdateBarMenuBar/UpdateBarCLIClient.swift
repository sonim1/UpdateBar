import Foundation
import UpdateBarCore

public struct CommandCall: Equatable, Sendable {
    public var executablePath: String
    public var arguments: [String]

    public init(executablePath: String, arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

public struct CommandApprovalStatus: Decodable, Equatable, Sendable {
    public var field: String
    public var approved: Bool
    public var fingerprint: String
    public var command: String
    public var cwd: String?

    public init(field: String, approved: Bool, fingerprint: String, command: String, cwd: String?) {
        self.field = field
        self.approved = approved
        self.fingerprint = fingerprint
        self.command = command
        self.cwd = cwd
    }
}

public protocol UpdateBarProcessRunning: AnyObject, Sendable {
    func run(executablePath: String, arguments: [String]) throws -> CommandResult
    func run(
        executablePath: String,
        arguments: [String],
        cancellationToken: CancellationToken?
    ) throws -> CommandResult
}

extension UpdateBarProcessRunning {
    public func run(
        executablePath: String,
        arguments: [String],
        cancellationToken: CancellationToken?
    ) throws -> CommandResult {
        try run(executablePath: executablePath, arguments: arguments)
    }
}

public struct UpdateBarCLIClient: Sendable {
    private let executablePath: String
    private let runner: any UpdateBarProcessRunning

    public init(executablePath: String, runner: any UpdateBarProcessRunning = ProcessRunner()) {
        self.executablePath = executablePath
        self.runner = runner
    }

    public func status(refresh: Bool = false) throws -> StatusSnapshot {
        var arguments = ["status", "--json", "--exit-zero-on-outdated"]
        if refresh {
            arguments.append("--refresh")
        }
        let result = try runner.run(executablePath: executablePath, arguments: arguments)
        try ensureSuccess(result, allowedExitCodes: [0, 10])
        return try JSONDecoder.updateBar.decode(StatusSnapshot.self, from: Data(result.stdout.utf8))
    }

    public func scan(category: String? = nil) throws -> ScanReport {
        var arguments = ["scan", "--json"]
        if let category, !category.isEmpty {
            arguments += ["--category", category]
        }
        let result = try runner.run(executablePath: executablePath, arguments: arguments)
        try ensureSuccess(result, allowedExitCodes: [0])
        return try JSONDecoder.updateBar.decode(ScanReport.self, from: Data(result.stdout.utf8))
    }

    public func registerScannedCandidates(
        _ candidates: [ScanCandidate],
        selectedIDs: [String],
        replace: Bool
    ) throws -> InitSummary {
        guard !selectedIDs.isEmpty else {
            return InitSummary(added: [], replaced: [], skipped: [])
        }
        var arguments = ["init", "--select", selectedIDs.joined(separator: ","), "--json"]
        if replace {
            arguments.append("--replace")
        }
        let result = try runner.run(executablePath: executablePath, arguments: arguments)
        try ensureSuccess(result, allowedExitCodes: [0])
        let payload = try JSONDecoder.updateBar.decode(
            InitResultPayload.self,
            from: Data(result.stdout.utf8)
        )
        return InitSummary(added: payload.added, replaced: payload.replaced, skipped: payload.skipped)
    }

    public func loadConfig() throws -> Config {
        let result = try runner.run(
            executablePath: executablePath,
            arguments: ["config", "get", "--json"]
        )
        try ensureSuccess(result, allowedExitCodes: [0])
        let payload = try JSONDecoder.updateBar.decode(
            ConfigDumpPayload.self,
            from: Data(result.stdout.utf8)
        )
        var config = Config.default
        try config.set("refresh.interval", value: payload.refresh.interval)
        try config.set(
            "security.require_https_source",
            value: String(payload.security.requireHTTPSSource)
        )
        return config
    }

    public func saveConfig(_ config: Config) throws {
        for (key, value) in [
            ("refresh.interval", config.refresh.interval.description),
            ("security.require_https_source", String(config.security.requireHTTPSSource)),
        ] {
            let result = try runner.run(
                executablePath: executablePath,
                arguments: ["config", "set", key, value, "--json"]
            )
            try ensureSuccess(result, allowedExitCodes: [0])
        }
    }

    public func checkNow(cancellationToken: CancellationToken? = nil) throws {
        let result = try runner.run(
            executablePath: executablePath,
            arguments: ["check", "--json", "--force", "--exit-zero-on-outdated"],
            cancellationToken: cancellationToken
        )
        try ensureSuccess(result, allowedExitCodes: [0, 10])
    }

    public func update(id: String, cancellationToken: CancellationToken? = nil) throws {
        let result = try runner.run(
            executablePath: executablePath,
            arguments: ["update", id, "--yes", "--json"],
            cancellationToken: cancellationToken
        )
        try ensureSuccess(result, allowedExitCodes: [0, 2, 3])
    }

    public func updateAllApproved(cancellationToken: CancellationToken? = nil) throws {
        let result = try runner.run(
            executablePath: executablePath,
            arguments: ["update", "--yes", "--json"],
            cancellationToken: cancellationToken
        )
        try ensureSuccess(result, allowedExitCodes: [0, 2, 3])
    }

    public func approvals(id: String) throws -> [CommandApprovalStatus] {
        let result = try runner.run(
            executablePath: executablePath,
            arguments: ["approvals", id, "--json"]
        )
        try ensureSuccess(result, allowedExitCodes: [0])
        return try JSONDecoder.updateBar.decode(
            [CommandApprovalStatus].self, from: Data(result.stdout.utf8))
    }

    public func approve(id: String, field: String, cancellationToken: CancellationToken? = nil)
        throws
    {
        let result = try runner.run(
            executablePath: executablePath,
            arguments: ["approve", id, "--field", field, "--json"],
            cancellationToken: cancellationToken
        )
        try ensureSuccess(result, allowedExitCodes: [0])
    }

    public func revoke(id: String, field: String, cancellationToken: CancellationToken? = nil)
        throws
    {
        let result = try runner.run(
            executablePath: executablePath,
            arguments: ["revoke", id, "--field", field, "--json"],
            cancellationToken: cancellationToken
        )
        try ensureSuccess(result, allowedExitCodes: [0])
    }

    public func setEnabled(id: String, enabled: Bool) throws {
        let result = try runner.run(
            executablePath: executablePath,
            arguments: [enabled ? "enable" : "disable", id, "--json"],
            cancellationToken: nil
        )
        try ensureSuccess(result, allowedExitCodes: [0])
    }

    private func ensureSuccess(_ result: CommandResult, allowedExitCodes: Set<Int32>) throws {
        guard allowedExitCodes.contains(result.exitCode) else {
            let detail = Self.errorDetail(from: result)
            throw UpdateBarCLIClientError.failed(exitCode: result.exitCode, stderr: detail)
        }
    }

    private static func errorDetail(from result: CommandResult) -> String {
        if let detail = jsonErrorDetail(from: result.stdout) {
            return SecretRedactor.redact(detail)
        }
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return SecretRedactor.redact(stderr)
        }
        return ""
    }

    private static func jsonErrorDetail(from stdout: String) -> String? {
        struct ErrorPayload: Decodable {
            var errors: [String]?
            var error: String?
        }

        guard let data = stdout.data(using: .utf8),
            let payload = try? JSONDecoder.updateBar.decode(ErrorPayload.self, from: data)
        else {
            return nil
        }
        if let errors = payload.errors?.filter({ !$0.isEmpty }), !errors.isEmpty {
            return errors.joined(separator: "\n")
        }
        if let error = payload.error, !error.isEmpty {
            return error
        }
        return nil
    }

    private struct InitResultPayload: Decodable {
        var added: [String]
        var replaced: [String]
        var skipped: [String]
    }

    private struct ConfigDumpPayload: Decodable {
        var refresh: Refresh
        var security: Security

        struct Refresh: Decodable {
            var interval: String
        }

        struct Security: Decodable {
            var requireHTTPSSource: Bool

            enum CodingKeys: String, CodingKey {
                case requireHTTPSSource = "require_https_source"
            }
        }
    }
}

public enum UpdateBarCLIClientError: Error, CustomStringConvertible, Equatable, Sendable {
    case failed(exitCode: Int32, stderr: String)
    case timedOut
    case cancelled

    public var description: String {
        switch self {
        case .failed(let exitCode, let stderr):
            let detail = SecretRedactor.redact(
                stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            return detail.isEmpty
                ? "updatebar exited \(exitCode)" : "updatebar exited \(exitCode): \(detail)"
        case .timedOut:
            return "updatebar timed out"
        case .cancelled:
            return "updatebar cancelled"
        }
    }
}

public final class ProcessRunner: UpdateBarProcessRunning, @unchecked Sendable {
    private let timeout: TimeInterval
    private let maxOutputBytes: Int

    public init(timeout: TimeInterval = 30, maxOutputBytes: Int = 1_048_576) {
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
    }

    public func run(executablePath: String, arguments: [String]) throws -> CommandResult {
        try run(executablePath: executablePath, arguments: arguments, cancellationToken: nil)
    }

    public func run(
        executablePath: String,
        arguments: [String],
        cancellationToken: CancellationToken?
    ) throws -> CommandResult {
        if cancellationToken?.isCancelled == true {
            throw UpdateBarCLIClientError.cancelled
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = scrubbedEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let stdoutData = LockedData(maxBytes: maxOutputBytes)
        let stderrData = LockedData(maxBytes: maxOutputBytes)
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        try process.run()
        let readersFinished = DispatchGroup()
        readersFinished.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            Self.drain(stdout.fileHandleForReading, into: stdoutData)
            readersFinished.leave()
        }
        readersFinished.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            Self.drain(stderr.fileHandleForReading, into: stderrData)
            readersFinished.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                terminateProcess(process, gracefully: true)
                _ = finished.wait(timeout: .now() + 2)
                _ = readersFinished.wait(timeout: .now() + 2)
                throw UpdateBarCLIClientError.timedOut
            }
            if finished.wait(timeout: .now() + min(0.05, remaining)) == .success {
                break
            }
            if cancellationToken?.isCancelled == true {
                terminateProcess(process, gracefully: true)
                _ = finished.wait(timeout: .now() + 2)
                _ = readersFinished.wait(timeout: .now() + 2)
                throw UpdateBarCLIClientError.cancelled
            }
        }
        readersFinished.wait()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData.data(), as: UTF8.self),
            stderr: String(decoding: stderrData.data(), as: UTF8.self)
        )
    }

    private func scrubbedEnvironment() -> [String: String] {
        SubprocessEnvironment.presentation(from: ProcessInfo.processInfo.environment)
    }

    private func terminateProcess(_ process: Process, gracefully: Bool) {
        if !gracefully {
            process.terminate()
            return
        }

        process.interrupt()
        let softDeadline = Date().addingTimeInterval(0.5)
        while process.isRunning {
            if Date() >= softDeadline {
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
        }
    }

    private static func drain(_ handle: FileHandle, into output: LockedData) {
        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            output.append(data)
        }
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private let maxBytes: Int
    private var storage = Data()

    init(maxBytes: Int) {
        self.maxBytes = max(0, maxBytes)
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        let remaining = maxBytes - storage.count
        if remaining > 0 {
            storage.append(data.prefix(remaining))
        }
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
