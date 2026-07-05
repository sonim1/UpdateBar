import Foundation

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

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
        try Self.configureNonBlocking(stdout.fileHandleForReading)
        try Self.configureNonBlocking(stderr.fileHandleForReading)
        let stdoutData = LockedData(maxBytes: policy.maxOutputBytes)
        let stderrData = LockedData(maxBytes: policy.maxOutputBytes)
        let stopReaders = LockedFlag()

        do {
            try process.run()
        } catch {
            throw ExecutionError.launchFailed(String(describing: error))
        }

        let readersFinished = DispatchGroup()
        readersFinished.enter()
        DispatchQueue.global().async {
            Self.drain(stdout.fileHandleForReading, into: stdoutData, stopReaders: stopReaders)
            readersFinished.leave()
        }
        readersFinished.enter()
        DispatchQueue.global().async {
            Self.drain(stderr.fileHandleForReading, into: stderrData, stopReaders: stopReaders)
            readersFinished.leave()
        }

        let deadline = Date().addingTimeInterval(policy.timeout)
        while process.isRunning && Date() < deadline {
            if cancellationToken?.isCancelled == true {
                stopProcess(process)
                finishReaders(
                    readersFinished, stdout: stdout, stderr: stderr, stopReaders: stopReaders,
                    timeout: 2.0)
                throw ExecutionError.cancelled(command: command.command)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            stopProcess(process)
            finishReaders(
                readersFinished, stdout: stdout, stderr: stderr, stopReaders: stopReaders,
                timeout: 2.0)
            throw ExecutionError.timedOut(command: command.command)
        }
        process.waitUntilExit()
        finishReaders(
            readersFinished, stdout: stdout, stderr: stderr, stopReaders: stopReaders, timeout: 0.2)

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData.data(), as: UTF8.self),
            stderr: String(decoding: stderrData.data(), as: UTF8.self)
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

    private func finishReaders(
        _ readersFinished: DispatchGroup,
        stdout: Pipe,
        stderr: Pipe,
        stopReaders: LockedFlag,
        timeout: TimeInterval
    ) {
        stopReaders.set()
        if readersFinished.wait(timeout: .now() + timeout) == .success {
            return
        }

        stdout.fileHandleForReading.closeFile()
        stderr.fileHandleForReading.closeFile()
        _ = readersFinished.wait(timeout: .now() + 1.0)
    }

    private static func configureNonBlocking(_ handle: FileHandle) throws {
        let fd = handle.fileDescriptor
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else {
            throw ExecutionError.launchFailed("failed to inspect output pipe flags")
        }
        guard fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw ExecutionError.launchFailed("failed to configure output pipe")
        }
    }

    private static func drain(
        _ handle: FileHandle,
        into output: LockedData,
        stopReaders: LockedFlag
    ) {
        let fd = handle.fileDescriptor
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBufferPointer { pointer in
                read(fd, pointer.baseAddress, pointer.count)
            }

            if count > 0 {
                output.append(Data(buffer.prefix(count)))
                continue
            }
            if count == 0 {
                break
            }
            if errno == EINTR {
                continue
            }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                if stopReaders.isSet {
                    break
                }
                Thread.sleep(forTimeInterval: 0.005)
                continue
            }
            break
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

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
