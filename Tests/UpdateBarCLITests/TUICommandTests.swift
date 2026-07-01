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

    func testTUICommandResolvesFromExplicitPath() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-tui-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let tui = bin.appendingPathComponent("custom-updatebar-tui")
        try writeExecutable(
            tui,
            """
#!/bin/sh
echo "override:$UPDATEBAR_BIN"
"""
        )

        let result = try CLIProcess.run(
            ["tui"],
            home: home,
            environment: [
                "UPDATEBAR_TUI": tui.path,
                "UPDATEBAR_BIN": "/tmp/override-bin"
            ]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "override:/tmp/override-bin")
    }

    func testTUICommandReportsMissingBinary() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-tui-tests")

        let result = try CLIProcess.run(["tui"], home: home, environment: ["PATH": home.path])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("Could not locate updatebar-tui."))
    }

    func testTUICommandRejectsInvalidExplicitPath() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-tui-tests")

        let result = try CLIProcess.run(
            ["tui"],
            home: home,
            environment: ["UPDATEBAR_TUI": home.path + "/missing-binary"]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("UPDATEBAR_TUI is set to a non-existent executable"))
    }

    private func writeExecutable(_ url: URL, _ body: String) throws {
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
