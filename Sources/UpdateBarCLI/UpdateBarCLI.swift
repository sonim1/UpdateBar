import ArgumentParser

struct UpdateBar: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "updatebar",
        abstract: "Track and update arbitrary registered tools.",
        version: UpdateBarVersion.current,
        groupedSubcommands: [
            CommandGroup(
                name: "Setup",
                subcommands: [
                    InitCommand.self,
                    ScanCommand.self,
                    AddCommand.self,
                    ImportCommand.self,
                    ExportCommand.self,
                ]),
            CommandGroup(
                name: "Check & Update",
                subcommands: [
                    StatusCommand.self,
                    CheckCommand.self,
                    UpdateCommand.self,
                ]),
            CommandGroup(
                name: "Manage",
                subcommands: [
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
            CommandGroup(
                name: "Support",
                subcommands: [
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
        let arguments = normalizeCLIArguments(Array(CommandLine.arguments.dropFirst()))
        do {
            try UpdateBar.validatePreflightArguments(arguments)
            var command = try UpdateBar.parseAsRoot(arguments)
            try command.run()
        } catch {
            handleCLIError(error, arguments: arguments)
        }
    }
}
