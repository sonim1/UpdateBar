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

    func testScanCategoriesCommonVersionedAndScopedTools() throws {
        let commands = MockCommandExecutor(results: [
            ScanService.brewListCommand: CommandResult(
                exitCode: 0,
                stdout: """
                    node@22 22.22.0
                    python@3.12 3.12.13_2
                    cloudflared 2026.5.0
                    supabase 2.72.7
                    """,
                stderr: ""
            ),
            ScanService.npmGlobalListCommand: CommandResult(
                exitCode: 0,
                stdout: """
                    {"dependencies":{"@openai/codex":{"version":"0.140.0"},"@google/gemini-cli":{"version":"1.2.3"},"typescript":{"version":"5.8.3"}}}
                    """,
                stderr: ""
            ),
            ScanService.knownToolsCommand: CommandResult(exitCode: 0, stdout: "", stderr: ""),
        ])
        let service = ScanService(commandRunner: commands)

        let report = try service.scan(detectors: [.brew, .npmGlobal, .known])

        XCTAssertEqual(try category("brew.node22", in: report), "runtime-sdk")
        XCTAssertEqual(try category("brew.python3.12", in: report), "runtime-sdk")
        XCTAssertEqual(try category("brew.cloudflared", in: report), "cloud-devops")
        XCTAssertEqual(try category("brew.supabase", in: report), "cloud-devops")
        XCTAssertEqual(try category("npm.openai.codex", in: report), "ai-agent")
        XCTAssertEqual(try category("npm.google.gemini-cli", in: report), "ai-agent")
        XCTAssertEqual(try category("npm.typescript", in: report), "library")
    }

    private func category(_ id: String, in report: ScanReport) throws -> String {
        try XCTUnwrap(report.candidates.first { $0.id == id }).category
    }
}
