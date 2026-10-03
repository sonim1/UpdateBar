import Foundation

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

public protocol PreparedCommand: Sendable {
    func start() throws -> any RunningCommand
}

public protocol RunningCommand: Sendable {
    var processIdentifier: Int32? { get }
    var processGroupIdentifier: Int32? { get }
    func wait() throws -> CommandResult
}

extension RunningCommand {
    public var processIdentifier: Int32? { nil }
    public var processGroupIdentifier: Int32? { nil }
}

package enum SubprocessLifecycle {
    package static func prepare(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String],
        timeout: TimeInterval?,
        maxOutputBytes: Int,
        cancellationToken: CancellationToken?,
        commandDescription: String,
        processGroupIdentifier: @escaping @Sendable (pid_t) -> pid_t = { getpgid($0) }
    ) throws -> any PreparedCommand {
        if cancellationToken?.isCancelled == true {
            throw ExecutionError.cancelled(command: commandDescription)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let output = try SubprocessOutputCapture(
            stdout: stdout.fileHandleForReading,
            stderr: stderr.fileHandleForReading,
            maxOutputBytes: maxOutputBytes
        )
        return FoundationPreparedCommand(
            process: process,
            output: output,
            timeout: timeout,
            cancellationToken: cancellationToken,
            commandDescription: commandDescription,
            processGroupIdentifier: processGroupIdentifier
        )
    }
}

private final class FoundationPreparedCommand: PreparedCommand, @unchecked Sendable {
    private let process: Process
    private let output: SubprocessOutputCapture
    private let timeout: TimeInterval?
    private let cancellationToken: CancellationToken?
    private let commandDescription: String
    private let processGroupIdentifier: @Sendable (pid_t) -> pid_t
    private let lock = NSLock()
    private var started = false

    init(
        process: Process,
        output: SubprocessOutputCapture,
        timeout: TimeInterval?,
        cancellationToken: CancellationToken?,
        commandDescription: String,
        processGroupIdentifier: @escaping @Sendable (pid_t) -> pid_t
    ) {
        self.process = process
        self.output = output
        self.timeout = timeout
        self.cancellationToken = cancellationToken
        self.commandDescription = commandDescription
        self.processGroupIdentifier = processGroupIdentifier
    }

    func start() throws -> any RunningCommand {
        lock.lock()
        guard !started else {
            lock.unlock()
            throw ExecutionError.launchFailed("prepared command was already started")
        }
        started = true
        lock.unlock()

        if cancellationToken?.isCancelled == true {
            throw ExecutionError.cancelled(command: commandDescription)
        }
        do {
            try process.run()
        } catch {
            throw ExecutionError.launchFailed(String(describing: error))
        }
        output.start()

        let processID = process.processIdentifier
        let hostGroupID = getpgrp()
        let observedGroupID = processGroupIdentifier(processID)
        let ownedGroupID: pid_t?
        if observedGroupID == processID, observedGroupID != hostGroupID {
            ownedGroupID = observedGroupID
        } else if !process.isRunning, observedGroupID == -1 {
            // Very short commands can exit and be reaped before the ownership
            // probe. They have already completed and cannot enter cleanup.
            ownedGroupID = nil
        } else {
            stopDirectChild()
            output.finish(timeout: 2)
            throw ExecutionError.launchFailed(
                "subprocess did not start in an isolated process group"
            )
        }

        return FoundationRunningCommand(
            process: process,
            output: output,
            timeout: timeout,
            startedAtUptime: ProcessInfo.processInfo.systemUptime,
            cancellationToken: cancellationToken,
            commandDescription: commandDescription,
            ownedGroupID: ownedGroupID,
            hostGroupID: hostGroupID
        )
    }

    private func stopDirectChild() {
        guard process.isRunning else { return }
        process.terminate()
        if waitForDirectExit(timeout: 0.5) { return }
        _ = kill(process.processIdentifier, SIGKILL)
        _ = waitForDirectExit(timeout: 1)
    }

    private func waitForDirectExit(timeout: TimeInterval) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        return !process.isRunning
    }
}

private final class FoundationRunningCommand: RunningCommand, @unchecked Sendable {
    private let process: Process
    private let output: SubprocessOutputCapture
    private let timeout: TimeInterval?
    private let startedAtUptime: TimeInterval
    private let cancellationToken: CancellationToken?
    private let commandDescription: String
    private let ownedGroupID: pid_t?
    private let hostGroupID: pid_t
    private let lock = NSLock()
    private var waited = false

    var processIdentifier: Int32? { process.processIdentifier }
    var processGroupIdentifier: Int32? { ownedGroupID }

    init(
        process: Process,
        output: SubprocessOutputCapture,
        timeout: TimeInterval?,
        startedAtUptime: TimeInterval,
        cancellationToken: CancellationToken?,
        commandDescription: String,
        ownedGroupID: pid_t?,
        hostGroupID: pid_t
    ) {
        self.process = process
        self.output = output
        self.timeout = timeout
        self.startedAtUptime = startedAtUptime
        self.cancellationToken = cancellationToken
        self.commandDescription = commandDescription
        self.ownedGroupID = ownedGroupID
        self.hostGroupID = hostGroupID
    }

    func wait() throws -> CommandResult {
        lock.lock()
        guard !waited else {
            lock.unlock()
            throw ExecutionError.launchFailed("running command was already awaited")
        }
        waited = true
        lock.unlock()

        let elapsedBeforeWait = max(
            0,
            ProcessInfo.processInfo.systemUptime - startedAtUptime
        )
        let deadline = timeout.map {
            ProcessInfo.processInfo.systemUptime + max(0, $0 - elapsedBeforeWait)
        }
        while process.isRunning {
            if cancellationToken?.isCancelled == true {
                stopOwnedGroup()
                output.finish(timeout: 2)
                throw ExecutionError.cancelled(command: commandDescription)
            }
            if let deadline, ProcessInfo.processInfo.systemUptime >= deadline {
                stopOwnedGroup()
                output.finish(timeout: 2)
                throw ExecutionError.timedOut(command: commandDescription)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        output.finish(timeout: 0.2)
        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: output.capturedStdout,
            stderr: output.capturedStderr
        )
    }

    private func stopOwnedGroup() {
        guard let groupID = ownedGroupID else { return }
        if cancellationToken?.isTerminationRequested == true {
            killOwnedGroup(groupID)
            return
        }
        guard groupIsSafeToSignal(groupID) else { return }
        _ = kill(-groupID, SIGINT)
        if waitForGroupExit(groupID, timeout: 0.5, stopForTerminationRequest: true) {
            return
        }
        if cancellationToken?.isTerminationRequested == true {
            killOwnedGroup(groupID)
            return
        }
        guard groupIsSafeToSignal(groupID) else { return }
        _ = kill(-groupID, SIGTERM)
        if waitForGroupExit(groupID, timeout: 1, stopForTerminationRequest: true) {
            return
        }
        killOwnedGroup(groupID)
    }

    private func groupIsSafeToSignal(_ groupID: pid_t) -> Bool {
        guard groupID > 1, groupID != hostGroupID, groupID != getpgrp() else { return false }
        if process.isRunning, getpgid(process.processIdentifier) != groupID {
            return false
        }
        return groupExists(groupID)
    }

    private func killOwnedGroup(_ groupID: pid_t) {
        guard groupIsSafeToSignal(groupID) else { return }
        _ = kill(-groupID, SIGKILL)
        _ = waitForGroupExit(groupID, timeout: 1, stopForTerminationRequest: false)
    }

    private func waitForGroupExit(
        _ groupID: pid_t,
        timeout: TimeInterval,
        stopForTerminationRequest: Bool = false
    ) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            _ = process.isRunning
            if !groupExists(groupID) { return true }
            if stopForTerminationRequest,
                cancellationToken?.isTerminationRequested == true
            {
                return false
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return !groupExists(groupID)
    }

    private func groupExists(_ groupID: pid_t) -> Bool {
        if kill(-groupID, 0) == 0 { return true }
        return errno == EPERM
    }
}
