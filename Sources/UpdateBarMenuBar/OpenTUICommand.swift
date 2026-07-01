import Foundation

public struct OpenTUICommand: Equatable, Sendable {
    public var executablePath: String
    public var arguments: [String]

    public init(
        cliPath: String,
        tuiCommand: String = "updatebar-tui",
        updateBarHome: String? = ProcessInfo.processInfo.environment["UPDATEBAR_HOME"]
    ) {
        let exports = [
            "export UPDATEBAR_BIN=\(Self.shellQuote(cliPath))",
            updateBarHome.map { "export UPDATEBAR_HOME=\(Self.shellQuote($0))" },
        ].compactMap { $0 }
        let quotedCommand = Self.shellQuote(tuiCommand)
        let fallbackPrompt = "\(tuiCommand) not found on PATH"
        let fallbackHowToMessage = "Run 'updatebar tui' from this shell to set UPDATEBAR_BIN automatically."
        let launch = [
            "if [ -x \"$UPDATEBAR_BIN\" ]",
            "then exec \"$UPDATEBAR_BIN\" tui",
            "elif command -v \(quotedCommand) >/dev/null 2>&1",
            "then exec \(quotedCommand)",
            "else printf '%s\\n' \(Self.shellQuote(fallbackPrompt))",
            "printf '%s\\n' \(Self.shellQuote("Build the TUI in the UpdateBar tui directory, then run npm link."))",
            "printf '%s\\n' \(Self.shellQuote(fallbackHowToMessage))",
            "fi",
        ]
        let script = (exports + launch).joined(separator: "; ")
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
