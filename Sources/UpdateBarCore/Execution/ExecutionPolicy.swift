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

public enum ExecutionError: Error, CustomStringConvertible, Equatable, Sendable {
    case invalidWorkingDirectory(String)
    case timedOut(command: String)
    case launchFailed(String)

    public var description: String {
        switch self {
        case let .invalidWorkingDirectory(path):
            return "\(path): working directory does not exist"
        case let .timedOut(command):
            return "\(command): timed out"
        case let .launchFailed(message):
            return message
        }
    }
}
