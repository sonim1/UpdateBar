import ArgumentParser
import UpdateBarCore

extension UpdateBar {
    static var topLevelHelpTargets: Set<String> {
        Set(configuration.subcommands.flatMap { subcommand in
            [subcommand._commandName] + subcommand.configuration.aliases
        }).union(["help"])
    }

    static func validatePreflightArguments(_ arguments: [String]) throws {
        try validateRemovedListCommand(arguments)
        try validateHelpTarget(arguments, knownTopLevelHelpTargets: topLevelHelpTargets)
        try validateTopLevelTarget(arguments, knownTopLevelTargets: topLevelHelpTargets, when: isInlineVersionFlag)
        try validateTopLevelTarget(arguments, knownTopLevelTargets: topLevelHelpTargets, when: isMachineOutputFlag)
        try validateHelpCommandPath(arguments)
        try validateTrailingInlineHelpArguments(arguments)
        try validateTrailingInlineVersionArguments(arguments)
        try validateApproveRequiresField(arguments)
    }

    private static func validateRemovedListCommand(_ arguments: [String]) throws {
        guard arguments.first == "list" else { return }
        throw ValidationError("""
        updatebar list was removed.
        Run updatebar status to list registered item ids.
        """)
    }

    private static func validateTopLevelTarget(
        _ arguments: [String],
        knownTopLevelTargets: Set<String>,
        when isFlag: (String) -> Bool
    ) throws {
        guard arguments.contains(where: isFlag),
              let first = arguments.first,
              !isFlag(first),
              !first.hasPrefix("-")
        else {
            return
        }

        guard knownTopLevelTargets.contains(first) else {
            throw ValidationError("""
            Unexpected argument '\(first)'
            Usage: updatebar <subcommand>
              See 'updatebar --help' for more information.
            """)
        }
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

    private static func isMachineOutputFlag(_ argument: String) -> Bool {
        argument == "--json" || argument == "--json-stream"
    }

    private static func validateApproveRequiresField(_ arguments: [String]) throws {
        guard arguments.first == "approve",
              !arguments.contains(where: isInlineHelpFlag),
              !arguments.contains(where: { $0 == "--field" || $0.hasPrefix("--field=") })
        else {
            return
        }

        guard let id = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) else {
            return
        }
        throw ValidationError(
            "approve requires --field. Run updatebar approvals \(SecretRedactor.redact(id)) to review command fields."
        )
    }
}
