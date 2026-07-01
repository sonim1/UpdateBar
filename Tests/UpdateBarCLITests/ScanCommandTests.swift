import Foundation
import UpdateBarCore
import XCTest

final class ScanCommandTests: XCTestCase {
    func testScanJSONUsesFakeManagersAndDoesNotWriteManifest() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            if [ "$1" = "list" ]; then
              printf 'jq 1.7.1\\n'
            fi
            """
        )
        try writeExecutable(
            bin.appendingPathComponent("npm"),
            """
            #!/bin/sh
            if [ "$1" = "ls" ]; then
              printf '{"dependencies":{"typescript":{"version":"5.8.3"}}}\\n'
            fi
            """
        )

        let result = try CLIProcess.run(
            ["scan", "--json", "--detectors", "brew,npm_global"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        let report = try JSONDecoder.updateBar.decode(
            ScanReport.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(report.candidates.map(\.id).sorted(), ["brew.jq", "npm.typescript"])
        XCTAssertEqual(report.candidates.first?.recipe?.trust.level, .untrusted)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: AppPaths(homeDirectory: home).manifestFile.path))
    }

    func testScanHumanOutputCanFilterCategory() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            if [ "$1" = "list" ]; then
              printf 'jq 1.7.1\\ngh 2.74.0\\n'
            fi
            """
        )

        let result = try CLIProcess.run(
            ["scan", "--detectors", "brew", "--category", "cloud-devops"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("gh"))
        XCTAssertTrue(result.stdout.contains("cloud-devops"))
        XCTAssertFalse(result.stdout.contains("jq"))
    }

    func testScanHumanOutputShowsCandidateIDsAndNextStep() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            if [ "$1" = "list" ]; then
              printf 'gh 2.74.0\\n'
            fi
            """
        )

        let result = try CLIProcess.run(
            ["scan", "--detectors", "brew"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("brew.gh"))
        XCTAssertTrue(result.stdout.contains("updatebar init --select brew.gh"))
    }

    func testScanRejectsEmptyDetectorList() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")

        let result = try CLIProcess.run(["scan", "--detectors", ","], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("expected brew, npm_global, or known"))
    }

    private func writeExecutable(_ url: URL, _ body: String) throws {
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
