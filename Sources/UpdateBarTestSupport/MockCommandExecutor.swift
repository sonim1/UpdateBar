import Foundation
import UpdateBarCore

public final class MockCommandExecutor: CommandRunning {
    public var results: [String: CommandResult]
    public private(set) var commands: [ShellCommand] = []

    public init(results: [String: CommandResult]) {
        self.results = results
    }

    public func run(_ command: ShellCommand, policy: ExecutionPolicy) throws -> CommandResult {
        commands.append(command)
        guard let result = results[command.command] else {
            throw MockError.missingCommand(command.command)
        }
        return result
    }

    enum MockError: Error {
        case missingCommand(String)
    }
}
