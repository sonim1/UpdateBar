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
                "UPDATEBAR_BIN": "/tmp/custom-bin-from-env"
            ]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "bin:/tmp/custom-bin-from-env")
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
                "UPDATEBAR_BIN": "/tmp/override-bin"
            ]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "override:/tmp/override-bin")
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
                "UPDATEBAR_BIN": "/tmp/invalid-bin"
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("UPDATEBAR_TUI is not executable"))
    }

    func testTUICommandReportsMissingBinary() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-tui-tests")

        let result = try CLIProcess.run(["tui"], home: home, environment: ["PATH": home.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("Could not locate updatebar-tui on PATH."))
        XCTAssertTrue(result.stderr.contains("UPDATEBAR_TUI"))
        XCTAssertTrue(result.stderr.contains("npm link"))
        XCTAssertTrue(result.stderr.contains("tui"))
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
        XCTAssertTrue(result.stderr.contains("Could not locate updatebar-tui on PATH."))
    }

    private func writeExecutable(_ url: URL, _ body: String) throws {
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
