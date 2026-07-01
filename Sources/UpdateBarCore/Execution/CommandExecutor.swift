import Foundation

public protocol CommandRunning {
    func run(_ command: ShellCommand, policy: ExecutionPolicy) throws -> CommandResult
}

public struct CommandExecutor: CommandRunning {
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
        if let cwd = command.cwd, !fileManager.fileExists(atPath: cwd) {
            throw ExecutionError.invalidWorkingDirectory(cwd)
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
        let stdoutData = LockedData(maxBytes: policy.maxOutputBytes)
        let stderrData = LockedData(maxBytes: policy.maxOutputBytes)

        do {
            try process.run()
        } catch {
            throw ExecutionError.launchFailed(String(describing: error))
        }

        let readersFinished = DispatchGroup()
        readersFinished.enter()
        DispatchQueue.global().async {
            Self.drain(stdout.fileHandleForReading, into: stdoutData)
            readersFinished.leave()
        }
        readersFinished.enter()
        DispatchQueue.global().async {
            Self.drain(stderr.fileHandleForReading, into: stderrData)
            readersFinished.leave()
        }

        let deadline = Date().addingTimeInterval(policy.timeout)
        while process.isRunning && Date() < deadline {
            if cancellationToken?.isCancelled == true {
                process.terminate()
                process.waitUntilExit()
                _ = readersFinished.wait(timeout: .now() + 2)
                throw ExecutionError.cancelled(command: command.command)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            _ = readersFinished.wait(timeout: .now() + 2)
            throw ExecutionError.timedOut(command: command.command)
        }
        process.waitUntilExit()
        readersFinished.wait()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData.data(), as: UTF8.self),
            stderr: String(decoding: stderrData.data(), as: UTF8.self)
        )
    }

    private func scrubbedEnvironment() -> [String: String] {
        let allowedKeys = Set(["PATH", "HOME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR", "USER"])
        return environment.filter { allowedKeys.contains($0.key) }
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
