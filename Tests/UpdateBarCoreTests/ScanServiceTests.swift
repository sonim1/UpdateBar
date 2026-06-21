import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class ScanServiceTests: XCTestCase {
    func testScanParsesBrewAndNPMGlobalCandidatesAsUntrustedRecipes() throws {
        let commands = MockCommandExecutor(results: [
            ScanService.brewListCommand: CommandResult(
                exitCode: 0,
                stdout: "jq 1.7.1\ngh 2.74.0\n",
                stderr: ""
            ),
            ScanService.npmGlobalListCommand: CommandResult(
                exitCode: 0,
                stdout: """
                    {"dependencies":{"typescript":{"version":"5.8.3"},"@anthropic-ai/claude-code":{"version":"1.0.43"}}}
                    """,
                stderr: ""
            ),
            ScanService.knownToolsCommand: CommandResult(exitCode: 0, stdout: "", stderr: ""),
        ])
        let service = ScanService(commandRunner: commands)

        let report = try service.scan(detectors: [.brew, .npmGlobal, .known])

        XCTAssertEqual(report.errors, [])
        let ids = report.candidates.map(\.id)
        XCTAssertTrue(ids.contains("brew.jq"))
        XCTAssertTrue(ids.contains("brew.gh"))
        XCTAssertTrue(ids.contains("npm.typescript"))
        XCTAssertTrue(ids.contains("npm.anthropic-ai.claude-code"))

        let jq = try XCTUnwrap(report.candidates.first { $0.id == "brew.jq" })
        XCTAssertEqual(jq.category, "shell-utility")
        XCTAssertEqual(jq.capability, .full)
        XCTAssertEqual(jq.recipe?.source.kind, .brew)
        XCTAssertEqual(jq.recipe?.trust.level, .untrusted)
        XCTAssertEqual(jq.recipe?.trust.approvedCommands, [:])

        let claude = try XCTUnwrap(
            report.candidates.first { $0.id == "npm.anthropic-ai.claude-code" })
        XCTAssertEqual(claude.category, "ai-agent")
        XCTAssertEqual(claude.detector, .npmGlobal)
        XCTAssertEqual(claude.recipe?.source.ref, "@anthropic-ai/claude-code")
        XCTAssertEqual(
            claude.recipe?.update.cmd, "npm install -g '@anthropic-ai/claude-code'@latest")
    }

    func testKnownToolsAreCheckOnlyAndDedupedWhenManagerOwned() throws {
        let commands = MockCommandExecutor(results: [
            ScanService.brewListCommand: CommandResult(
                exitCode: 0, stdout: "gh 2.74.0\n", stderr: ""),
            ScanService.npmGlobalListCommand: CommandResult(
                exitCode: 0, stdout: #"{"dependencies":{}}"#, stderr: ""),
            ScanService.knownToolsCommand: CommandResult(
                exitCode: 0,
                stdout: "gh\tgh version 2.74.0\nrtk\trtk 0.9.0\n",
                stderr: ""
            ),
        ])
        let service = ScanService(commandRunner: commands)

        let report = try service.scan(detectors: [.brew, .npmGlobal, .known])

        XCTAssertNotNil(report.candidates.first { $0.id == "brew.gh" })
        XCTAssertNil(report.candidates.first { $0.id == "known.gh" })
        let rtk = try XCTUnwrap(report.candidates.first { $0.id == "known.rtk" })
        XCTAssertEqual(rtk.category, "ai-agent")
        XCTAssertEqual(rtk.capability, .checkOnly)
        XCTAssertNil(rtk.recipe)
    }
}
