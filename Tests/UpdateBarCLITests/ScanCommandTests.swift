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
            if [ "$1" = "leaves" ]; then
              printf 'jq\\n'
            elif [ "$1" = "list" ]; then
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
            if [ "$1" = "leaves" ]; then
              printf 'jq\\ngh\\n'
            elif [ "$1" = "list" ]; then
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

    func testScanHumanOutputCanFilterScopedAIAgentPackages() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("npm"),
            """
            #!/bin/sh
            if [ "$1" = "ls" ]; then
              printf '{"dependencies":{"@openai/codex":{"version":"0.140.0"},"typescript":{"version":"5.8.3"}}}\\n'
            fi
            """
        )

        let result = try CLIProcess.run(
            ["scan", "--detectors", "npm_global", "--category", "ai-agent"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("@openai/codex"))
        XCTAssertTrue(result.stdout.contains("ai-agent"))
        XCTAssertFalse(result.stdout.contains("typescript"))
    }

    func testScanJSONCanScanCodexSkills() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let skill = home.appendingPathComponent(".codex/skills/openspec-propose")
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try "Skill instructions\n".write(
            to: skill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let result = try CLIProcess.run(
            ["scan", "--json", "--detectors", "codex_skill"],
            home: home,
            environment: ["HOME": home.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        let report = try JSONDecoder.updateBar.decode(
            ScanReport.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(report.candidates.map(\.id), ["codex_skill.openspec-propose"])
        XCTAssertEqual(report.candidates.first?.category, "codex-skill")
        XCTAssertEqual(report.candidates.first?.capability, .metadataOnly)
        XCTAssertNil(report.candidates.first?.recipe)
    }

    func testScanHumanOutputShowsCandidateIDsAndNextStep() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            if [ "$1" = "leaves" ]; then
              printf 'gh\\n'
            elif [ "$1" = "list" ]; then
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
        XCTAssertTrue(result.stdout.contains("updatebar init\n"))
        XCTAssertTrue(result.stdout.contains("updatebar init --select brew.gh"))
    }

    func testScanRejectsEmptyDetectorList() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")

        let result = try CLIProcess.run(["scan", "--detectors", ","], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("expected brew, npm_global, known, or codex_skill"))
    }

    func testScanAcceptsCaseInsensitiveAndDuplicateDetectors() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            if [ "$1" = "leaves" ]; then
              printf 'jq\\n'
            elif [ "$1" = "list" ]; then
              printf 'jq 1.7.1\\n'
            fi
            """
        )

        let result = try CLIProcess.run(
            ["scan", "--json", "--detectors", "BREW,brew"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        let report = try JSONDecoder.updateBar.decode(
            ScanReport.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(report.candidates.map(\.id), ["brew.jq"])
    }

    func testScanRejectsUnknownDetector() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")

        let result = try CLIProcess.run(["scan", "--detectors", "brew,foo"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("foo: unknown detector"))
    }

    func testScanAcceptsWhitespaceSeparatedDetectors() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            "#!/bin/sh\nexit 0\n"
        )
        try writeExecutable(
            bin.appendingPathComponent("npm"),
            "#!/bin/sh\nexit 0\n"
        )

        let result = try CLIProcess.run(
            ["scan", "--detectors", " brew , npm_global "],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Found 0 candidate(s)"))
    }

    func testScanFiltersCategoryCaseInsensitive() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            if [ "$1" = "leaves" ]; then
              printf 'jq\\ngh\\n'
            elif [ "$1" = "list" ]; then
              printf 'jq 1.7.1\\ngh 2.74.0\\n'
            fi
            """
        )

        let result = try CLIProcess.run(
            ["scan", "--detectors", "brew", "--category", "CLOUD-devops"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("gh"))
        XCTAssertFalse(result.stdout.contains("jq"))
    }

    func testScanFiltersCategoryWithWhitespaceAndUnderscores() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            if [ "$1" = "leaves" ]; then
              printf 'jq\\ngh\\n'
            elif [ "$1" = "list" ]; then
              printf 'jq 1.7.1\\ngh 2.74.0\\n'
            fi
            """
        )

        let result = try CLIProcess.run(
            ["scan", "--detectors", "brew", "--category", " CLOUD DEVOPS "],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("gh"))
        XCTAssertFalse(result.stdout.contains("jq"))
    }

    func testScanFiltersCategoryAliasWithoutSeparator() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            if [ "$1" = "leaves" ]; then
              printf 'jq\\ngh\\n'
            elif [ "$1" = "list" ]; then
              printf 'jq 1.7.1\\ngh 2.74.0\\n'
            fi
            """
        )

        let result = try CLIProcess.run(
            ["scan", "--detectors", "brew", "--category", "clouddevops"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("gh"))
        XCTAssertFalse(result.stdout.contains("jq"))
    }

    func testScanRejectsBlankCategoryFilter() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")

        let result = try CLIProcess.run(
            ["scan", "--category", "   "],
            home: home
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("category must not be empty"))
    }

    func testScanRejectsBlankCategoryBeforeRunningDetectors() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        let marker = home.appendingPathComponent("detector-ran")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            printf 'ran' > \(marker.path)
            printf 'detector should not run\\n' >&2
            exit 42
            """
        )

        let result = try CLIProcess.run(
            ["scan", "--detectors", "brew", "--category", "   "],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("category must not be empty"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(result.stderr.contains("detector should not run"))
    }

    private func writeExecutable(_ url: URL, _ body: String) throws {
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
