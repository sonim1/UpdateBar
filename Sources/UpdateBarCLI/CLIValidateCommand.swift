import ArgumentParser
import Foundation
import UpdateBarCore

struct ValidateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate a recipe or manifest document.",
        shouldDisplay: false
    )

    @Argument(help: "Recipe or manifest file to validate, or '-' for stdin.")
    var file: String

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    @Flag(name: .long, help: "Include structured validation explanations in JSON output.")
    var explain = false

    func run() throws {
        let data = try readInputData(file)
        let result = try validateRecipeDocument(data)
        if json {
            try printJSON(
                ValidationPayload(
                    ok: result.isValid,
                    valid: result.isValid,
                    errors: result.errors,
                    explanations: explain
                        ? result.errors.map(ValidationExplanation.init(error:)) : nil
                ))
        } else if result.isValid {
            writeStdout("valid")
        } else {
            for error in result.errors {
                writeStderr(error)
            }
        }
        if !result.isValid {
            throw ExitCode.failure
        }
    }

    private func validateRecipeDocument(_ data: Data) throws -> ValidationResult {
        if try isManifestDocument(data) {
            return try ManifestValidator.validate(data: data)
        }
        return try RecipeValidator.validate(data: data)
    }
}
