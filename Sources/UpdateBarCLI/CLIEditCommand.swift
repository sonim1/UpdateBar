import ArgumentParser
import Foundation
import UpdateBarCore

struct EditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit one registered recipe in $VISUAL or $EDITOR.",
        shouldDisplay: false
    )

    @Argument(help: "Item id to edit.")
    var id: String

    @Option(
        name: .long,
        help: "Edit check.cmd, latest.cmd, or update.cmd.",
        completion: .list(["check.cmd", "latest.cmd", "update.cmd"])
    )
    var field: String?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Read field command text from a file or '-' for stdin.", valueName: "file")
    )
    var from: String?

    @Flag(name: .long, help: "Print machine-readable JSON; requires --field and --from.")
    var json = false

    func run() throws {
        try validateMode()
        let store = ManifestStore()
        let manifest = try store.loadExistingOrEmpty()
        guard let original = manifest.item(id: id) else {
            throw RegistryError.itemNotFound(id)
        }

        if let field {
            try runFieldEdit(field: field, original: original, store: store)
            return
        }

        try runWholeRecipeEdit(original: original, store: store)
    }

    private func runWholeRecipeEdit(original: Recipe, store: ManifestStore) throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-edit-\(UUID().uuidString).json")
        try JSONEncoder.updateBar.encode(original).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        try runEditor(file: temp)
        let editedData = try Data(contentsOf: temp)
        let edited = try loadEditedRecipe(data: editedData, original: original)
        guard edited.id == original.id else {
            throw ValidationError("id cannot be changed during edit")
        }
        try validateEditedRecipe(edited)

        try save(edited, store: store)
        writeStdout("edited \(SecretRedactor.redact(id))")
    }

    private func runFieldEdit(field: String, original: Recipe, store: ManifestStore) throws {
        let current = try commandText(field: field, in: original)
        let command = try editedCommand(field: field, current: current)
        let candidate = try replacingCommand(field: field, command: command, in: original)
        let edited = invalidateChangedApprovals(original: original, edited: candidate)
        try validateEditedRecipe(edited)
        let changed = edited != original

        if changed {
            try save(edited, store: store)
        }
        try outputFieldEdit(recipe: edited, field: field, changed: changed)
    }

    private func save(_ edited: Recipe, store: ManifestStore) throws {
        try store.withExclusiveLock {
            var latest = try store.loadExistingOrEmpty()
            guard latest.item(id: id) != nil else {
                throw RegistryError.itemNotFound(id)
            }
            latest = latest.replacing(item: edited)
            latest.provenance.updatedAt = Date()
            try store.save(latest)
        }
    }

    private func validateMode() throws {
        if from != nil, field == nil {
            throw ValidationError("edit --from requires --field")
        }
        if json, field == nil || from == nil {
            throw ValidationError("edit --json requires --field and --from")
        }
    }

    private func commandText(field: String, in recipe: Recipe) throws -> String {
        switch field {
        case "check.cmd":
            guard case .command(let command) = recipe.check else {
                throw ValidationError("check.cmd: recipe has no command field")
            }
            return command
        case "latest.cmd":
            guard recipe.latest.strategy == .cmd, let command = recipe.latest.cmd else {
                throw ValidationError("latest.cmd: recipe has no command field")
            }
            return command
        case "update.cmd":
            return recipe.update.cmd
        default:
            throw RegistryError.commandFieldNotFound(field)
        }
    }

    private func replacingCommand(field: String, command: String, in recipe: Recipe) throws
        -> Recipe
    {
        var copy = recipe
        _ = try commandText(field: field, in: recipe)
        switch field {
        case "check.cmd":
            copy.check = .command(command)
        case "latest.cmd":
            copy.latest.cmd = command
        case "update.cmd":
            copy.update.cmd = command
        default:
            throw RegistryError.commandFieldNotFound(field)
        }
        return copy
    }

    private func editedCommand(field: String, current: String) throws -> String {
        let data: Data
        if let from {
            data = try readInputData(from)
        } else {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("updatebar-edit-command-\(UUID().uuidString).txt")
            try Data(current.utf8).write(to: temp)
            defer { try? FileManager.default.removeItem(at: temp) }
            try runEditor(file: temp)
            data = try Data(contentsOf: temp)
        }
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw ValidationError("command input must be valid UTF-8")
        }
        let command = removingOneFinalLineEnding(from: decoded)
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("\(field): command must not be empty")
        }
        return command
    }

    private func removingOneFinalLineEnding(from value: String) -> String {
        if value.hasSuffix("\r\n") {
            return String(value.dropLast(2))
        }
        if value.hasSuffix("\n") {
            return String(value.dropLast())
        }
        return value
    }

    private func outputFieldEdit(recipe: Recipe, field: String, changed: Bool) throws {
        if json {
            try printJSON(redactedEditPayload(for: recipe, field: field, changed: changed))
            return
        }
        let verb = changed ? "edited" : "unchanged"
        writeStdout("\(verb) \(SecretRedactor.redact(recipe.id)) \(field)")
        printApprovalNextSteps(for: [recipe.id])
    }

    private func loadEditedRecipe(data: Data, original: Recipe) throws -> Recipe {
        let validation = try RecipeValidator.validate(data: data)
        if validation.isValid {
            return try invalidateChangedApprovals(
                original: original,
                edited: JSONDecoder.updateBar.decode(Recipe.self, from: data)
            )
        }

        guard let decoded = try? JSONDecoder.updateBar.decode(Recipe.self, from: data) else {
            throw ValidationError(validation.errors.joined(separator: "\n"))
        }
        let cleaned = invalidateChangedApprovals(original: original, edited: decoded)
        let cleanedValidation = try RecipeValidator.validate(
            data: JSONEncoder.updateBar.encode(cleaned))
        guard cleanedValidation.isValid else {
            throw ValidationError(cleanedValidation.errors.joined(separator: "\n"))
        }
        return cleaned
    }

    private func runEditor(file: URL) throws {
        let environment = ProcessInfo.processInfo.environment
        let editor =
            nonEmptyEnvironmentValue("VISUAL", in: environment)
            ?? nonEmptyEnvironmentValue("EDITOR", in: environment)
            ?? "vi"
        var editorParts = try parseCommand(editor)
        guard let executable = editorParts.first, !executable.isEmpty else {
            throw ValidationError("EDITOR command is empty")
        }
        let commandIndex = commandTokenIndex(afterAssignmentsIn: editorParts) ?? 0
        let command = editorParts[commandIndex]
        guard let resolvedCommand = resolveExecutable(command, environment: environment) else {
            throw ValidationError("EDITOR/VISUAL command not found in PATH: \(command)")
        }
        editorParts[commandIndex] = resolvedCommand

        // `env` applies leading assignments while avoiding shell interpolation.
        let envPath =
            FileManager.default.isExecutableFile(atPath: "/usr/bin/env")
            ? "/usr/bin/env"
            : "/bin/env"
        guard FileManager.default.isExecutableFile(atPath: envPath) else {
            throw ValidationError("environment could not resolve editor command")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: envPath)
        process.arguments = editorParts + [file.path]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ValidationError("editor exited \(process.terminationStatus)")
        }
    }

    private func nonEmptyEnvironmentValue(_ key: String, in environment: [String: String])
        -> String?
    {
        guard let value = environment[key],
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return value
    }

    private func commandTokenIndex(afterAssignmentsIn parts: [String]) -> Int? {
        let trimmed = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return trimmed.firstIndex(where: { !$0.isEmpty && !isEnvironmentAssignment($0) })
    }

    private func isEnvironmentAssignment(_ token: String) -> Bool {
        guard let firstEquals = token.firstIndex(of: "=") else {
            return false
        }
        return firstEquals != token.startIndex
    }

    private func validateEditedRecipe(_ recipe: Recipe) throws {
        let manifest = Manifest(
            schemaVersion: 1,
            items: [recipe],
            provenance: Provenance(createdBy: "updatebar", createdAt: Date(), updatedAt: Date())
        )
        let validation = try ManifestValidator.validate(
            data: JSONEncoder.updateBar.encode(manifest))
        guard validation.isValid else {
            throw ValidationError(validation.errors.joined(separator: "\n"))
        }
    }

    private func invalidateChangedApprovals(original: Recipe, edited: Recipe) -> Recipe {
        let newFingerprints = edited.commandFingerprints()
        var copy = edited
        if copy.trust.level == .untrusted {
            copy.trust.approvedCommands = [:]
            return copy
        }
        copy.trust.approvedCommands = edited.trust.approvedCommands.filter { field, approved in
            original.trust.approvedCommands[field] == approved && newFingerprints[field] == approved
        }
        if copy.trust.approvedCommands.isEmpty {
            copy.trust.level = .untrusted
        }
        return copy
    }

    private func parseCommand(_ value: String) throws -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false

        for scalar in value {
            if escaped {
                current.append(scalar)
                escaped = false
                continue
            }
            if scalar == "\\" {
                escaped = true
                continue
            }
            if let openQuote = quote {
                if scalar == openQuote {
                    quote = nil
                    continue
                }
                current.append(scalar)
                continue
            }
            if scalar == "'" || scalar == "\"" {
                quote = scalar
                continue
            }
            if scalar == " " || scalar == "\t" {
                if !current.isEmpty {
                    parts.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }
            current.append(scalar)
        }

        if escaped {
            current.append("\\")
        }
        if !current.isEmpty {
            parts.append(current)
        }
        if quote != nil {
            throw ValidationError("EDITOR/VISUAL has unmatched quote")
        }
        return parts
    }
}
