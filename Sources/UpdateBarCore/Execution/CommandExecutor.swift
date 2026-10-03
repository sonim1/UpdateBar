import Foundation

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

public protocol CommandRunning: Sendable {
    func run(_ command: ShellCommand, policy: ExecutionPolicy) throws -> CommandResult
}

/// The executor keeps immutable configuration and creates a fresh `Process`
/// for every command, so instances can be shared by update workers.
public struct CommandExecutor: CommandRunning, @unchecked Sendable {
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

    public func run(_ command: ShellCommand, policy: ExecutionPolicy) throws -> CommandResult {
        if let cwd = command.cwd {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: cwd, isDirectory: &isDirectory),
                isDirectory.boolValue
            else {
                throw ExecutionError.invalidWorkingDirectory(cwd)
            }
        }
        if cancellationToken?.isCancelled == true {
            throw ExecutionError.cancelled(command: command.command)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command.command]
        if let cwd = command.cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        process.environment = scrubbedEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let output = try SubprocessOutputCapture(
            stdout: stdout.fileHandleForReading,
            stderr: stderr.fileHandleForReading,
            maxOutputBytes: policy.maxOutputBytes
        )

        do {
            try process.run()
        } catch {
            throw ExecutionError.launchFailed(String(describing: error))
        }

        output.start()

        let deadline = Date().addingTimeInterval(policy.timeout)
        while process.isRunning && Date() < deadline {
            if cancellationToken?.isCancelled == true {
                stopProcess(process)
                output.finish(timeout: 2.0)
                throw ExecutionError.cancelled(command: command.command)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            stopProcess(process)
            output.finish(timeout: 2.0)
            throw ExecutionError.timedOut(command: command.command)
        }
        output.finish(timeout: 0.2)

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: output.capturedStdout,
            stderr: output.capturedStderr
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

    private func stopProcess(_ process: Process) {
        guard process.isRunning else { return }

        process.interrupt()
        if waitForExit(process, timeout: 0.5) { return }

        process.terminate()
        if waitForExit(process, timeout: 1.0) { return }

        kill(process.processIdentifier, SIGKILL)
        _ = waitForExit(process, timeout: 1.0)
    }

    private func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        return !process.isRunning
    }

}
