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
}

public protocol UpdateBarProcessRunning: AnyObject, Sendable {
    func run(executablePath: String, arguments: [String]) throws -> CommandResult
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

    public func checkNow() throws {
        let result = try runner.run(
            executablePath: executablePath,
            arguments: ["check", "--json", "--exit-zero-on-outdated"]
        )
        try ensureSuccess(result, allowedExitCodes: [0, 10])
    }

    public func update(id: String) throws {
        let result = try runner.run(
            executablePath: executablePath,
            arguments: ["update", id, "--yes", "--json"]
        )
        try ensureSuccess(result, allowedExitCodes: [0])
    }

    public func updateAllApproved() throws {
        let result = try runner.run(
            executablePath: executablePath,
            arguments: ["update", "--all", "--yes", "--json"]
        )
        try ensureSuccess(result, allowedExitCodes: [0])
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

    public func approve(id: String, field: String) throws {
        let result = try runner.run(
            executablePath: executablePath,
            arguments: ["approve", id, "--field", field, "--json"]
        )
        try ensureSuccess(result, allowedExitCodes: [0])
    }

    public func revoke(id: String, field: String) throws {
        let result = try runner.run(
            executablePath: executablePath,
            arguments: ["revoke", id, "--field", field, "--json"]
        )
        try ensureSuccess(result, allowedExitCodes: [0])
    }

    private func ensureSuccess(_ result: CommandResult, allowedExitCodes: Set<Int32>) throws {
        guard allowedExitCodes.contains(result.exitCode) else {
            throw UpdateBarCLIClientError.failed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }
}

public enum UpdateBarCLIClientError: Error, CustomStringConvertible, Equatable, Sendable {
    case failed(exitCode: Int32, stderr: String)

    public var description: String {
        switch self {
        case .failed(let exitCode, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "updatebar exited \(exitCode)" : "updatebar exited \(exitCode): \(detail)"
        }
    }
}

public final class ProcessRunner: UpdateBarProcessRunning, @unchecked Sendable {
    public init() {}

    public func run(executablePath: String, arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(
                decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(
                decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}
