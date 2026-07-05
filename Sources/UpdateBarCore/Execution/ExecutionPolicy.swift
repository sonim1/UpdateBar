import Foundation

public struct ExecutionPolicy: Equatable, Sendable {
    public var timeout: TimeInterval
    public var maxOutputBytes: Int

    public init(timeout: TimeInterval, maxOutputBytes: Int) {
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
    }
}

public struct CommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

public enum ExecutionError: Error, CustomStringConvertible, Equatable, Sendable {
    case invalidWorkingDirectory(String)
    case timedOut(command: String)
    case launchFailed(String)
    case cancelled(command: String)

    public var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case .invalidWorkingDirectory(let path):
            return "\(redacted(path)): working directory does not exist"
        case .timedOut(let command):
            return "\(redacted(command)): timed out"
        case .launchFailed(let message):
            return redacted(message)
        case .cancelled(let command):
            return "\(redacted(command)): cancelled"
        }
    }

    private func redacted(_ text: String) -> String {
        SecretRedactor.redact(text)
    }
}
