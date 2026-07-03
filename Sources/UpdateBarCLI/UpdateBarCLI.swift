import ArgumentParser

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

private extension UpdateBar {
    static var topLevelHelpTargets: Set<String> {
        Set(configuration.subcommands.flatMap { subcommand in
            [subcommand._commandName] + subcommand.configuration.aliases
        }).union(["help"])
    }

    static func validateHelpCommandPath(_ arguments: [String]) throws {
        guard arguments.first == "help", arguments.count > 1 else {
            return
        }

        var command: ParsableCommand.Type = Self.self
        var path: [String] = []
        for target in arguments.dropFirst() {
            guard !target.hasPrefix("-") else {
                return
            }
            guard let next = command.configuration.subcommands.first(where: { subcommand in
                subcommand._commandName == target || subcommand.configuration.aliases.contains(target)
            }) else {
                let parent = path.isEmpty ? "updatebar" : "updatebar help \(path.joined(separator: " "))"
                throw ValidationError("""
                Unexpected help target '\(target)' after \(parent)
                Usage: updatebar help <subcommand>
                  See 'updatebar --help' for more information.
                """)
            }
            path.append(target)
            command = next
        }
    }

    static func validateTrailingInlineHelpArguments(_ arguments: [String]) throws {
        try validateTrailingInlineArguments(
            arguments,
            matching: isInlineHelpFlag,
            flagSynopsis: "--help",
            skipHelpCommand: true
        ) { command, trailing in
            command == "updatebar --help" && !trailing.hasPrefix("-")
            ? """
            Unexpected argument '\(trailing)' after \(command)
            Usage: updatebar --help
              Use 'updatebar help \(trailing)' for subcommand help.
            """
            : """
            Unexpected argument '\(trailing)' after \(command)
            Usage: \(command)
            """
        }
    }

    static func validateTrailingInlineVersionArguments(_ arguments: [String]) throws {
        try validateTrailingInlineArguments(
            arguments,
            matching: isInlineVersionFlag,
            flagSynopsis: "--version",
            skipHelpCommand: false
        ) { command, trailing in
            """
            Unexpected argument '\(trailing)' after \(command)
            Usage: \(command)
            """
        }
    }

    private static func validateTrailingInlineArguments(
        _ arguments: [String],
        matching isFlag: (String) -> Bool,
        flagSynopsis: String,
        skipHelpCommand: Bool,
        message: (String, String) -> String
    ) throws {
        guard (!skipHelpCommand || arguments.first != "help"),
              let flagIndex = arguments.firstIndex(where: isFlag)
        else {
            return
        }

        let afterFlagIndex = arguments.index(after: flagIndex)
        guard afterFlagIndex < arguments.endIndex,
              let trailing = arguments[afterFlagIndex...].first
        else {
            return
        }

        let command = inlineCommand(argumentsBeforeFlag: arguments[..<flagIndex], flagSynopsis: flagSynopsis)
        throw ValidationError(message(command, trailing))
    }

    private static func inlineCommand(argumentsBeforeFlag: ArraySlice<String>, flagSynopsis: String) -> String {
        var command: ParsableCommand.Type = Self.self
        var path: [String] = []
        for target in argumentsBeforeFlag {
            guard !target.hasPrefix("-"),
                  let next = command.configuration.subcommands.first(where: { subcommand in
                      subcommand._commandName == target || subcommand.configuration.aliases.contains(target)
                  })
            else {
                break
            }
            path.append(target)
            command = next
        }
        return path.isEmpty ? "updatebar \(flagSynopsis)" : "updatebar \(path.joined(separator: " ")) \(flagSynopsis)"
    }

    private static func isInlineHelpFlag(_ argument: String) -> Bool {
        argument == "--help" || argument == "-h"
    }

    private static func isInlineVersionFlag(_ argument: String) -> Bool {
        argument == "--version"
    }
}

@main
enum UpdateBarMain {
    static func main() {
        let arguments = normalizeCLIArguments(Array(CommandLine.arguments.dropFirst()))
        do {
            try validateHelpTarget(arguments, knownTopLevelHelpTargets: UpdateBar.topLevelHelpTargets)
            try UpdateBar.validateHelpCommandPath(arguments)
            try UpdateBar.validateTrailingInlineHelpArguments(arguments)
            try UpdateBar.validateTrailingInlineVersionArguments(arguments)
            var command = try UpdateBar.parseAsRoot(arguments)
            try command.run()
        } catch {
            handleCLIError(error, arguments: arguments)
        }
    }
}
