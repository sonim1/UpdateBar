import Foundation
import XCTest
import UpdateBarCore
import UpdateBarTestSupport

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

    func testEditSupportsEditorArguments() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let editor = try editorScript(home: home, body: #"if [ "$1" = "--normalize" ]; then perl -0pi -e 's/"name" : "Tool"/"name" : "Arg Tool"/' "$2"; else exit 1; fi"#)

        let result = try CLIProcess.run(
            ["edit", "tool"],
            home: home,
            environment: ["EDITOR": "\(editor.path) --normalize"]
        )
        let manifest = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(manifest.item(id: "tool")?.name, "Arg Tool")
    }

    func testEditResolvesEditorFromPath() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let binDir = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let editor = try editorScript(home: binDir, body: #"perl -0pi -e 's/"name" : "Tool"/"name" : "Path Tool"/' "$1""#)
        let editorPath = home.appendingPathComponent("bin/updatebar-editor").path
        try FileManager.default.moveItem(at: editor, to: URL(fileURLWithPath: editorPath))

        let systemPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let result = try CLIProcess.run(
            ["edit", "tool"],
            home: home,
            environment: [
                "EDITOR": "updatebar-editor",
                "PATH": "\(binDir.path):\(systemPath)"
            ]
        )
        let manifest = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(manifest.item(id: "tool")?.name, "Path Tool")
    }

    func testEditRunsTheValidatedPathExecutable() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let binDir = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let safeEditor = try editorScript(home: binDir, body: #"perl -0pi -e 's/"name" : "Tool"/"name" : "Safe Tool"/' "$1""#)
        let safeEditorPath = binDir.appendingPathComponent("updatebar-editor")
        try FileManager.default.moveItem(at: safeEditor, to: safeEditorPath)
        let relativeEditor = try editorScript(home: home, body: #"perl -0pi -e 's/"name" : "Tool"/"name" : "Relative Tool"/' "$1""#)
        try FileManager.default.moveItem(at: relativeEditor, to: home.appendingPathComponent("updatebar-editor"))

        let systemPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let result = try CLIProcess.run(
            ["edit", "tool"],
            home: home,
            currentDirectory: home,
            environment: [
                "EDITOR": "updatebar-editor",
                "PATH": ".:\(binDir.path):\(systemPath)"
            ]
        )
        let manifest = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(manifest.item(id: "tool")?.name, "Safe Tool")
    }

    func testEditSupportsQuotedEditorPathWithSpaces() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let spacedDirectory = home.appendingPathComponent("My Editors")
        try FileManager.default.createDirectory(at: spacedDirectory, withIntermediateDirectories: true)
        let editor = try editorScript(home: spacedDirectory, body: #"perl -0pi -e 's/"name" : "Tool"/"name" : "Spaced Tool"/' "$1""#)
        let quotedEditor = "'\(editor.path)'"

        let result = try CLIProcess.run(
            ["edit", "tool"],
            home: home,
            environment: ["EDITOR": quotedEditor]
        )
        let manifest = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(manifest.item(id: "tool")?.name, "Spaced Tool")
    }

    func testEditSupportsEnvironmentAssignmentsAndQuotedPath() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let spacedDirectory = home.appendingPathComponent("Editor Home")
        try FileManager.default.createDirectory(at: spacedDirectory, withIntermediateDirectories: true)
        let editor = try editorScript(
            home: spacedDirectory,
            body: #"perl -0pi -e 's/"name" : "Tool"/"name" : "Assigned Tool"/' "$1""#
        )
        let editorSpec = "UPDATEBAR_TEST_EDITOR=1 '\(editor.path)'"

        let result = try CLIProcess.run(
            ["edit", "tool"],
            home: home,
            environment: ["EDITOR": editorSpec]
        )
        let manifest = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(manifest.item(id: "tool")?.name, "Assigned Tool")
    }

    func testEditFallsBackToEditorWhenVisualIsEmpty() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let editor = try editorScript(home: home, body: #"perl -0pi -e 's/"name" : "Tool"/"name" : "Editor Tool"/' "$1""#)

        let result = try CLIProcess.run(
            ["edit", "tool"],
            home: home,
            environment: [
                "VISUAL": "",
                "EDITOR": editor.path,
            ]
        )
        let manifest = try ManifestStore(paths: paths).load()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(manifest.item(id: "tool")?.name, "Editor Tool")
    }

    func testEditRejectsUnknownEditorCommand() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)

        let result = try CLIProcess.run(["edit", "tool"], home: home, environment: ["EDITOR": "no-such-editor"])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("EDITOR/VISUAL command not found in PATH: no-such-editor"))
        XCTAssertEqual(try ManifestStore(paths: paths).load().item(id: "tool")?.name, "Tool")
    }

    func testEditMissingItemDoesNotCreateManifest() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)

        let result = try CLIProcess.run(["edit", "missing"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("missing: item not found"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.manifestFile.path))
    }

    func testEditRejectsUnknownEditorCommandAfterAssignments() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)

        let result = try CLIProcess.run(["edit", "tool"], home: home, environment: ["EDITOR": "FOO=1 no-such-editor"])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("EDITOR/VISUAL command not found in PATH: no-such-editor"))
        XCTAssertEqual(try ManifestStore(paths: paths).load().item(id: "tool")?.name, "Tool")
    }

    func testInvalidEditorCommandRejections() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)

        let result = try CLIProcess.run(["edit", "tool"], home: home, environment: ["EDITOR": "unterminated 'command"])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("EDITOR/VISUAL has unmatched quote"))
        XCTAssertEqual(try ManifestStore(paths: paths).load().item(id: "tool")?.name, "Tool")
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

    func testInvalidEditReportsValidationErrorsWithoutCodingKeys() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let editor = try editorScript(home: home, body: #"printf '{ "id": "tool" }' > "$1""#)

        let result = try CLIProcess.run(["edit", "tool"], home: home, environment: ["EDITOR": editor.path])
        let manifest = try ManifestStore(paths: paths).load()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("$.name: required"))
        XCTAssertTrue(result.stderr.contains("$.source: required"))
        XCTAssertFalse(result.stderr.contains("CodingKeys"))
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

    func testEditMarksRecipeUntrustedWhenAllApprovalsAreInvalidated() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let original = try XCTUnwrap(ManifestStore(paths: paths).load().item(id: "tool"))
        let checkApproval = try XCTUnwrap(original.trust.approvedCommands["check.cmd"])
        let latestApproval = try XCTUnwrap(original.trust.approvedCommands["latest.cmd"])
        let updateApproval = try XCTUnwrap(original.trust.approvedCommands["update.cmd"])
        let editor = try editorScript(
            home: home,
            body: """
            cat > "$1" <<'JSON'
            {
              "id": "tool",
              "name": "Tool",
              "category": "cli",
              "path": null,
              "source": { "kind": "custom", "ref": "tool", "branch": null },
              "version_scheme": "semver",
              "check": { "cmd": "printf 'tool 2.0.0'" },
              "latest": { "strategy": "cmd", "cmd": "printf 'tool 2.1.0'", "pattern": null },
              "version_parse": { "regex": "([0-9]+\\\\.[0-9]+\\\\.[0-9]+)" },
              "update": { "cmd": "printf changed", "requires_write": true, "cwd": null },
              "pin": null,
              "enabled": true,
              "trust": {
                "level": "trusted",
                "approved_commands": {
                  "check.cmd": "\(checkApproval)",
                  "latest.cmd": "\(latestApproval)",
                  "update.cmd": "\(updateApproval)"
                }
              }
            }
            JSON
            """
        )

        let result = try CLIProcess.run(["edit", "tool"], home: home, environment: ["EDITOR": editor.path])
        let recipe = try XCTUnwrap(ManifestStore(paths: paths).load().item(id: "tool"))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(recipe.trust.approvedCommands, [:])
        XCTAssertEqual(recipe.trust.level, .untrusted)
    }

    func testEditClearsApprovalsWhenRecipeIsMarkedUntrusted() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let original = try XCTUnwrap(ManifestStore(paths: paths).load().item(id: "tool"))
        let checkApproval = try XCTUnwrap(original.trust.approvedCommands["check.cmd"])
        let latestApproval = try XCTUnwrap(original.trust.approvedCommands["latest.cmd"])
        let updateApproval = try XCTUnwrap(original.trust.approvedCommands["update.cmd"])
        let editor = try editorScript(
            home: home,
            body: """
            cat > "$1" <<'JSON'
            {
              "id": "tool",
              "name": "Tool",
              "category": "cli",
              "path": null,
              "source": { "kind": "custom", "ref": "tool", "branch": null },
              "version_scheme": "semver",
              "check": { "cmd": "printf 'tool 1.0.0'" },
              "latest": { "strategy": "cmd", "cmd": "printf 'tool 1.1.0'", "pattern": null },
              "version_parse": { "regex": "([0-9]+\\\\.[0-9]+\\\\.[0-9]+)" },
              "update": { "cmd": "printf updated", "requires_write": true, "cwd": null },
              "pin": null,
              "enabled": true,
              "trust": {
                "level": "untrusted",
                "approved_commands": {
                  "check.cmd": "\(checkApproval)",
                  "latest.cmd": "\(latestApproval)",
                  "update.cmd": "\(updateApproval)"
                }
              }
            }
            JSON
            """
        )

        let result = try CLIProcess.run(["edit", "tool"], home: home, environment: ["EDITOR": editor.path])
        let recipe = try XCTUnwrap(ManifestStore(paths: paths).load().item(id: "tool"))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(recipe.trust.level, .untrusted)
        XCTAssertEqual(recipe.trust.approvedCommands, [:])
    }

    func testChangingCheckCommandToFileInvalidatesStaleCheckApproval() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let versionFile = home.appendingPathComponent("version.txt")
        try "tool 1.0.0\n".write(to: versionFile, atomically: true, encoding: .utf8)
        let original = try XCTUnwrap(ManifestStore(paths: paths).load().item(id: "tool"))
        let checkApproval = try XCTUnwrap(original.trust.approvedCommands["check.cmd"])
        let latestApproval = try XCTUnwrap(original.trust.approvedCommands["latest.cmd"])
        let updateApproval = try XCTUnwrap(original.trust.approvedCommands["update.cmd"])
        let editor = try editorScript(
            home: home,
            body: """
            cat > "$1" <<'JSON'
            {
              "id": "tool",
              "name": "Tool",
              "category": "cli",
              "path": null,
              "source": { "kind": "custom", "ref": "tool", "branch": null },
              "version_scheme": "semver",
              "check": { "file": "\(versionFile.path)" },
              "latest": { "strategy": "cmd", "cmd": "printf 'tool 1.1.0'", "pattern": null },
              "version_parse": { "regex": "([0-9]+\\\\.[0-9]+\\\\.[0-9]+)" },
              "update": { "cmd": "printf updated", "requires_write": true, "cwd": null },
              "pin": null,
              "enabled": true,
              "trust": {
                "level": "trusted",
                "approved_commands": {
                  "check.cmd": "\(checkApproval)",
                  "latest.cmd": "\(latestApproval)",
                  "update.cmd": "\(updateApproval)"
                }
              }
            }
            JSON
            """
        )

        let result = try CLIProcess.run(["edit", "tool"], home: home, environment: ["EDITOR": editor.path])
        let recipe = try XCTUnwrap(ManifestStore(paths: paths).load().item(id: "tool"))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(recipe.check, .file(path: versionFile.path))
        XCTAssertNil(recipe.trust.approvedCommands["check.cmd"])
        XCTAssertNotNil(recipe.trust.approvedCommands["latest.cmd"])
        XCTAssertNil(recipe.trust.approvedCommands["update.cmd"])
    }

    func testEditReportsRemainingValidationErrorsAfterCleaningStaleApprovals() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let versionFile = home.appendingPathComponent("version.txt")
        try "tool 1.0.0\n".write(to: versionFile, atomically: true, encoding: .utf8)
        let original = try XCTUnwrap(ManifestStore(paths: paths).load().item(id: "tool"))
        let checkApproval = try XCTUnwrap(original.trust.approvedCommands["check.cmd"])
        let latestApproval = try XCTUnwrap(original.trust.approvedCommands["latest.cmd"])
        let updateApproval = try XCTUnwrap(original.trust.approvedCommands["update.cmd"])
        let editor = try editorScript(
            home: home,
            body: """
            cat > "$1" <<'JSON'
            {
              "id": "tool",
              "name": "Tool",
              "category": "cli",
              "path": null,
              "source": { "kind": "custom", "ref": "tool", "branch": null },
              "version_scheme": "semver",
              "check": { "file": "\(versionFile.path)" },
              "latest": { "strategy": "cmd", "cmd": "printf 'tool 1.1.0'", "pattern": null },
              "version_parse": { "regex": "[0-9]+\\\\.[0-9]+\\\\.[0-9]+" },
              "update": { "cmd": "printf updated", "requires_write": true, "cwd": null },
              "pin": null,
              "enabled": true,
              "trust": {
                "level": "trusted",
                "approved_commands": {
                  "check.cmd": "\(checkApproval)",
                  "latest.cmd": "\(latestApproval)",
                  "update.cmd": "\(updateApproval)"
                }
              }
            }
            JSON
            """
        )

        let result = try CLIProcess.run(["edit", "tool"], home: home, environment: ["EDITOR": editor.path])
        let recipe = try XCTUnwrap(ManifestStore(paths: paths).load().item(id: "tool"))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("version_parse.regex: invalid; expected exactly one capture group"))
        XCTAssertFalse(result.stderr.contains("approved_commands"))
        XCTAssertEqual(recipe.check, .command("printf 'tool 1.0.0'"))
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
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TestApprovals.approveAllCommands(in: &item)
        return item
    }
}
