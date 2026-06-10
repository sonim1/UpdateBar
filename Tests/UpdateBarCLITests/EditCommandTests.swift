import Foundation
import XCTest
import UpdateBarCore

final class EditCommandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testEditSavesValidEditorChanges() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let editor = try editorScript(home: home, body: #"perl -0pi -e 's/"name" : "Tool"/"name" : "Edited Tool"/' "$1""#)

        let result = try CLIProcess.run(["edit", "tool"], home: home, environment: ["EDITOR": editor.path])
        let manifest = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(manifest.item(id: "tool")?.name, "Edited Tool")
    }

    func testInvalidEditLeavesOriginalManifestUnchanged() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let editor = try editorScript(home: home, body: #"printf '{' > "$1""#)

        let result = try CLIProcess.run(["edit", "tool"], home: home, environment: ["EDITOR": editor.path])
        let manifest = try ManifestStore(paths: paths).load()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(manifest.item(id: "tool")?.name, "Tool")
    }

    func testCommandChangesInvalidateAffectedApproval() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let editor = try editorScript(
            home: home,
            body: #"perl -0pi -e 's/printf updated/printf changed/' "$1""#
        )

        let result = try CLIProcess.run(["edit", "tool"], home: home, environment: ["EDITOR": editor.path])
        let recipe = try XCTUnwrap(ManifestStore(paths: paths).load().item(id: "tool"))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertNil(recipe.trust.approvedCommands["update.cmd"])
        XCTAssertNotNil(recipe.trust.approvedCommands["check.cmd"])
    }

    private func saveManifest(paths: AppPaths) throws {
        try ManifestStore(paths: paths).save(Manifest(
            schemaVersion: 1,
            items: [recipe()],
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        ))
    }

    private func editorScript(home: URL, body: String) throws -> URL {
        let url = home.appendingPathComponent("editor-\(UUID().uuidString).sh")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func recipe() -> Recipe {
        var item = Recipe(
            id: "tool",
            name: "Tool",
            category: "cli",
            path: nil,
            source: Source(kind: .custom, ref: "tool", branch: nil),
            versionScheme: .semver,
            check: .command("printf 'tool 1.0.0'"),
            latest: LatestSpec(strategy: .cmd, cmd: "printf 'tool 1.1.0'", pattern: nil),
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
