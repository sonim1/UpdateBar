import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class ScanServiceTests: XCTestCase {
    func testBrewScanCommandUsesManuallyInstalledLeaves() {
        XCTAssertTrue(ScanService.brewListCommand.contains("brew leaves --installed-on-request"))
        XCTAssertTrue(
            ScanService.brewListCommand.contains("brew list --formula --versions $leaves"))
        XCTAssertFalse(ScanService.brewListCommand.contains("brew list --formula --versions;"))
    }

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

    func testKnownToolsAreDedupedWhenManagerNamesAreVersionedOrScoped() throws {
        let commands = MockCommandExecutor(results: [
            ScanService.brewListCommand: CommandResult(
                exitCode: 0, stdout: "node@22 22.22.0\n", stderr: ""),
            ScanService.npmGlobalListCommand: CommandResult(
                exitCode: 0,
                stdout: #"{"dependencies":{"@openai/codex":{"version":"0.140.0"}}}"#,
                stderr: ""
            ),
            ScanService.knownToolsCommand: CommandResult(
                exitCode: 0,
                stdout: "node\tv22.22.2\ncodex\t0.140.0\nrtk\trtk 0.9.0\n",
                stderr: ""
            ),
        ])
        let service = ScanService(commandRunner: commands)

        let report = try service.scan(detectors: [.brew, .npmGlobal, .known])

        XCTAssertNotNil(report.candidates.first { $0.id == "brew.node22" })
        XCTAssertNotNil(report.candidates.first { $0.id == "npm.openai.codex" })
        XCTAssertNil(report.candidates.first { $0.id == "known.node" })
        XCTAssertNil(report.candidates.first { $0.id == "known.codex" })
        XCTAssertNotNil(report.candidates.first { $0.id == "known.rtk" })
    }

    func testScanDeduplicatesRepeatedManagerOutputByID() throws {
        let commands = MockCommandExecutor(results: [
            ScanService.brewListCommand: CommandResult(
                exitCode: 0,
                stdout: "gh 2.74.0\ngh 2.74.0\n",
                stderr: ""
            ),
        ])
        let service = ScanService(commandRunner: commands)

        let report = try service.scan(detectors: [.brew])

        XCTAssertEqual(report.candidates.map(\.id), ["brew.gh"])
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

    func testScanParsesCodexSkillDirectoriesAsMetadataOnlyCandidates() throws {
        let home = try temporaryHome(prefix: "updatebar-core-scan-tests")
        try writeSkill(named: "openspec-propose", under: ".codex/skills", home: home)
        try writeSkill(named: "gstack-review", under: ".agents/skills", home: home)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codex/skills/not-a-skill"),
            withIntermediateDirectories: true
        )
        let service = ScanService(
            commandRunner: MockCommandExecutor(results: [:]),
            homeDirectory: home
        )

        let report = try service.scan(detectors: [.codexSkill])

        XCTAssertEqual(report.errors, [])
        XCTAssertEqual(
            report.candidates.map(\.id),
            ["codex_skill.gstack-review", "codex_skill.openspec-propose"]
        )
        let skill = try XCTUnwrap(
            report.candidates.first { $0.id == "codex_skill.openspec-propose" })
        XCTAssertEqual(skill.category, "codex-skill")
        XCTAssertEqual(skill.capability, .metadataOnly)
        XCTAssertEqual(skill.confidence, .high)
        XCTAssertEqual(skill.sourceRef, "~/.codex/skills/openspec-propose")
        XCTAssertNil(skill.recipe)
    }

    func testScanParsesMCPConfigsAsMetadataOnlyCandidatesWithoutEnvValues() throws {
        let home = try temporaryHome(prefix: "updatebar-core-scan-tests")
        try writeText(
            """
            {
              "mcpServers": {
                "filesystem": {
                  "command": "npx",
                  "args": ["-y", "@modelcontextprotocol/server-filesystem"],
                  "env": { "TOKEN": "secret-token" }
                }
              }
            }
            """,
            to: ".cursor/mcp.json",
            home: home
        )
        try writeText(
            """
            [mcp_servers.github]
            command = "gh-mcp"
            args = ["stdio"]

            [mcp_servers.github.env]
            env_token = "secret-token"
            """,
            to: ".codex/config.toml",
            home: home
        )
        let service = ScanService(
            commandRunner: MockCommandExecutor(results: [:]),
            homeDirectory: home
        )

        let report = try service.scan(detectors: [.mcpConfig])

        XCTAssertEqual(report.errors, [])
        XCTAssertEqual(
            report.candidates.map(\.id),
            ["mcp_config.filesystem", "mcp_config.github"]
        )
        let filesystem = try XCTUnwrap(
            report.candidates.first { $0.id == "mcp_config.filesystem" })
        XCTAssertEqual(filesystem.category, "mcp-server")
        XCTAssertEqual(filesystem.capability, .metadataOnly)
        XCTAssertEqual(filesystem.confidence, .medium)
        XCTAssertEqual(filesystem.sourceRef, "npx")
        XCTAssertNil(filesystem.recipe)
        XCTAssertFalse(report.candidates.description.contains("secret-token"))
    }

    private func category(_ id: String, in report: ScanReport) throws -> String {
        try XCTUnwrap(report.candidates.first { $0.id == id }).category
    }

    private func writeSkill(named name: String, under root: String, home: URL) throws {
        let directory = home.appendingPathComponent(root).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "Skill instructions\n".write(
            to: directory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeText(_ text: String, to relativePath: String, home: URL) throws {
        let url = relativePath.split(separator: "/").reduce(home) { partial, component in
            partial.appendingPathComponent(String(component))
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func temporaryHome(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
