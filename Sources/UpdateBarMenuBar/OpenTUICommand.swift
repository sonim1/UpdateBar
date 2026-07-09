import Foundation

public struct OpenTUICommand: Equatable, Sendable {
    /// Contents of the `.command` launcher script the app writes to disk.
    /// TUI discovery, UPDATEBAR_TUI overrides, and install guidance all live
    /// in the CLI's `tui` subcommand so the terminal only ever shows one
    /// short command.
    public var commandFileContents: String
    public var executablePath: String
    public var arguments: [String]

    public init(cliPath: String, commandFileURL: URL, terminal: TUITerminal) {
        commandFileContents = """
            #!/bin/sh
            exec \(Self.shellQuote(cliPath)) tui
            """
        executablePath = "/usr/bin/open"
        switch terminal.launchStyle {
        case .openDocument:
            arguments = ["-b", terminal.id, commandFileURL.path]
        case .openWithArgs(let flags):
            arguments = ["-nb", terminal.id, "--args"] + flags + [commandFileURL.path]
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
