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
        throw ValidationError("Could not locate updatebar-tui on PATH.")
    }

    private func makeTUIEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["UPDATEBAR_BIN"] = resolveCurrentUpdateBarBinary()
        return environment
    }

    private func resolveCurrentUpdateBarBinary() -> String {
        let fallback = explicitExecutablePath(CommandLine.arguments.first) ?? "updatebar"
        return environmentValueOrDefault(
            ProcessInfo.processInfo.environment["UPDATEBAR_BIN"],
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
