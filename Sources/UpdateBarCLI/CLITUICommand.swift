import ArgumentParser
import Foundation
import UpdateBarCore

struct TUICommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tui",
        abstract: "Launch the Ink terminal UI if installed.",
        shouldDisplay: false
    )

    func run() throws {
        let executable = try resolveTUICommand()
        let environment = makeTUIEnvironment()

        // Replace this process instead of spawning a child: Foundation's
        // Process puts the child in a new process group, so the TUI's
        // tcsetattr(raw mode) is a background call the kernel ignores and
        // arrow keys echo instead of navigating.
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(executable), nil]
        var envp: [UnsafeMutablePointer<CChar>?] =
            environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        execve(executable, &argv, &envp)

        let message = String(cString: strerror(errno))
        for pointer in argv { free(pointer) }
        for pointer in envp { free(pointer) }
        throw ValidationError("failed to launch \(executable): \(message)")
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
            """
            updatebar-tui is not installed.
            Install it with: brew install sonim1/tap/updatebar-tui
            (Developing from source? Run `npm --prefix tui install && npm --prefix tui run build`, then set UPDATEBAR_TUI=tui/dist/index.js.)
            """
        )
    }

    private func makeTUIEnvironment() -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        var environment = SubprocessEnvironment.presentation(from: source)
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
