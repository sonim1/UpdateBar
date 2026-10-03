import Foundation
import UpdateBarCore

/// Thread-safe because UpdateRunner executes recipes on a worker pool; several
/// threads call `run` concurrently.
public final class MockCommandExecutor: CommandLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResults: [String: CommandResult]
    private var recorded: [ShellCommand] = []
    private var delays: [String: TimeInterval] = [:]

    public init(results: [String: CommandResult]) {
        self.storedResults = results
    }

    public var results: [String: CommandResult] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedResults
        }
        set {
            lock.lock()
            storedResults = newValue
            lock.unlock()
        }
    }

    /// Commands in the order they were observed. Under parallel execution the
    /// order across different recipes is not deterministic; prefer
    /// `recordedCommandTexts` when asserting on a multi-item run.
    public var commands: [ShellCommand] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// Sorted command texts, safe to assert on regardless of scheduling order.
    public var recordedCommandTexts: [String] {
        commands.map(\.command).sorted()
    }

    /// Makes a command block for `seconds` so tests can observe overlap.
    public func setDelay(_ seconds: TimeInterval, forCommand command: String) {
        lock.lock()
        delays[command] = seconds
        lock.unlock()
    }

    public func prepare(_ command: ShellCommand, policy: ExecutionPolicy) throws
        -> any PreparedCommand
    {
        MockPreparedCommand(executor: self, command: command)
    }

    fileprivate func start(_ command: ShellCommand) throws -> any RunningCommand {
        lock.lock()
        recorded.append(command)
        let result = storedResults[command.command]
        let delay = delays[command.command]
        lock.unlock()

        guard let result else {
            throw MockError.missingCommand(command.command)
        }
        return MockRunningCommand(result: result, delay: delay)
    }

    public enum MockError: Error {
        case missingCommand(String)
    }
}

private struct MockPreparedCommand: PreparedCommand {
    let executor: MockCommandExecutor
    let command: ShellCommand

    func start() throws -> any RunningCommand {
        try executor.start(command)
    }
}

private struct MockRunningCommand: RunningCommand {
    let result: CommandResult
    let delay: TimeInterval?

    func wait() throws -> CommandResult {
        if let delay {
            Thread.sleep(forTimeInterval: delay)
        }
        return result
    }
}
