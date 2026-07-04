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
        try validateRemovedVersionCommand(arguments)
        try validateRemovedAddOptions(arguments)
        try validateRemovedUpdateOptions(arguments)
        try validateRemovedScanOptions(arguments)
        try validateIntrinsicJSONFlags(arguments)
        try validateUnsupportedJSONStreamFlags(arguments)
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

    private static func validateRemovedVersionCommand(_ arguments: [String]) throws {
        guard arguments.first == "version" else { return }
        throw ValidationError("""
        updatebar version was removed.
        Run updatebar --version.
        """)
    }

    private static func validateRemovedAddOptions(_ arguments: [String]) throws {
        guard arguments.first == "add" else { return }
        if hasOption("--ai", in: arguments) {
            throw ValidationError("""
            add --ai was removed.
            Run updatebar template recipe to draft recipe JSON, or use an external agent, then run updatebar add --from <file>.
            """)
        }
        if hasOption("--provider", in: arguments) {
            throw ValidationError("""
            add --provider was removed.
            Recipe authoring belongs to external agents. Save generated recipe JSON, then run updatebar add --from <file>.
            """)
        }
        if hasOption("--manual", in: arguments) {
            throw ValidationError("""
            add --manual was removed.
            Run updatebar add without --from to use the manual wizard, or run updatebar add --from <file>.
            """)
        }
        if hasOption("--trust", in: arguments) {
            throw ValidationError("""
            add --trust was removed.
            New recipes are saved untrusted. Run updatebar approvals <id> to review command fields.
            """)
        }
    }

    private static func validateRemovedUpdateOptions(_ arguments: [String]) throws {
        guard arguments.first == "update" else { return }
        if hasOption("--all", in: arguments) {
            throw ValidationError("""
            update --all was removed.
            Run updatebar update without ids to update every approved outdated item.
            """)
        }
    }

    private static func validateRemovedScanOptions(_ arguments: [String]) throws {
        guard let command = arguments.first,
              command == "scan" || command == "init",
              hasOption("--detectors", in: arguments)
        else {
            return
        }
        throw ValidationError("""
        \(command) --detectors was removed.
        Run updatebar \(command) --category <category> to filter results. Default scan sources are selected automatically.
        """)
    }

    private static func validateIntrinsicJSONFlags(_ arguments: [String]) throws {
        guard let command = intrinsicJSONCommand(in: arguments) else { return }
        if hasOption("--json-stream", in: arguments) {
            throw ValidationError("""
            \(command) does not support JSONL streaming.
            Run updatebar \(command) without --json-stream.
            Usage: updatebar \(command)
            """)
        }
        if hasOption("--json", in: arguments) {
            throw ValidationError("""
            \(command) already prints JSON.
            Run updatebar \(command) without --json.
            Usage: updatebar \(command)
            """)
        }
    }

    private static func intrinsicJSONCommand(in arguments: [String]) -> String? {
        if arguments.first == "schema" {
            return "schema"
        }
        guard arguments.first == "template",
              let subcommand = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }),
              subcommand == "recipe" || subcommand == "manifest"
        else {
            return nil
        }
        return "template \(subcommand)"
    }

    private static func validateUnsupportedJSONStreamFlags(_ arguments: [String]) throws {
        guard let command = arguments.first,
              ["init", "scan", "status"].contains(command),
              hasOption("--json-stream", in: arguments)
        else {
            return
        }
        throw ValidationError(unsupportedJSONStreamMessage(for: command))
    }

    private static func unsupportedJSONStreamMessage(for command: String) -> String {
        if command == "init" {
            return """
            init does not support JSONL streaming.
            Run updatebar init --select all --json for headless setup, or updatebar scan --json to preview candidates.
            """
        }
        return """
        \(command) does not support JSONL streaming.
        Run updatebar \(command) --json for a snapshot, or updatebar check --json-stream to stream refresh progress.
        """
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

    private static func hasOption(_ option: String, in arguments: [String]) -> Bool {
        arguments.contains { argument in
            argument == option || argument.hasPrefix("\(option)=")
        }
    }

    private static func validateApproveRequiresField(_ arguments: [String]) throws {
        guard arguments.first == "approve",
              !arguments.contains(where: isInlineHelpFlag),
              !hasOption("--field", in: arguments)
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
