import ArgumentParser
import Foundation
import UpdateBarCore

struct PinCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pin",
        abstract: "Pin an item to a version.",
        shouldDisplay: false
    )

    @Argument(help: "Item id to pin.")
    var id: String

    @Argument(help: "Version to pin; omit to use the current stored version.")
    var version: String?

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    func run() throws {
        let recipe = try RegistryService().pin(id: id, version: version)
        if json {
            try printJSON(redactedItemMutationPayload(for: recipe))
        } else {
            writeStdout("pinned \(SecretRedactor.redact(recipe.id)) \(recipe.pin ?? "")")
        }
    }
}

struct UnpinCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unpin",
        abstract: "Clear an item's pinned version.",
        shouldDisplay: false
    )

    @Argument(help: "Item id to unpin.")
    var id: String

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    func run() throws {
        let recipe = try RegistryService().unpin(id: id)
        if json {
            try printJSON(redactedItemMutationPayload(for: recipe))
        } else {
            writeStdout("unpinned \(SecretRedactor.redact(recipe.id))")
            if let retry = batchUpdateYesCommand(for: [recipe.id]) {
                printNextCommands([retry])
            }
        }
    }
}

struct EnableCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable",
        abstract: "Enable an item.",
        shouldDisplay: false
    )

    @Argument(help: "Item id to enable.")
    var id: String

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    func run() throws {
        let recipe = try RegistryService().setEnabled(id: id, enabled: true)
        if json {
            try printJSON(redactedItemMutationPayload(for: recipe))
        } else {
            writeStdout("enabled \(SecretRedactor.redact(recipe.id))")
            if let retry = batchUpdateYesCommand(for: [recipe.id]) {
                printNextCommands([retry])
            }
        }
    }
}

struct DisableCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable",
        abstract: "Disable an item.",
        shouldDisplay: false
    )

    @Argument(help: "Item id to disable.")
    var id: String

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    func run() throws {
        let recipe = try RegistryService().setEnabled(id: id, enabled: false)
        if json {
            try printJSON(redactedItemMutationPayload(for: recipe))
        } else {
            writeStdout("disabled \(SecretRedactor.redact(recipe.id))")
        }
    }
}

struct RemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove an item from the registry.",
        shouldDisplay: false
    )

    @Argument(help: "Item id to remove.")
    var id: String

    @Flag(name: .long, help: "Remove without prompting; required with --json to remove.")
    var yes = false

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    func run() throws {
        let service = RegistryService()
        if !yes {
            _ = try service.recipe(id: id)
            try requireYes(
                prompt: "Remove \(id)? Type yes to continue:",
                cancelMessage: "remove cancelled",
                interactive: !json
            )
        }
        try service.remove(id: id)
        if json {
            try printJSON(RemovePayload(ok: true, id: SecretRedactor.redact(id), removed: true))
        } else {
            writeStdout("removed \(SecretRedactor.redact(id))")
        }
    }
}

struct ApprovalCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "approve",
        abstract: "Approve one command field for an item.",
        shouldDisplay: false
    )

    @Argument(help: "Item id to approve.")
    var id: String

    @Option(name: .long, help: "Command field to approve, such as update.cmd.")
    var field: String

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    func run() throws {
        let recipe = try RegistryService().approve(id: id, field: field)
        if json {
            try printJSON(redactedApprovalMutationPayload(for: recipe, field: field))
        } else {
            writeStdout("approved \(SecretRedactor.redact(recipe.id)) \(field)")
            printApprovalNextStep(for: recipe)
        }
    }

    private func printApprovalNextStep(for recipe: Recipe) {
        if recipe.commandFingerprints().keys.allSatisfy({
            TrustPolicy.isApproved(recipe, field: $0)
        }) {
            printNextCommands([checkCommand(for: recipe.id)])
        } else {
            printNextCommands([approvalCommand(for: recipe.id)])
        }
    }
}

struct ApprovalsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "approvals",
        abstract: "Review command fields for approval."
    )

    @Argument(help: "Item id to inspect.")
    var id: String

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    func run() throws {
        let rows = try RegistryService().approvals(id: id)
        if json {
            try printJSON(rows.map(redactedRow))
        } else {
            writeStdout("FIELD\tSTATUS\tCOMMAND\tDETAIL")
            for row in rows {
                writeStdout(humanRow(row))
            }
            let unapprovedRows = rows.filter { !$0.approved }
            if !unapprovedRows.isEmpty {
                printNextCommands(
                    unapprovedRows.map {
                        approveFieldCommand(for: id, field: $0.field)
                    })
            } else {
                writeStdout("")
                writeStdout("All command fields approved.")
                printNextCommands([checkCommand(for: id)])
            }
        }
    }

    private func redactedRow(_ row: ApprovalStatus) -> ApprovalStatus {
        ApprovalStatus(
            field: row.field,
            approved: row.approved,
            fingerprint: row.fingerprint,
            command: SecretRedactor.redact(row.command),
            cwd: row.cwd.map(SecretRedactor.redact)
        )
    }

    private func humanRow(_ row: ApprovalStatus) -> String {
        let row = redactedRow(row)
        var parts = [
            row.field,
            row.approved ? "approved" : "unapproved",
            oneLine(row.command),
        ]
        if let cwd = row.cwd, !cwd.isEmpty {
            parts.append("cwd=\(oneLine(cwd))")
        } else {
            parts.append("")
        }
        return parts.joined(separator: "\t")
    }

    private func oneLine(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

struct RevokeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "revoke",
        abstract: "Revoke approval for one command field.",
        shouldDisplay: false
    )

    @Argument(help: "Item id to revoke approval from.")
    var id: String

    @Option(name: .long, help: "Command field to revoke, such as update.cmd.")
    var field: String

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    func run() throws {
        let recipe = try RegistryService().revokeApproval(id: id, field: field)
        if json {
            try printJSON(redactedApprovalMutationPayload(for: recipe, field: field))
        } else {
            writeStdout("revoked \(SecretRedactor.redact(recipe.id)) \(field)")
            printNextCommands([approvalCommand(for: recipe.id)])
        }
    }
}
