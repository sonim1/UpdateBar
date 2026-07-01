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
        let script = (exports + [Self.shellQuote(tuiCommand)]).joined(separator: "; ")
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
