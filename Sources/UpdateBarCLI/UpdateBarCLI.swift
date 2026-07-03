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
        guard arguments.first != "help",
              let helpIndex = arguments.firstIndex(where: isInlineHelpFlag)
        else {
            return
        }

        let afterHelpIndex = arguments.index(after: helpIndex)
        guard afterHelpIndex < arguments.endIndex,
              let trailing = arguments[afterHelpIndex...].first(where: { !$0.hasPrefix("-") })
        else {
            return
        }

        let helpCommand = inlineHelpCommand(argumentsBeforeHelp: arguments[..<helpIndex])
        let message = helpCommand == "updatebar --help"
            ? """
            Unexpected argument '\(trailing)' after \(helpCommand)
            Usage: updatebar --help
              Use 'updatebar help \(trailing)' for subcommand help.
            """
            : """
            Unexpected argument '\(trailing)' after \(helpCommand)
            Usage: \(helpCommand)
            """
        throw ValidationError(message)
    }

    private static func inlineHelpCommand(argumentsBeforeHelp: ArraySlice<String>) -> String {
        var command: ParsableCommand.Type = Self.self
        var path: [String] = []
        for target in argumentsBeforeHelp {
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
        return path.isEmpty ? "updatebar --help" : "updatebar \(path.joined(separator: " ")) --help"
    }

    private static func isInlineHelpFlag(_ argument: String) -> Bool {
        argument == "--help" || argument == "-h"
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
            var command = try UpdateBar.parseAsRoot(arguments)
            try command.run()
        } catch {
            handleCLIError(error, arguments: arguments)
        }
    }
}
