import ArgumentParser

extension UpdateBar {
    static var topLevelHelpTargets: Set<String> {
        Set(configuration.subcommands.flatMap { subcommand in
            [subcommand._commandName] + subcommand.configuration.aliases
        }).union(["help"])
    }

    static func validatePreflightArguments(_ arguments: [String]) throws {
        try validateHelpTarget(arguments, knownTopLevelHelpTargets: topLevelHelpTargets)
        try validateHelpCommandPath(arguments)
        try validateTrailingInlineHelpArguments(arguments)
        try validateTrailingInlineVersionArguments(arguments)
    }

    private static func validateHelpCommandPath(_ arguments: [String]) throws {
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

    private static func validateTrailingInlineHelpArguments(_ arguments: [String]) throws {
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

    private static func validateTrailingInlineVersionArguments(_ arguments: [String]) throws {
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
