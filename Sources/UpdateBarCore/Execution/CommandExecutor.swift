import Foundation

public protocol CommandRunning: Sendable {
    func run(_ command: ShellCommand, policy: ExecutionPolicy) throws -> CommandResult
}

public protocol CommandLaunching: CommandRunning {
    func prepare(_ command: ShellCommand, policy: ExecutionPolicy) throws -> any PreparedCommand
}

extension CommandLaunching {
    public func run(_ command: ShellCommand, policy: ExecutionPolicy) throws -> CommandResult {
        try prepare(command, policy: policy).start().wait()
    }
}

/// The executor keeps immutable configuration and creates a fresh `Process`
/// for every command, so instances can be shared by update workers.
public struct CommandExecutor: CommandLaunching, @unchecked Sendable {
    private let environment: [String: String]
    private let fileManager: FileManager
    private let cancellationToken: CancellationToken?

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        cancellationToken: CancellationToken? = nil
    ) {
        self.environment = environment
        self.fileManager = fileManager
        self.cancellationToken = cancellationToken
    }

    public func prepare(_ command: ShellCommand, policy: ExecutionPolicy) throws
        -> any PreparedCommand
    {
        if let cwd = command.cwd {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: cwd, isDirectory: &isDirectory),
                isDirectory.boolValue
            else {
                throw ExecutionError.invalidWorkingDirectory(cwd)
            }
        }
        return try SubprocessLifecycle.prepare(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", command.command],
            currentDirectoryURL: command.cwd.map { URL(fileURLWithPath: $0) },
            environment: scrubbedEnvironment(),
            timeout: policy.timeout,
            maxOutputBytes: policy.maxOutputBytes,
            cancellationToken: cancellationToken,
            commandDescription: command.command
        )
    }

    private func scrubbedEnvironment() -> [String: String] {
        let allowedKeys = Set(["PATH", "HOME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR", "USER"])
        var scrubbed = environment.filter { allowedKeys.contains($0.key) }
        if let path = scrubbed["PATH"] {
            scrubbed["PATH"] =
                path
                .split(separator: ":", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { $0.hasPrefix("/") }
                .joined(separator: ":")
        }
        return scrubbed
    }

}
