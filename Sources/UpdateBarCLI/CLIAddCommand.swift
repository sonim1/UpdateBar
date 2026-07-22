import ArgumentParser
import Foundation
import UpdateBarCore

struct AddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add one recipe from JSON.",
        usage: "updatebar add --from <file|-> [--dry-run] [--json] [--replace]"
    )

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Required recipe input: recipe or single-item manifest JSON file, or '-' for stdin.",
            valueName: "file")
    )
    var from: String?

    @Flag(name: .long, help: "Validate and print the recipe without saving it.")
    var dryRun = false

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    @Flag(name: .long, help: "Overwrite an existing item with the same id.")
    var replace = false

    func run() throws {
        let recipe = try loadRecipeInput()
        let validated = try validatedRecipe(recipe)
        let prepared = TrustPolicy.untrustedCopy(validated)

        if dryRun {
            try output(redactedAddPayload(valid: true, recipe: prepared, errors: []), saved: false)
            return
        }

        do {
            let outcome = try RegistryService().addRecipe(prepared, replace: replace)
            try output(
                redactedAddPayload(valid: true, recipe: prepared, errors: [], outcome: outcome),
                saved: true
            )
        } catch {
            if json {
                try output(
                    redactedAddPayload(
                        valid: false,
                        recipe: prepared,
                        errors: [sanitizedErrorMessage(for: error)]
                    ), saved: false)
                throw ExitCode.failure
            }
            throw error
        }
    }

    private func loadRecipeInput() throws -> Recipe {
        guard let from else {
            throw ValidationError(
                "add requires recipe input; pass --from <file> or --from - for stdin")
        }
        let data = try readInputData(from)
        return try loadRecipe(data: data)
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
                writeStdout("\(verb) \(SecretRedactor.redact(recipe.id))")
                printApprovalNextSteps(for: [recipe.id])
            } else {
                writeStdout("valid \(SecretRedactor.redact(recipe.id))")
                writeStdout("dry run: not saved")
            }
        } else {
            for error in payload.errors {
                writeStderr(error)
            }
        }
    }
}
