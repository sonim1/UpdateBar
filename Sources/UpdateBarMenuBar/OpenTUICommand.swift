import Foundation

public struct OpenTUICommand: Equatable, Sendable {
    public var executablePath: String
    public var arguments: [String]

    public init(
        cliPath: String,
        tuiCommand: String = "updatebar-tui",
        updateBarHome: String? = ProcessInfo.processInfo.environment["UPDATEBAR_HOME"],
        tuiCommandOverride: String? = ProcessInfo.processInfo.environment["UPDATEBAR_TUI"]
    ) {
        let exports = [
            "export UPDATEBAR_BIN=\(Self.shellQuote(cliPath))",
            updateBarHome.map { "export UPDATEBAR_HOME=\(Self.shellQuote($0))" },
            tuiCommandOverride.map { "export UPDATEBAR_TUI=\(Self.shellQuote($0))" },
        ].compactMap { $0 }

        let quotedCommand = Self.shellQuote(tuiCommand)
        let fallbackPrompt = Self.shellQuote("\(tuiCommand) is not available")
        let fallbackSetup = Self.shellQuote("Build the TUI in the UpdateBar tui directory, then run npm link.")
        let fallbackHowToMessage = Self.shellQuote(
            "Run 'updatebar tui' to start the terminal UI (or set UPDATEBAR_TUI to a runnable binary)."
        )
        let invalidTUIMessage = Self.shellQuote("UPDATEBAR_TUI is set but not executable:")

        let launch = [
            "if [ -n \"$UPDATEBAR_TUI\" ] && [ -x \"$UPDATEBAR_TUI\" ]",
            "then exec \"$UPDATEBAR_TUI\"",
            "elif [ -n \"$UPDATEBAR_TUI\" ]",
            "then printf '%s\\n' \(invalidTUIMessage)",
            "printf '%s\\n' \"$UPDATEBAR_TUI\"",
            "exit 1",
            "elif [ -x \"$UPDATEBAR_BIN\" ]",
            "then exec \"$UPDATEBAR_BIN\" tui",
            "elif command -v \(quotedCommand) >/dev/null 2>&1",
            "then exec \(quotedCommand)",
            "else printf '%s\\n' \(fallbackPrompt)",
            "printf '%s\\n' \(fallbackSetup)",
            "printf '%s\\n' \(fallbackHowToMessage)",
            "exit 1",
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
