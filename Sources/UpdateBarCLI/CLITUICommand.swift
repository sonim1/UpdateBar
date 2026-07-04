import ArgumentParser
import Foundation

struct TUICommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tui",
        abstract: "Launch the Ink terminal UI if installed.",
        shouldDisplay: false
    )

    func run() throws {
        let process = Process()
        let executable = try resolveTUICommand()
        process.executableURL = URL(fileURLWithPath: executable)
        process.environment = makeTUIEnvironment()
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()

        let exitCode = Int32(process.terminationStatus)
        if exitCode != 0 {
            throw ExitCode(exitCode)
        }
    }

    private func resolveTUICommand() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["UPDATEBAR_TUI"], !override.isEmpty {
            if explicitExecutablePath(override) != nil {
                return override
            }
            throw ValidationError("UPDATEBAR_TUI is not executable: \(override)")
        }
        if let resolved = commandFromPath(name: "updatebar-tui", environment: environment) {
            return resolved
        }
        throw ValidationError(
            "Could not locate updatebar-tui on PATH. Build it with `npm --prefix tui install && npm --prefix tui run build`, then run `UPDATEBAR_TUI=$PWD/tui/dist/index.js updatebar tui`, or add updatebar-tui to PATH."
        )
    }

    private func makeTUIEnvironment() -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        let allowedKeys = [
            "PATH",
            "HOME",
            "LANG",
            "LC_ALL",
            "LC_CTYPE",
            "TMPDIR",
            "USER",
            "TERM",
            "COLORTERM",
            "NO_COLOR",
            "FORCE_COLOR",
            "UPDATEBAR_HOME",
        ]
        var environment: [String: String] = [:]
        for key in allowedKeys {
            if let value = source[key], !value.isEmpty {
                environment[key] = value
            }
        }
        environment["UPDATEBAR_BIN"] = resolveCurrentUpdateBarBinary(environment: source)
        return environment
    }

    private func resolveCurrentUpdateBarBinary(environment: [String: String]) -> String {
        let fallback = explicitExecutablePath(CommandLine.arguments.first) ?? "updatebar"
        return environmentValueOrDefault(
            environment["UPDATEBAR_BIN"],
            fallback
        )
    }

    private func environmentValueOrDefault(_ value: String?, _ fallback: String) -> String {
        guard let value, !value.isEmpty else {
            return fallback
        }
        return value
    }

    private func explicitExecutablePath(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        guard FileManager.default.isExecutableFile(atPath: value) else {
            return nil
        }
        return value
    }

    private func commandFromPath(name: String, environment: [String: String]) -> String? {
        return resolveExecutable(name, environment: environment)
    }
}
