import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class LatestStrategyTests: XCTestCase {
    func testNPMRegistryReadsDistTagLatest() throws {
        let data = try Data(
            contentsOf: TestFixtures.fixtureURL("npm", "claude-code-registry-response.json")
        )
        let http = MockHTTPClient(responses: [
            "https://registry.npmjs.org/%40anthropic-ai%2Fclaude-code": data
        ])
        let context = LatestContext(httpClient: http, commandRunner: emptyCommands())

        let latest = try NPMRegistryLatestStrategy().latest(for: recipe(), context: context)

        XCTAssertEqual(latest, "1.5.0")
    }

    func testGitHeadUsesRemoteHeadSHA() throws {
        var item = recipe()
        item.source.kind = .git
        item.source.ref = "https://github.com/example/tool.git"
        item.source.branch = "main"
        let command = "git ls-remote -- 'https://github.com/example/tool.git' 'refs/heads/main'"
        let context = LatestContext(
            httpClient: emptyHTTP(),
            commandRunner: MockCommandExecutor(results: [
                command: CommandResult(exitCode: 0, stdout: "abc123\trefs/heads/main\n", stderr: "")
            ])
        )

        let latest = try GitLatestStrategy(mode: .head).latest(for: item, context: context)

        XCTAssertEqual(latest, "abc123")
    }

    func testGitTagsSelectsHighestSemverTag() throws {
        var item = recipe()
        item.source.kind = .git
        item.source.ref = "https://github.com/example/tool.git"
        let command = "git ls-remote --tags -- 'https://github.com/example/tool.git'"
        let context = LatestContext(
            httpClient: emptyHTTP(),
            commandRunner: MockCommandExecutor(results: [
                command: CommandResult(
                    exitCode: 0,
                    stdout:
                        "aaa\trefs/tags/v1.4.0\n"
                        + "bbb\trefs/tags/v1.5.0\n"
                        + "ccc\trefs/tags/v1.5.0^{}\n",
                    stderr: ""
                )
            ])
        )

        let latest = try GitLatestStrategy(mode: .tags).latest(for: item, context: context)

        XCTAssertEqual(latest, "1.5.0")
    }

    func testGitSourceAndBranchAreShellQuoted() throws {
        var item = recipe()
        item.source.kind = .git
        item.source.ref = "https://example.com/tool.git'; touch /tmp/pwn #"
        item.source.branch = "main'; touch /tmp/branch #"
        let command =
            "git ls-remote -- 'https://example.com/tool.git'\\''; touch /tmp/pwn #' "
            + "'refs/heads/main'\\''; touch /tmp/branch #'"
        let commands = MockCommandExecutor(results: [
            command: CommandResult(exitCode: 0, stdout: "abc123\trefs/heads/main\n", stderr: "")
        ])
        let context = LatestContext(httpClient: emptyHTTP(), commandRunner: commands)

        _ = try GitLatestStrategy(mode: .head).latest(for: item, context: context)

        XCTAssertEqual(commands.commands.map(\.command), [command])
    }

    func testGitHubReleaseReadsLatestNonDraftRelease() throws {
        var item = recipe()
        item.source.kind = .githubRelease
        item.source.ref = "owner/repo"
        let data = try Data(contentsOf: TestFixtures.fixtureURL("github", "releases.json"))
        let http = MockHTTPClient(responses: [
            "https://api.github.com/repos/owner/repo/releases": data
        ])

        let latest = try GitHubReleaseLatestStrategy().latest(
            for: item,
            context: LatestContext(httpClient: http, commandRunner: emptyCommands())
        )

        XCTAssertEqual(latest, "1.5.0")
    }

    func testBrewParsesFormulaVersion() throws {
        var item = recipe()
        item.source.kind = .brew
        item.source.ref = "ripgrep"
        let command = "brew info --json=v2 -- 'ripgrep'"
        let context = LatestContext(
            httpClient: emptyHTTP(),
            commandRunner: MockCommandExecutor(results: [
                command: CommandResult(
                    exitCode: 0,
                    stdout: #"{"formulae":[{"name":"ripgrep","versions":{"stable":"14.1.0"}}]}"#,
                    stderr: ""
                )
            ])
        )

        let latest = try BrewLatestStrategy().latest(for: item, context: context)

        XCTAssertEqual(latest, "14.1.0")
    }

    func testBrewSourceRefIsShellQuoted() throws {
        var item = recipe()
        item.source.kind = .brew
        item.source.ref = "ripgrep'; touch /tmp/pwn #"
        let command = "brew info --json=v2 -- 'ripgrep'\\''; touch /tmp/pwn #'"
        let commands = MockCommandExecutor(results: [
            command: CommandResult(
                exitCode: 0,
                stdout: #"{"formulae":[{"name":"ripgrep","versions":{"stable":"14.1.0"}}]}"#,
                stderr: ""
            )
        ])
        let context = LatestContext(httpClient: emptyHTTP(), commandRunner: commands)

        _ = try BrewLatestStrategy().latest(for: item, context: context)

        XCTAssertEqual(commands.commands.map(\.command), [command])
    }

    func testHTTPRegexExtractsVersion() throws {
        var item = recipe()
        item.source.kind = .http
        item.source.ref = "https://example.com/tool"
        item.latest.pattern = #"version: ([0-9]+\.[0-9]+\.[0-9]+)"#
        let http = MockHTTPClient(responses: [
            "https://example.com/tool": Data("version: 3.2.1".utf8)
        ])

        let latest = try HTTPLatestStrategy().latest(
            for: item,
            context: LatestContext(httpClient: http, commandRunner: emptyCommands())
        )

        XCTAssertEqual(latest, "3.2.1")
    }

    func testHTTPRegexRejectsPlainHTTPWhenHTTPSIsRequired() throws {
        var item = recipe()
        item.source.kind = .http
        item.source.ref = "http://example.com/tool"
        item.latest.pattern = #"version: ([0-9]+\.[0-9]+\.[0-9]+)"#
        let context = LatestContext(
            httpClient: emptyHTTP(),
            commandRunner: emptyCommands(),
            requireHTTPSSource: true
        )

        XCTAssertThrowsError(
            try HTTPLatestStrategy().latest(for: item, context: context)
        ) { error in
            XCTAssertEqual(
                String(describing: error),
                "http://example.com/tool: https source required"
            )
        }
    }

    func testHTTPRegexAllowsPlainHTTPWhenHTTPSIsNotRequired() throws {
        var item = recipe()
        item.source.kind = .http
        item.source.ref = "http://example.com/tool"
        item.latest.pattern = #"version: ([0-9]+\.[0-9]+\.[0-9]+)"#
        let http = MockHTTPClient(responses: [
            "http://example.com/tool": Data("version: 3.2.1".utf8)
        ])
        let context = LatestContext(
            httpClient: http,
            commandRunner: emptyCommands(),
            requireHTTPSSource: false
        )

        let latest = try HTTPLatestStrategy().latest(for: item, context: context)

        XCTAssertEqual(latest, "3.2.1")
    }

    func testHTTPRegexRejectsHTTPSDowngradeRedirect() throws {
        var item = recipe()
        item.source.kind = .http
        item.source.ref = "https://example.com/tool"
        item.latest.pattern = #"version: ([0-9]+\.[0-9]+\.[0-9]+)"#
        let http = MockHTTPClient(
            responses: ["https://example.com/tool": Data("version: 3.2.1".utf8)],
            finalURLs: ["https://example.com/tool": "http://example.com/tool"]
        )
        let context = LatestContext(
            httpClient: http,
            commandRunner: emptyCommands(),
            requireHTTPSSource: true
        )

        XCTAssertThrowsError(
            try HTTPLatestStrategy().latest(for: item, context: context)
        ) { error in
            XCTAssertEqual(
                String(describing: error),
                "http://example.com/tool: https redirect not allowed"
            )
        }
    }

    func testCmdStrategyRunsApprovedCommandAndParsesVersion() throws {
        var item = recipe()
        item.latest.strategy = .cmd
        item.latest.cmd = "tool latest"
        item.versionParse = .regex("([0-9]+\\.[0-9]+\\.[0-9]+)")
        let context = LatestContext(
            httpClient: emptyHTTP(),
            commandRunner: MockCommandExecutor(results: [
                "tool latest": CommandResult(exitCode: 0, stdout: "version 9.8.7", stderr: "")
            ])
        )

        let latest = try CommandLatestStrategy().latest(for: item, context: context)

        XCTAssertEqual(latest, "9.8.7")
    }

    private func recipe() -> Recipe {
        let data = try! Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json"))
        return try! JSONDecoder.updateBar.decode(Manifest.self, from: data).items[0]
    }

    private func emptyHTTP() -> MockHTTPClient {
        MockHTTPClient(responses: [:])
    }

    private func emptyCommands() -> MockCommandExecutor {
        MockCommandExecutor(results: [:])
    }
}
