import Foundation

public struct ShellCommand: Equatable, Sendable {
    public var command: String
    public var cwd: String?

    public init(command: String, cwd: String?) {
        self.command = command
        self.cwd = cwd
    }
}
