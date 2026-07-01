import Foundation
import XCTest
import UpdateBarCore

final class ExportImportCommandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testImportValidManifestMarksItemsUntrustedAndDoesNotCreateState() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-import-tests")
        let paths = AppPaths(homeDirectory: home)
        let importFile = try writeImportManifest(home: home, items: [recipe(id: "imported")])

        let result = try CLIProcess.run(["import", importFile.path, "--json"], home: home)
        let manifest = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
        XCTAssertEqual(manifest.item(id: "imported")?.trust.level, .untrusted)
        XCTAssertEqual(manifest.item(id: "imported")?.trust.approvedCommands, [:])
    }

    func testImportRejectsDuplicateUnlessReplaceIsPassed() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-import-tests")
        let paths = AppPaths(homeDirectory: home)
        try ManifestStore(paths: paths).save(manifest(items: [recipe(id: "tool", name: "Original")]))
        let importFile = try writeImportManifest(home: home, items: [recipe(id: "tool", name: "Replacement")])

        let duplicate = try CLIProcess.run(["import", importFile.path, "--json"], home: home)
        var stored = try ManifestStore(paths: paths).load()

        XCTAssertNotEqual(duplicate.exitCode, 0)
        XCTAssertEqual(stored.item(id: "tool")?.name, "Original")

        let replaced = try CLIProcess.run(["import", importFile.path, "--replace", "--json"], home: home)
        stored = try ManifestStore(paths: paths).load()

        XCTAssertEqual(replaced.exitCode, 0)
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

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(stored.item(id: "stdin")?.trust.level, .untrusted)
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
        XCTAssertEqual(try JSONDecoder.updateBar.decode(Manifest.self, from: Data(contentsOf: output)).items.count, 1)
        XCTAssertEqual(try JSONDecoder.updateBar.decode(Manifest.self, from: Data(jsonResult.stdout.utf8)).items.count, 1)
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

    private func writeImportManifest(home: URL, items: [Recipe]) throws -> URL {
        let file = home.appendingPathComponent("import.json")
        try JSONEncoder.updateBar.encode(manifest(items: items)).write(to: file)
        return file
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
            notify: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TrustPolicy.approveAllCommands(in: &item)
        return item
    }
}
