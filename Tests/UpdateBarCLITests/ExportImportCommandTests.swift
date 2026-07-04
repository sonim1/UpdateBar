import Foundation
import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class ExportImportCommandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testImportValidManifestMarksItemsUntrustedAndDoesNotCreateState() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-import-tests")
        let paths = AppPaths(homeDirectory: home)
        let importFile = try writeImportManifest(home: home, items: [recipe(id: "imported")])

        let result = try CLIProcess.run(["import", importFile.path, "--json"], home: home)
        let manifest = try ManifestStore(paths: paths).load()
        let payload = try JSONDecoder.updateBar.decode(
            ImportPayload.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(payload.ok)
        XCTAssertEqual(payload.added, ["imported"])
        XCTAssertEqual(payload.replaced, [])
        XCTAssertEqual(payload.errors, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
        XCTAssertEqual(manifest.item(id: "imported")?.trust.level, .untrusted)
        XCTAssertEqual(manifest.item(id: "imported")?.trust.approvedCommands, [:])
    }

    func testImportRejectsDuplicateUnlessReplaceIsPassed() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-import-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(
            manifest(items: [recipe(id: "tool", name: "Original")]))
        let importFile = try writeImportManifest(
            home: home, items: [recipe(id: "tool", name: "Replacement")])

        let duplicate = try CLIProcess.run(["import", importFile.path, "--json"], home: home)
        var stored = try ManifestStore(paths: paths).load()
        let duplicatePayload = try JSONDecoder.updateBar.decode(
            ImportPayload.self, from: Data(duplicate.stdout.utf8))

        XCTAssertNotEqual(duplicate.exitCode, 0)
        XCTAssertFalse(duplicatePayload.ok)
        XCTAssertEqual(duplicatePayload.added, [])
        XCTAssertEqual(duplicatePayload.replaced, [])
        XCTAssertTrue(
            duplicatePayload.errors.contains("tool: duplicate item; pass --replace to overwrite"))
        XCTAssertEqual(stored.item(id: "tool")?.name, "Original")

        let replaced = try CLIProcess.run(
            ["import", importFile.path, "--replace", "--json"], home: home)
        stored = try ManifestStore(paths: paths).load()
        let replacedPayload = try JSONDecoder.updateBar.decode(
            ImportPayload.self, from: Data(replaced.stdout.utf8))

        XCTAssertEqual(replaced.exitCode, 0)
        XCTAssertTrue(replacedPayload.ok)
        XCTAssertEqual(replacedPayload.added, [])
        XCTAssertEqual(replacedPayload.replaced, ["tool"])
        XCTAssertEqual(replacedPayload.errors, [])
        XCTAssertEqual(stored.item(id: "tool")?.name, "Replacement")
        XCTAssertEqual(stored.item(id: "tool")?.trust.level, .untrusted)
    }

    func testImportRejectsUnsupportedSchemaVersion() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-import-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: []))
        let file = home.appendingPathComponent("invalid.json")
        try Data(#"{"schema_version":99,"items":[]}"#.utf8).write(to: file)

        let result = try CLIProcess.run(["import", file.path, "--json"], home: home)
        let stored = try ManifestStore(paths: paths).load()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(stored.items.isEmpty)
    }

    func testImportMissingInputFileJSONReturnsUsageError() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-import-tests")
        let file = home.appendingPathComponent("missing-manifest.json")

        let result = try CLIProcess.run(["import", file.path, "--json"], home: home)
        let payload = try JSONDecoder.updateBar.decode(
            ErrorPayload.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(payload.code, "usage_error")
        XCTAssertTrue(payload.errors.contains { $0.contains("missing-manifest.json") })
    }

    func testImportReadsManifestFromStdin() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-import-tests")
        let paths = AppPaths(homeDirectory: home)
        let encoded = try JSONEncoder.updateBar.encode(manifest(items: [recipe(id: "stdin")]))

        let result = try CLIProcess.run(
            ["import", "-", "--json"],
            home: home,
            stdin: String(decoding: encoded, as: UTF8.self)
        )
        let stored = try ManifestStore(paths: paths).load()
        let payload = try JSONDecoder.updateBar.decode(
            ImportPayload.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(payload.added, ["stdin"])
        XCTAssertEqual(payload.replaced, [])
        XCTAssertEqual(stored.item(id: "stdin")?.trust.level, .untrusted)
    }

    func testImportEmptyStdinJSONReturnsDecodeError() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-import-tests")

        let result = try CLIProcess.run(["import", "-", "--json"], home: home, stdin: "")
        let payload = try JSONDecoder.updateBar.decode(
            ErrorPayload.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(payload.code, "decode_error")
        XCTAssertTrue(payload.errors.contains("document is not valid JSON"))
    }

    func testImportHumanModePrintsApprovalNextStepBeforeCheck() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-import-tests")
        let importFile = try writeImportManifest(home: home, items: [recipe(id: "imported")])

        let result = try CLIProcess.run(["import", importFile.path], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("imported 1 item(s)"))
        XCTAssertTrue(result.stdout.contains("Next"))
        XCTAssertTrue(result.stdout.contains("updatebar approvals imported"))
        XCTAssertFalse(result.stdout.contains("updatebar check imported"))
    }

    func testExportWritesManifestObjectAndPrintsJSON() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-export-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: [recipe(id: "tool")]))
        let output = home.appendingPathComponent("exported.json")

        let fileResult = try CLIProcess.run(["export", output.path], home: home)
        let jsonResult = try CLIProcess.run(["export", "--json"], home: home)

        XCTAssertEqual(fileResult.exitCode, 0)
        XCTAssertEqual(jsonResult.exitCode, 0)
        XCTAssertEqual(
            try JSONDecoder.updateBar.decode(Manifest.self, from: Data(contentsOf: output)).items
                .count, 1)
        XCTAssertEqual(
            try JSONDecoder.updateBar.decode(Manifest.self, from: Data(jsonResult.stdout.utf8))
                .items.count, 1)
    }

    func testExportHumanOutputRedactsSecretLikeOutputPath() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-export-tests")
        let paths = AppPaths(homeDirectory: home)
        let secret = "sk-or-v1-secret-value"
        try ManifestStore(paths: paths).save(manifest(items: [recipe(id: "tool")]))
        let output = home.appendingPathComponent("\(secret)-exported.json")

        let result = try CLIProcess.run(["export", output.path], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(result.stdout.contains("exported "))
        XCTAssertTrue(result.stdout.contains("[REDACTED]"))
        XCTAssertFalse(result.stdout.contains(secret))
    }

    func testExportJSONRejectsLegacyManifestWithLiteralSecret() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-export-tests")
        let paths = AppPaths(homeDirectory: home)
        let secret = "sk-or-v1-secret-value"
        var item = recipe(id: "tool")
        item.update.cmd = "tool update --token \(secret)"
        try ManifestStore(paths: paths).save(manifest(items: [item]))

        let result = try CLIProcess.run(["export", "--json"], home: home)
        let payload = try JSONDecoder.updateBar.decode(
            ErrorPayload.self, from: Data(result.stdout.utf8))
        let combined = result.stdout + result.stderr

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(payload.code, "registry_error")
        XCTAssertTrue(
            payload.errors.contains {
                $0.contains("items[0].update.cmd: must not contain literal secrets")
            })
        XCTAssertFalse(combined.contains(secret))
    }

    func testExportJSONDoesNotCreateManifestOnFreshHome() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-export-tests")
        let paths = AppPaths(homeDirectory: home)

        let result = try CLIProcess.run(["export", "--json"], home: home)
        let exported = try JSONDecoder.updateBar.decode(
            Manifest.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(exported.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.manifestFile.path))
    }

    func testExportWithJSONDisallowsFileOutputPath() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-export-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: [recipe(id: "tool")]))
        let output = home.appendingPathComponent("exported.json")

        let result = try CLIProcess.run(["export", output.path, "--json"], home: home)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let combined = result.stdout + result.stderr
        XCTAssertTrue(combined.contains("export --json does not accept a file argument."))
    }

    func testExportJSONUsageErrorDoesNotCreateManifest() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-export-tests")
        let paths = AppPaths(homeDirectory: home)
        let output = home.appendingPathComponent("exported.json")

        let result = try CLIProcess.run(["export", output.path, "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.manifestFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testExportMissingOutputDirectoryReportsWritablePath() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-export-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: [recipe(id: "tool")]))
        let output = home.appendingPathComponent("missing/exported.json")

        let result = try CLIProcess.run(["export", output.path], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains(output.path))
        XCTAssertTrue(result.stderr.contains("output file could not be written"))
    }

    private func writeImportManifest(home: URL, items: [Recipe]) throws -> URL {
        let file = home.appendingPathComponent("import.json")
        try JSONEncoder.updateBar.encode(manifest(items: items)).write(to: file)
        return file
    }

    private struct ImportPayload: Decodable {
        var ok: Bool
        var added: [String]
        var replaced: [String]
        var errors: [String]
    }

    private struct ErrorPayload: Decodable {
        var code: String
        var errors: [String]
    }

    private func manifest(items: [Recipe]) -> Manifest {
        Manifest(
            schemaVersion: 1,
            items: items,
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        )
    }

    private func recipe(id: String, name: String? = nil) -> Recipe {
        var item = Recipe(
            id: id,
            name: name ?? id,
            category: "cli",
            path: nil,
            source: Source(kind: .custom, ref: id, branch: nil),
            versionScheme: .semver,
            check: .command("printf '\(id) 1.0.0'"),
            latest: LatestSpec(strategy: .cmd, cmd: "printf '\(id) 1.1.0'", pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: "printf updated", cwd: nil),
            pin: nil,
            enabled: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TestApprovals.approveAllCommands(in: &item)
        return item
    }
}
