import ArgumentParser
import Foundation
import UpdateBarCore

struct ExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export registered recipes as a manifest.",
        shouldDisplay: false
    )

    @Argument(help: "Output file path; omit when using --json.")
    var file: String?

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    func run() throws {
        if json, file != nil {
            throw ValidationError("export --json does not accept a file argument.")
        }
        guard json || file != nil else {
            throw ValidationError("provide an export file or --json")
        }

        let manifest = try RegistryService().exportManifest()
        if json {
            try printJSON(manifest)
            return
        }
        guard let file else { return }
        try writeOutputData(JSONEncoder.updateBar.encode(manifest), to: file)
        writeStdout("exported \(file)")
    }
}

struct ImportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import recipes from a manifest file or stdin.",
        shouldDisplay: false
    )

    @Argument(help: "Manifest file path, or '-' for stdin.")
    var file: String

    @Flag(name: .long, help: "Overwrite existing items with matching ids.")
    var replace = false

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    func run() throws {
        let data = try readInputData(file)
        let validation = try ManifestValidator.validate(data: data)
        guard validation.isValid else {
            if json {
                try printJSON(ImportPayload(added: [], replaced: [], errors: validation.errors))
            } else {
                for error in validation.errors {
                    writeStderr(error)
                }
            }
            throw ExitCode.failure
        }

        let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)
        do {
            let summary = try RegistryService().importManifest(manifest, replace: replace)
            if json {
                try printJSON(ImportPayload(summary: summary, errors: []))
            } else {
                print("imported \(summary.added.count + summary.replaced.count) item(s)")
                printApprovalAndCheckNextSteps(for: summary.added + summary.replaced)
            }
        } catch {
            if json {
                try printJSON(ImportPayload(
                    added: [],
                    replaced: [],
                    errors: [sanitizedErrorMessage(for: error)]
                ))
            }
            throw error
        }
    }
}
