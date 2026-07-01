import XCTest

final class DocumentationSnapshotTests: XCTestCase {
    func testRootHelpShowsPrimaryWorkflowCommandsOnly() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        let result = try CLIProcess.run(["--help"], home: home)
        let output = result.stdout

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        for command in ["add", "init", "scan", "check", "status", "update", "list", "approvals"] {
            XCTAssertTrue(output.contains(command), "missing \(command)")
        }
        let helpLines = output.split(separator: "\n").map(String.init)
        for command in ["guide", "schema", "template", "validate", "tui"] {
            XCTAssertFalse(helpShowsCommand(command, in: helpLines), "support command should be hidden: \(command)")
        }
        for command in ["approve", "revoke", "pin", "unpin", "enable", "disable", "remove", "edit"] {
            XCTAssertFalse(helpShowsCommand(command, in: helpLines), "advanced manage command should be hidden: \(command)")
        }
        #if os(macOS)
        XCTAssertTrue(output.contains("\n  background"), "background command should be present on macOS")
        #else
        XCTAssertFalse(output.contains("\n  background"), "background command should not be shown on non-macOS")
        #endif
        for section in ["SETUP SUBCOMMANDS:", "CHECK & UPDATE SUBCOMMANDS:", "MANAGE SUBCOMMANDS:", "SYSTEM SUBCOMMANDS:"] {
            XCTAssertTrue(output.contains(section), "missing section \(section)")
        }
    }

    private func helpShowsCommand(_ command: String, in lines: [String]) -> Bool {
        lines.contains { line in
            line == "  \(command)" || line.hasPrefix("  \(command) ")
        }
    }

    func testGuideAgentDocumentsExitCodeTable() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        let result = try CLIProcess.run(["guide", "agent"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Exit codes:"))
        XCTAssertTrue(result.stdout.contains("1 usage/config/validation error"))
        XCTAssertTrue(result.stdout.contains("2 partial update failure"))
        XCTAssertTrue(result.stdout.contains("3 update blocked on command approval"))
        XCTAssertTrue(result.stdout.contains("10 outdated items exist for check/status"))
    }

    func testUpdateHelpDocumentsHeadlessJSONFlags() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        let result = try CLIProcess.run(["update", "--help"], home: home)
        let output = result.stdout

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(output.contains("--yes"))
        XCTAssertTrue(output.contains("--json"))
    }

    func testCompletionScriptWritesToStdoutOnly() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        let result = try CLIProcess.run(["--generate-completion-script", "bash"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("complete -o filenames -F _updatebar updatebar"))
    }

    func testCompletionScriptsExposePrimaryRootCommandsOnly() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")
        let visibleCommands = ["init", "scan", "add", "import", "export", "status", "check", "update", "list", "approvals", "config", "help"]
        let hiddenCommands = ["approve", "revoke", "pin", "unpin", "enable", "disable", "remove", "edit", "guide", "schema", "template", "validate", "tui"]

        #if os(macOS)
        let platformVisibleCommands = visibleCommands + ["background"]
        #else
        let platformVisibleCommands = visibleCommands
        #endif

        for shell in ["bash", "zsh", "fish"] {
            let result = try CLIProcess.run(["--generate-completion-script", shell], home: home)
            let commands = try rootCompletionCommands(from: result.stdout, shell: shell)

            XCTAssertEqual(result.exitCode, 0)
            XCTAssertEqual(result.stderr, "")
            for command in platformVisibleCommands {
                XCTAssertTrue(commands.contains(command), "\(shell) completion missing \(command)")
            }
            for command in hiddenCommands {
                XCTAssertFalse(commands.contains(command), "\(shell) completion should hide \(command)")
            }
        }
    }

    private func rootCompletionCommands(from script: String, shell: String) throws -> Set<String> {
        switch shell {
        case "bash":
            guard
                let line = script.split(separator: "\n").first(where: { $0.contains("compgen -W '") }),
                let start = line.range(of: "compgen -W '")?.upperBound,
                let end = line[start...].range(of: "' --")?.lowerBound
            else {
                throw XCTSkip("bash root completion list not found")
            }
            return Set(line[start..<end].split(separator: " ").map(String.init))
        case "zsh":
            var commands = Set<String>()
            var inSubcommands = false
            for line in script.split(separator: "\n").map(String.init) {
                if line.contains("local -ar subcommands=(") {
                    inSubcommands = true
                    continue
                }
                if inSubcommands && line.trimmingCharacters(in: .whitespaces) == ")" {
                    break
                }
                if inSubcommands, let firstQuote = line.firstIndex(of: "'") {
                    let contentStart = line.index(after: firstQuote)
                    if let colon = line[contentStart...].firstIndex(of: ":") {
                        commands.insert(String(line[contentStart..<colon]))
                    }
                }
            }
            return commands
        case "fish":
            let marker = #"__updatebar_should_offer_completions_for_positional "updatebar" -eq 1"#
            let commandPattern = #"-fa '"#
            let commands = script.split(separator: "\n").compactMap { rawLine -> String? in
                let line = String(rawLine)
                guard
                    line.contains(marker),
                    let start = line.range(of: commandPattern)?.upperBound,
                    let end = line[start...].range(of: "'")?.lowerBound
                else {
                    return nil
                }
                return String(line[start..<end])
            }
            return Set(commands)
        default:
            throw XCTSkip("unsupported shell: \(shell)")
        }
    }
}
