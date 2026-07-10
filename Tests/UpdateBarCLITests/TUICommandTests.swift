import Foundation
import XCTest

final class TUICommandTests: XCTestCase {
    func testTUICommandResolvesFromPATH() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-tui-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("updatebar-tui"),
            """
            #!/bin/sh
            echo "bin:$UPDATEBAR_BIN"
            """
        )

        let result = try CLIProcess.run(
            ["tui"],
            home: home,
            environment: [
                "PATH": bin.path,
                "UPDATEBAR_BIN": "/tmp/custom-bin-from-env",
            ]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            "bin:/tmp/custom-bin-from-env")
    }

    func testTUICommandDoesNotForwardSecretEnvironment() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-tui-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("updatebar-tui"),
            """
            #!/bin/sh
            printf 'secret=%s\\n' "${OPENROUTER_API_KEY:-missing}"
            printf 'home=%s\\n' "${UPDATEBAR_HOME:-missing}"
            printf 'term=%s\\n' "${TERM:-missing}"
            """
        )

        let result = try CLIProcess.run(
            ["tui"],
            home: home,
            environment: [
                "PATH": bin.path,
                "OPENROUTER_API_KEY": "sk-or-v1-secret-value",
                "TERM": "xterm-256color",
            ]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("secret=missing"))
        XCTAssertTrue(result.stdout.contains("home=\(home.path)"))
        XCTAssertTrue(result.stdout.contains("term=xterm-256color"))
        XCTAssertFalse(result.stdout.contains("sk-or-v1-secret-value"))
    }

    func testTUICommandForwardsGitHubTokensForReleaseChecks() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-tui-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("updatebar-tui"),
            """
            #!/bin/sh
            printf 'github=%s\\n' "${GITHUB_TOKEN:-missing}"
            printf 'gh=%s\\n' "${GH_TOKEN:-missing}"
            """
        )

        let result = try CLIProcess.run(
            ["tui"],
            home: home,
            environment: [
                "PATH": bin.path,
                "GITHUB_TOKEN": "ghp_release_check_token",
                "GH_TOKEN": "gh_release_check_token",
            ]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("github=ghp_release_check_token"))
        XCTAssertTrue(result.stdout.contains("gh=gh_release_check_token"))
    }

    func testTUICommandResolvesFromEnvironmentOverride() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-tui-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let pathBin = home.appendingPathComponent("path-bin")
        let overrideBin = home.appendingPathComponent("override-bin")
        try FileManager.default.createDirectory(at: pathBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: overrideBin, withIntermediateDirectories: true)

        try writeExecutable(
            pathBin.appendingPathComponent("updatebar-tui"),
            """
            #!/bin/sh
            echo "path:$UPDATEBAR_BIN"
            """
        )
        try writeExecutable(
            overrideBin.appendingPathComponent("updatebar-tui-custom"),
            """
            #!/bin/sh
            echo "override:$UPDATEBAR_BIN"
            """
        )

        let result = try CLIProcess.run(
            ["tui"],
            home: home,
            environment: [
                "PATH": pathBin.path,
                "UPDATEBAR_TUI": overrideBin.appendingPathComponent("updatebar-tui-custom").path,
                "UPDATEBAR_BIN": "/tmp/override-bin",
            ]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            "override:/tmp/override-bin")
    }

    func testTUICommandRejectsInvalidEnvironmentOverridePath() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-tui-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("updatebar-tui"),
            """
            #!/bin/sh
            echo "path:$UPDATEBAR_BIN"
            """
        )

        let invalid = home.appendingPathComponent("not-an-executable")
        try Data("not executable".utf8).write(to: invalid)

        let result = try CLIProcess.run(
            ["tui"],
            home: home,
            environment: [
                "PATH": bin.path,
                "UPDATEBAR_TUI": invalid.path,
                "UPDATEBAR_BIN": "/tmp/invalid-bin",
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("UPDATEBAR_TUI is not executable"))
    }

    func testTUICommandRedactsInvalidEnvironmentOverridePath() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-tui-tests")
        let secretPath = "/tmp/sk-or-v1-secret-value/updatebar-tui"

        let result = try CLIProcess.run(
            ["tui"],
            home: home,
            environment: [
                "PATH": home.path,
                "UPDATEBAR_TUI": secretPath,
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("UPDATEBAR_TUI is not executable"))
        XCTAssertTrue(result.stderr.contains("/tmp/[REDACTED]/updatebar-tui"))
        XCTAssertFalse(result.stderr.contains("sk-or-v1-secret-value"))
    }

    func testTUICommandReportsMissingBinary() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-tui-tests")

        let result = try CLIProcess.run(["tui"], home: home, environment: ["PATH": home.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("updatebar-tui is not installed."))
        XCTAssertTrue(result.stderr.contains("brew install sonim1/tap/updatebar-tui"))
        XCTAssertTrue(result.stderr.contains("npm --prefix tui install"))
        XCTAssertTrue(result.stderr.contains("UPDATEBAR_TUI"))
    }

    func testTUICommandIgnoresRelativePathEntries() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-tui-tests")
        try writeExecutable(
            home.appendingPathComponent("updatebar-tui"),
            """
            #!/bin/sh
            echo "relative-path"
            """
        )

        let result = try CLIProcess.run(
            ["tui"],
            home: home,
            currentDirectory: home,
            environment: ["PATH": "."]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(result.stdout.contains("relative-path"))
        XCTAssertTrue(result.stderr.contains("updatebar-tui is not installed."))
    }

    private func writeExecutable(_ url: URL, _ body: String) throws {
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
