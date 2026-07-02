import ArgumentParser
import Foundation
import UpdateBarCore

struct AddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add one recipe from JSON or the manual wizard.",
        shouldDisplay: false
    )

    @Option(name: .long, help: "Recipe JSON file to add, or '-' for stdin.")
    var from: String?

    @Flag(name: .long, help: "Validate and print the recipe without saving it.")
    var dryRun = false

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    @Flag(name: .long, help: "Overwrite an existing item with the same id.")
    var replace = false

    func run() throws {
        let recipe = try loadManualRecipe()
        let validated = try validatedRecipe(recipe)
        let prepared = TrustPolicy.untrustedCopy(validated)

        if dryRun {
            try output(AddPayload(valid: true, recipe: prepared, errors: []), saved: false)
            return
        }

        do {
            let outcome = try RegistryService().addRecipe(prepared, replace: replace)
            try output(AddPayload(valid: true, recipe: prepared, errors: [], outcome: outcome), saved: true)
        } catch {
            if json {
                try output(AddPayload(
                    valid: false,
                    recipe: prepared,
                    errors: [sanitizedErrorMessage(for: error)]
                ), saved: false)
            }
            throw error
        }
    }

    private func loadManualRecipe() throws -> Recipe {
        if let from {
            if from == "-" {
                let data = FileHandle.standardInput.readDataToEndOfFile()
                return try loadRecipe(data: data)
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: from))
            return try loadRecipe(data: data)
        }
        return try runWizard()
    }

    private func loadRecipe(data: Data) throws -> Recipe {
        if try isManifestDocument(data) {
            let validation = try ManifestValidator.validate(data: data)
            guard validation.isValid else {
                throw ValidationError(validation.errors.joined(separator: "\n"))
            }
            let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)
            guard manifest.items.count == 1, let recipe = manifest.items.first else {
                throw ValidationError("add requires exactly one recipe")
            }
            return recipe
        }

        let validation = try RecipeValidator.validate(data: data)
        guard validation.isValid else {
            throw ValidationError(validation.errors.joined(separator: "\n"))
        }
        let recipe = try JSONDecoder.updateBar.decode(Recipe.self, from: data)
        return try validatedRecipe(recipe)
    }

    private func validatedRecipe(_ recipe: Recipe) throws -> Recipe {
        let manifest = Manifest(
            schemaVersion: 1,
            items: [recipe],
            provenance: Provenance(createdBy: "updatebar", createdAt: Date(), updatedAt: Date())
        )
        let data = try JSONEncoder.updateBar.encode(manifest)
        let validation = try ManifestValidator.validate(data: data)
        guard validation.isValid else {
            throw ValidationError(validation.errors.joined(separator: "\n"))
        }
        return recipe
    }

    private func output(_ payload: AddPayload, saved: Bool) throws {
        if json {
            try printJSON(payload)
        } else if payload.valid, let recipe = payload.recipe {
            if saved {
                let verb = payload.outcome == .replaced ? "replaced" : "added"
                print("\(verb) \(recipe.id)")
                printApprovalAndCheckNextSteps(for: [recipe.id])
            } else {
                print("valid \(recipe.id)")
                print("dry run: not saved")
            }
        } else {
            for error in payload.errors {
                writeStderr(error)
            }
        }
    }

    private func runWizard() throws -> Recipe {
        let id = try prompt("id")
        let name = try prompt("name")
        let category = try prompt("category")
        let path = optionalPrompt("path")
        let sourceKindText = try prompt("source.kind")
        guard let sourceKind = SourceKind(rawValue: sourceKindText) else {
            throw ValidationError("source.kind: unsupported value \(sourceKindText)")
        }
        let sourceRef = try prompt("source.ref")
        let sourceBranch = optionalPrompt("source.branch")
        let schemeText = try prompt("version_scheme")
        guard let scheme = VersionScheme(rawValue: schemeText) else {
            throw ValidationError("version_scheme: unsupported value \(schemeText)")
        }
        let checkCommand = try prompt("check.cmd")
        let latestStrategyText = try prompt("latest.strategy")
        guard let latestStrategy = LatestStrategyKind(rawValue: latestStrategyText) else {
            throw ValidationError("latest.strategy: unsupported value \(latestStrategyText)")
        }
        let latestCommand = latestStrategy == .cmd ? try prompt("latest.cmd") : optionalPrompt("latest.cmd")
        let latestPattern = latestStrategy == .httpRegex ? try prompt("latest.pattern") : optionalPrompt("latest.pattern")
        let versionRegex = try prompt("version_parse.regex")
        let updateCommand = try prompt("update.cmd")
        let updateCWD = optionalPrompt("update.cwd")

        return Recipe(
            id: id,
            name: name,
            category: category,
            path: path,
            source: Source(kind: sourceKind, ref: sourceRef, branch: sourceBranch),
            versionScheme: scheme,
            check: .command(checkCommand),
            latest: LatestSpec(strategy: latestStrategy, cmd: latestCommand, pattern: latestPattern),
            versionParse: .regex(versionRegex),
            update: UpdateSpec(cmd: updateCommand, cwd: updateCWD),
            pin: nil,
            enabled: true,
            trust: Trust(level: .untrusted, approvedCommands: [:])
        )
    }

    private func prompt(_ label: String) throws -> String {
        writePrompt(label)
        guard let line = readLine() else {
            writeStderr("")
            throw ValidationError("\(label): required")
        }
        guard !line.isEmpty else {
            throw ValidationError("\(label): required")
        }
        return line
    }

    private func optionalPrompt(_ label: String) -> String? {
        writePrompt(label)
        guard let line = readLine() else {
            writeStderr("")
            return nil
        }
        guard !line.isEmpty else {
            return nil
        }
        return line
    }
}
