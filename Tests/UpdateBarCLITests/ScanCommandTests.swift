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
            ["scan", "--json"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        let report = try JSONDecoder.updateBar.decode(
            ScanReport.self, from: Data(result.stdout.utf8))
        XCTAssertTrue(report.candidates.contains { $0.id == "brew.jq" })
        XCTAssertTrue(report.candidates.contains { $0.id == "npm.typescript" })
        let jq = try XCTUnwrap(report.candidates.first { $0.id == "brew.jq" })
        XCTAssertEqual(jq.recipe?.trust.level, .untrusted)
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
            ["scan", "--category", "cloud-devops"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("gh"))
        XCTAssertTrue(result.stdout.contains("cloud-devops"))
        XCTAssertFalse(result.stdout.contains("jq"))
    }

    func testScanHumanOutputReportsConciseDetectorErrors() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            printf 'brew exploded\\n' >&2
            exit 42
            """
        )

        let result = try CLIProcess.run(
            ["scan"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.stdout.contains("Errors"))
        XCTAssertFalse(result.stdout.contains("brew: exited 42"))
        XCTAssertFalse(result.stdout.contains("brew exploded"))
        XCTAssertTrue(result.stderr.contains("Errors"))
        XCTAssertTrue(result.stderr.contains("brew: exited 42"))
        XCTAssertTrue(result.stderr.contains("brew exploded"))
        XCTAssertFalse(result.stderr.contains("brew exploded\nbrew exploded"))
        XCTAssertFalse(result.stdout.contains("if command -v brew"))
    }

    func testScanHumanOutputRedactsDetectorErrorSecrets() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            printf 'token sk-or-v1-secret-value\\n' >&2
            exit 42
            """
        )

        let result = try CLIProcess.run(
            ["scan"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("[REDACTED]"))
        XCTAssertFalse(result.stdout.contains("sk-or-v1-secret-value"))
        XCTAssertFalse(result.stderr.contains("sk-or-v1-secret-value"))
    }

    func testScanJSONRedactsDetectorErrorSecrets() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            printf 'token sk-or-v1-secret-value\\n' >&2
            exit 42
            """
        )

        let result = try CLIProcess.run(
            ["scan", "--json"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        let report = try JSONDecoder.updateBar.decode(
            ScanReport.self, from: Data(result.stdout.utf8))
        XCTAssertTrue(report.errors.contains { $0.message.contains("[REDACTED]") })
        XCTAssertFalse(report.errors.contains { $0.message.contains("sk-or-v1-secret-value") })
    }

    func testScanHumanEmptyCategoryResultSuggestsBroaderScan() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")

        let result = try CLIProcess.run(
            ["scan", "--category", "mcp-server"],
            home: home,
            environment: ["HOME": home.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Found 0 candidate(s)"))
        XCTAssertTrue(result.stdout.contains("No candidates found for category mcp-server."))
        XCTAssertTrue(result.stdout.contains("Try updatebar scan without --category."))
        XCTAssertFalse(result.stdout.contains("Next"))
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
            ["scan", "--category", "ai-agent"],
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
            ["scan", "--json", "--category", "codex-skill"],
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

    func testScanCodexSkillsUsesIsolatedCLIProcessHome() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let skill = home.appendingPathComponent(".codex/skills/local-only")
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try "Skill instructions\n".write(
            to: skill.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let result = try CLIProcess.run(["scan", "--json", "--category", "codex-skill"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        let report = try JSONDecoder.updateBar.decode(
            ScanReport.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(report.candidates.map(\.id), ["codex_skill.local-only"])
        XCTAssertEqual(report.candidates.first?.sourceRef, "~/.codex/skills/local-only")
    }

    func testScanJSONCanScanMCPConfigs() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let config = home.appendingPathComponent(".cursor/mcp.json")
        try FileManager.default.createDirectory(
            at: config.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
            {
              "mcpServers": {
                "filesystem": {
                  "command": "npx",
                  "args": ["-y", "@modelcontextprotocol/server-filesystem"],
                  "env": { "TOKEN": "secret-token" }
                }
              }
            }
            """.write(to: config, atomically: true, encoding: .utf8)

        let result = try CLIProcess.run(
            ["scan", "--json", "--category", "mcp-server"],
            home: home,
            environment: ["HOME": home.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        let report = try JSONDecoder.updateBar.decode(
            ScanReport.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(report.candidates.map(\.id), ["mcp_config.filesystem"])
        XCTAssertEqual(report.candidates.first?.category, "mcp-server")
        XCTAssertEqual(report.candidates.first?.capability, .metadataOnly)
        XCTAssertEqual(report.candidates.first?.sourceRef, "npx")
        XCTAssertFalse(result.stdout.contains("secret-token"))
    }

    func testScanHumanOutputShowsMetadataSourceRefWithoutSecrets() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let config = home.appendingPathComponent(".cursor/mcp.json")
        try FileManager.default.createDirectory(
            at: config.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
            {
              "mcpServers": {
                "filesystem": {
                  "command": "npx",
                  "env": { "TOKEN": "secret-token" }
                }
              }
            }
            """.write(to: config, atomically: true, encoding: .utf8)

        let result = try CLIProcess.run(
            ["scan", "--category", "mcp-server"],
            home: home,
            environment: ["HOME": home.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("mcp_config.filesystem"))
        XCTAssertTrue(result.stdout.contains("npx"))
        XCTAssertFalse(result.stdout.contains("secret-token"))
    }

    func testScanHumanOutputExplainsReviewOnlyCandidatesAreNotImportable() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let config = home.appendingPathComponent(".cursor/mcp.json")
        try FileManager.default.createDirectory(
            at: config.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"mcpServers":{"filesystem":{"command":"npx"}}}"#.write(
            to: config,
            atomically: true,
            encoding: .utf8
        )

        let result = try CLIProcess.run(
            ["scan", "--category", "mcp-server"],
            home: home,
            environment: ["HOME": home.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Needs Review"))
        XCTAssertTrue(result.stdout.contains("not importable yet"))
        XCTAssertTrue(result.stdout.contains("Run updatebar scan without --category to look for importable candidates."))
        XCTAssertFalse(result.stdout.contains("updatebar init --select"))
    }

    func testScanCategoryMCPServerRunsOnlyRelevantDefaultDetector() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        let marker = home.appendingPathComponent("brew-ran")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            printf 'ran' > \(marker.path)
            exit 42
            """
        )
        let config = home.appendingPathComponent(".cursor/mcp.json")
        try FileManager.default.createDirectory(
            at: config.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"mcpServers":{"filesystem":{"command":"npx"}}}"#.write(
            to: config,
            atomically: true,
            encoding: .utf8
        )

        let result = try CLIProcess.run(
            ["scan", "--category", "mcp-server"],
            home: home,
            environment: ["HOME": home.path, "PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("mcp_config.filesystem"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
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
            ["scan"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("ITEM\tID\tCATEGORY\tSOURCE\tCAPABILITY"))
        XCTAssertTrue(result.stdout.contains("brew.gh"))
        XCTAssertTrue(result.stdout.contains("[1] gh 2.74.0\tbrew.gh\tcloud-devops\tbrew\tfull"))
        XCTAssertTrue(result.stdout.contains("Scan is read-only. Use init to choose and register items."))
        XCTAssertTrue(result.stdout.contains("updatebar init\n"))
        XCTAssertTrue(result.stdout.contains("updatebar init --select all"))
        XCTAssertFalse(result.stdout.contains("updatebar init --select brew.gh"))
        let next = try XCTUnwrap(result.stdout.range(of: "Next\nupdatebar init"))
        let needsReview = try XCTUnwrap(result.stdout.range(of: "Needs Review"))
        XCTAssertLessThan(next.lowerBound, needsReview.lowerBound)
    }

    func testScanHumanCategoryNextStepPreservesCategoryAndUsesAllSelection() throws {
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
            ["scan", "--category", "cloud-devops"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("brew.gh"))
        XCTAssertFalse(result.stdout.contains("brew.jq"))
        XCTAssertTrue(result.stdout.contains("updatebar init --category cloud-devops\n"))
        XCTAssertTrue(result.stdout.contains("updatebar init --category cloud-devops --select all"))
        XCTAssertFalse(result.stdout.contains("updatebar init\nupdatebar init --select"))
    }

    func testScanDetectorsFlagIsRemovedFromCLI() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-scan-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let result = try CLIProcess.run(
            ["scan", "--json", "--detectors", "brew"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("Unknown option '--detectors'"))
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
            ["scan", "--category", "CLOUD-devops"],
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
            ["scan", "--category", " CLOUD DEVOPS "],
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
            ["scan", "--category", "clouddevops"],
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
            ["scan", "--category", "   "],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("category must not be empty"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(result.stderr.contains("detector should not run"))
    }

    func testScanRejectsUnknownCategoryBeforeRunningDetectors() throws {
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
            ["scan", "--category", "localservice"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("localservice: unknown category"))
        XCTAssertFalse(result.stderr.contains("local-service: unknown category"))
        XCTAssertTrue(result.stderr.contains("ai-agent"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(result.stderr.contains("detector should not run"))
    }

    private func writeExecutable(_ url: URL, _ body: String) throws {
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
