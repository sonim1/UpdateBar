import ArgumentParser
import Foundation
import UpdateBarCore
#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct UpdateBar: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "updatebar",
        abstract: "Track and update arbitrary registered tools.",
        version: UpdateBarVersion.current,
        groupedSubcommands: [
            CommandGroup(name: "Setup", subcommands: [
                InitCommand.self,
                ScanCommand.self,
                AddCommand.self,
                ImportCommand.self,
                ExportCommand.self,
            ]),
            CommandGroup(name: "Check & Update", subcommands: [
                StatusCommand.self,
                CheckCommand.self,
                UpdateCommand.self,
                ListCommand.self,
            ]),
            CommandGroup(name: "Manage", subcommands: [
                ApprovalCommand.self,
                ApprovalsCommand.self,
                RevokeCommand.self,
                PinCommand.self,
                UnpinCommand.self,
                EnableCommand.self,
                DisableCommand.self,
                RemoveCommand.self,
                EditCommand.self,
            ]),
                CommandGroup(name: "System", subcommands: systemSubcommands),
            CommandGroup(name: "Support", subcommands: [
                GuideCommand.self,
                TUICommand.self,
                SchemaCommand.self,
                TemplateCommand.self,
                ValidateCommand.self,
            ]),
        ]
    )

    private static let systemSubcommands: [ParsableCommand.Type] = {
#if os(macOS)
        return [ConfigCommand.self, BackgroundCommand.self]
#else
        return [ConfigCommand.self]
#endif
    }()
}

@main
enum UpdateBarMain {
    static func main() {
        let arguments = Self.normalizeArguments(Array(CommandLine.arguments.dropFirst()))
        do {
            var command = try UpdateBar.parseAsRoot(arguments)
            try command.run()
        } catch {
            if error is ExitCode {
                let exitCode = UpdateBar.exitCode(for: error)
                terminate(processExitCode(for: exitCode))
            }
            let exitCode = UpdateBar.exitCode(for: error)
            if exitCode == .success {
                let message = sanitizedErrorMessage(for: error)
                if !message.isEmpty {
                    writeStdout(message)
                }
                terminate(0)
            }
            if requestedJSONOutput(arguments),
                !JSONOutputTracker.shared.didWrite
            {
                writeJSONError(error, code: exitCode)
                terminate(processExitCode(for: exitCode))
            }
            let message = sanitizedErrorMessage(for: error)
            if !message.isEmpty {
                writeStderr(message)
            }
            terminate(processExitCode(for: exitCode))
        }
    }

    private static func normalizeArguments(_ arguments: [String]) -> [String] {
        var normalized: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            let next: String? = index + 1 < arguments.count
                ? arguments[index + 1]
                : nil

            if let next,
               let normalizedPair = normalizeBooleanFlagValuePair(flag: argument, value: next)
            {
                normalized.append(contentsOf: normalizedPair)
                index += 2
                continue
            }

            if let action = normalizeBooleanAssignmentArgument(argument) {
                switch action {
                case .keep(let value):
                    normalized.append(value)
                case .drop:
                    break
                }
                index += 1
                continue
            }

            normalized.append(argument)
            index += 1
        }

        return normalized
    }

    private static func normalizeBooleanFlagValuePair(flag: String, value: String) -> [String]? {
        guard isBooleanFlag(flag),
              let boolValue = parseBooleanValue(value)
        else {
            return nil
        }

        return boolValue ? [flag] : []
    }

    private static func normalizeBooleanAssignmentArgument(_ argument: String) -> NormalizedArgument? {
        guard argument.hasPrefix("--"), let equalsRange = argument.firstIndex(of: "=") else {
            return nil
        }

        let key = String(argument[..<equalsRange])
        let value = String(argument[argument.index(after: equalsRange)...]).lowercased()

        switch key {
        case "--json", "--json-stream":
            if trueBooleanValues.contains(value) {
                return .keep(key)
            }
            if falseBooleanValues.contains(value) {
                return .drop
            }
            return .keep(argument)
        default:
            return .keep(argument)
        }
    }

    private enum NormalizedArgument {
        case keep(String)
        case drop
    }

    private static func isBooleanFlag(_ argument: String) -> Bool {
        jsonBooleanFlags.contains(argument)
    }

    private static func parseBooleanValue(_ value: String) -> Bool? {
        let normalized = value.lowercased()
        if trueBooleanValues.contains(normalized) {
            return true
        }
        if falseBooleanValues.contains(normalized) {
            return false
        }
        return nil
    }

    private static let jsonBooleanFlags: Set<String> = [
        "--json",
        "--json-stream"
    ]

    private static let trueBooleanValues: Set<String> = [
        "1",
        "true",
        "t",
        "yes",
        "on"
    ]

    private static let falseBooleanValues: Set<String> = [
        "0",
        "false",
        "f",
        "no",
        "off"
    ]

    private static func requestedJSONOutput(_ arguments: [String]) -> Bool {
        arguments.contains("--json") || arguments.contains("--json-stream")
            || arguments.contains(where: { $0.hasPrefix("--json=") || $0.hasPrefix("--json-stream=") })
    }

    private static func writeJSONError(_ error: Error, code exitCode: ExitCode) {
        let message = sanitizedErrorMessage(for: error)
        let payload = ErrorEnvelope(
            ok: false,
            code: errorCode(for: error, exitCode: exitCode),
            errors: [message]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(payload) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static func errorCode(for error: Error, exitCode: ExitCode) -> String {
        if exitCode == .validationFailure {
            return "usage_error"
        }
        if error is ValidationError {
            return "usage_error"
        }
        if error is ConfigError {
            return "config_error"
        }
        if error is RegistryError {
            return "registry_error"
        }
        if error is DecodingError {
            return "decode_error"
        }
        return "runtime_error"
    }

    private static func processExitCode(for exitCode: ExitCode) -> Int32 {
        exitCode == .validationFailure ? 1 : exitCode.rawValue
    }

    private static func terminate(_ code: Int32) -> Never {
#if os(Linux)
        Glibc.exit(code)
#else
        Darwin.exit(code)
#endif
    }
}
