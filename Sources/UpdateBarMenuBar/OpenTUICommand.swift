import Foundation

public struct OpenTUICommand: Equatable, Sendable {
    public var executablePath: String
    public var arguments: [String]

    public init(cliPath: String) {
        // TUI discovery, UPDATEBAR_TUI overrides, and install guidance all live
        // in the CLI's `tui` subcommand so the Terminal window only ever shows
        // one short command.
        let script = "exec \(Self.shellQuote(cliPath)) tui"
        executablePath = "/usr/bin/osascript"
        arguments = [
            "-e",
            "tell application \"Terminal\" to do script \(Self.appleScriptQuote(script))",
            "-e",
            "tell application \"Terminal\" to activate",
        ]
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptQuote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
