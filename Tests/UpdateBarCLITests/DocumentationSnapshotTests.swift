import XCTest

final class DocumentationSnapshotTests: XCTestCase {
    func testRootHelpShowsPrimaryWorkflowCommandsOnly() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        let result = try CLIProcess.run(["--help"], home: home)
        let output = result.stdout

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        for command in ["init", "scan", "check", "status", "update", "approvals"] {
            XCTAssertTrue(output.contains(command), "missing \(command)")
        }
        let helpLines = output.split(separator: "\n").map(String.init)
        for command in ["add", "import", "export", "background", "config", "guide", "schema", "template", "validate", "tui"] {
            XCTAssertFalse(helpShowsCommand(command, in: helpLines), "support command should be hidden: \(command)")
        }
        for command in ["approve", "revoke", "pin", "unpin", "enable", "disable", "remove", "edit"] {
            XCTAssertFalse(helpShowsCommand(command, in: helpLines), "advanced manage command should be hidden: \(command)")
        }
        for section in ["SETUP SUBCOMMANDS:", "CHECK & UPDATE SUBCOMMANDS:", "MANAGE SUBCOMMANDS:"] {
            XCTAssertTrue(output.contains(section), "missing section \(section)")
        }
        XCTAssertFalse(output.contains("SYSTEM SUBCOMMANDS:"), "system commands should be hidden from root help")
    }

    func testRootHelpVisibleCommandsHaveDescriptions() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")
        let result = try CLIProcess.run(["--help"], home: home)
        let helpLines = result.stdout.split(separator: "\n").map(String.init)
        let commands = ["init", "scan", "status", "check", "update", "approvals"]

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        for command in commands {
            XCTAssertTrue(helpHasDescription(for: command, in: helpLines), "visible command should have a root help description: \(command)")
        }
    }

    func testPrimaryCommandOptionsHaveHelpDescriptions() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")
        let expectedOptionsByCommand: [String: [String]] = [
            "scan": ["--json", "--category"],
            "init": ["--json", "--replace", "--select", "--category"],
            "status": ["--json"],
            "check": ["--json", "--json-stream", "--force"],
            "update": ["--yes", "--json", "--json-stream"],
            "approvals": ["--json"],
        ]

        for (command, options) in expectedOptionsByCommand {
            let result = try CLIProcess.run([command, "--help"], home: home)
            let helpLines = result.stdout.split(separator: "\n").map(String.init)

            XCTAssertEqual(result.exitCode, 0, "\(command) --help should succeed")
            XCTAssertEqual(result.stderr, "", "\(command) --help should not write stderr")
            for option in options {
                XCTAssertTrue(
                    optionHasDescription(option, in: helpLines),
                    "\(command) \(option) should have a help description"
                )
            }
            if command == "status" {
                XCTAssertFalse(
                    optionHasDescription("--refresh", in: helpLines),
                    "status --refresh is an internal state hint and should stay out of primary help"
                )
            }
            if command == "update" {
                XCTAssertFalse(
                    optionHasDescription("--all", in: helpLines),
                    "update defaults to all outdated items when ids are omitted"
                )
            }
            if ["status", "check"].contains(command) {
                XCTAssertFalse(
                    optionHasDescription("--exit-zero-on-outdated", in: helpLines),
                    "\(command) --exit-zero-on-outdated is for automation and should stay out of primary help"
                )
            }
            if ["scan", "init"].contains(command) {
                XCTAssertFalse(
                    optionHasDescription("--detectors", in: helpLines),
                    "\(command) should not expose scan-source overrides in primary help"
                )
            }
        }
    }

    func testAddHelpHidesTrustShortcut() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        let result = try CLIProcess.run(["add", "--help"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        let helpLines = result.stdout.split(separator: "\n").map(String.init)
        XCTAssertFalse(optionHasDescription("--trust", in: helpLines))
        XCTAssertFalse(optionHasDescription("--yes", in: helpLines))
    }

    func testHiddenWorkflowCommandInputsHaveHelpDescriptions() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")
        let expectedOptionsByCommand: [String: [String]] = [
            "add": ["--from", "--dry-run", "--json", "--replace"],
            "import": ["--replace", "--json"],
            "export": ["--json"],
        ]
        let expectedArgumentsByCommand: [String: [String]] = [
            "import": ["<file>"],
            "export": ["<file>"],
        ]

        for (command, options) in expectedOptionsByCommand {
            let result = try CLIProcess.run([command, "--help"], home: home)
            let helpLines = result.stdout.split(separator: "\n").map(String.init)

            XCTAssertEqual(result.exitCode, 0, "\(command) --help should succeed")
            XCTAssertEqual(result.stderr, "", "\(command) --help should not write stderr")
            for option in options {
                XCTAssertTrue(
                    optionHasDescription(option, in: helpLines),
                    "\(command) \(option) should have a help description"
                )
            }
            if command == "add" {
                XCTAssertFalse(
                    optionHasDescription("--manual", in: helpLines),
                    "add defaults to the manual wizard when --from is omitted"
                )
            }
        }

        for (command, arguments) in expectedArgumentsByCommand {
            let result = try CLIProcess.run([command, "--help"], home: home)
            let helpLines = result.stdout.split(separator: "\n").map(String.init)

            XCTAssertEqual(result.exitCode, 0, "\(command) --help should succeed")
            XCTAssertEqual(result.stderr, "", "\(command) --help should not write stderr")
            for argument in arguments {
                XCTAssertTrue(
                    optionHasDescription(argument, in: helpLines),
                    "\(command) \(argument) should have a help description"
                )
            }
        }
    }

    func testPrimaryCommandArgumentsHaveHelpDescriptions() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")
        let expectedArgumentsByCommand: [String: [String]] = [
            "approvals": ["<id>"],
            "update": ["<ids>"],
        ]

        for (command, arguments) in expectedArgumentsByCommand {
            let result = try CLIProcess.run([command, "--help"], home: home)
            let helpLines = result.stdout.split(separator: "\n").map(String.init)

            XCTAssertEqual(result.exitCode, 0, "\(command) --help should succeed")
            XCTAssertEqual(result.stderr, "", "\(command) --help should not write stderr")
            for argument in arguments {
                XCTAssertTrue(
                    optionHasDescription(argument, in: helpLines),
                    "\(command) \(argument) should have a help description"
                )
            }
        }
    }

    func testUpdateHelpDocumentsDefaultOutdatedScope() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        let rootResult = try CLIProcess.run(["--help"], home: home)
        let updateResult = try CLIProcess.run(["update", "--help"], home: home)

        XCTAssertEqual(rootResult.exitCode, 0)
        XCTAssertEqual(rootResult.stderr, "")
        XCTAssertTrue(rootResult.stdout.contains("Run approved update commands for outdated items."))
        XCTAssertEqual(updateResult.exitCode, 0)
        XCTAssertEqual(updateResult.stderr, "")
        let normalizedUpdateHelp = updateResult.stdout.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(normalizedUpdateHelp.contains("Updates every outdated item when omitted."))
    }

    func testApprovalsHelpAndDocsExplainReviewWorkflow() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")
        let rootResult = try CLIProcess.run(["--help"], home: home)
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)
        let approvalsSection = try readmeSection(
            "### `updatebar approvals",
            before: "The direct mutation commands below",
            in: docs
        )

        XCTAssertEqual(rootResult.exitCode, 0)
        XCTAssertEqual(rootResult.stderr, "")
        XCTAssertTrue(rootResult.stdout.contains("Review command fields for approval."))
        XCTAssertTrue(approvalsSection.contains("command text"))
        XCTAssertTrue(approvalsSection.contains("Next"))
    }

    func testInitHelpDocumentsSelectNumbersAndAll() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        let result = try CLIProcess.run(["init", "--help"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("numbers"))
        XCTAssertTrue(result.stdout.contains("all"))
    }

    func testScanAndInitHelpListSupportedCategories() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        for command in ["scan", "init"] {
            let result = try CLIProcess.run([command, "--help"], home: home)

            XCTAssertEqual(result.exitCode, 0)
            XCTAssertEqual(result.stderr, "")
            XCTAssertTrue(result.stdout.contains("ai-agent"), "\(command) help missing ai-agent")
            XCTAssertTrue(result.stdout.contains("library"), "\(command) help missing library")
            XCTAssertTrue(result.stdout.contains("mcp-server"), "\(command) help missing mcp-server")
        }
    }

    func testSystemSubcommandsHaveHelpDescriptions() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")
        var expectedSubcommandsByCommand: [String: [String]] = [
            "config": ["get", "set"],
        ]
        #if os(macOS)
        expectedSubcommandsByCommand["background"] = ["install", "status", "uninstall"]
        #endif

        for (command, subcommands) in expectedSubcommandsByCommand {
            let result = try CLIProcess.run([command, "--help"], home: home)
            let helpLines = result.stdout.split(separator: "\n").map(String.init)

            XCTAssertEqual(result.exitCode, 0, "\(command) --help should succeed")
            XCTAssertEqual(result.stderr, "", "\(command) --help should not write stderr")
            for subcommand in subcommands {
                XCTAssertTrue(
                    helpHasDescription(for: subcommand, in: helpLines),
                    "\(command) \(subcommand) should have a help description"
                )
            }
        }
    }

    func testSystemSubcommandInputsHaveHelpDescriptions() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")
        var expectedOptionsByCommand: [[String]: [String]] = [
            ["config", "get"]: ["--json"],
            ["config", "set"]: ["--json"],
        ]
        #if os(macOS)
        expectedOptionsByCommand[["background", "install"]] = ["--yes", "--json"]
        expectedOptionsByCommand[["background", "status"]] = ["--json"]
        expectedOptionsByCommand[["background", "uninstall"]] = ["--json"]
        #endif
        let expectedArgumentsByCommand: [[String]: [String]] = [
            ["config", "get"]: ["<key>"],
            ["config", "set"]: ["<key>", "<value>"],
        ]

        for (commandPath, options) in expectedOptionsByCommand {
            let result = try CLIProcess.run(commandPath + ["--help"], home: home)
            let helpLines = result.stdout.split(separator: "\n").map(String.init)

            XCTAssertEqual(result.exitCode, 0, "\(commandPath.joined(separator: " ")) --help should succeed")
            XCTAssertEqual(result.stderr, "", "\(commandPath.joined(separator: " ")) --help should not write stderr")
            for option in options {
                XCTAssertTrue(
                    optionHasDescription(option, in: helpLines),
                    "\(commandPath.joined(separator: " ")) \(option) should have a help description"
                )
            }
            if commandPath == ["background", "install"] {
                XCTAssertFalse(
                    optionHasDescription("--interval-seconds", in: helpLines),
                    "background install should use refresh.interval instead of a separate interval option"
                )
            }
        }

        for (commandPath, arguments) in expectedArgumentsByCommand {
            let result = try CLIProcess.run(commandPath + ["--help"], home: home)
            let helpLines = result.stdout.split(separator: "\n").map(String.init)

            XCTAssertEqual(result.exitCode, 0, "\(commandPath.joined(separator: " ")) --help should succeed")
            XCTAssertEqual(result.stderr, "", "\(commandPath.joined(separator: " ")) --help should not write stderr")
            for argument in arguments {
                XCTAssertTrue(
                    optionHasDescription(argument, in: helpLines),
                    "\(commandPath.joined(separator: " ")) \(argument) should have a help description"
                )
            }
        }
    }

    func testSupportSubcommandsHaveHelpDescriptions() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")
        let expectedSubcommandsByCommand: [[String]: [String]] = [
            ["guide"]: ["agent", "recipe"],
            ["template"]: ["recipe", "manifest"],
        ]

        for (commandPath, subcommands) in expectedSubcommandsByCommand {
            let result = try CLIProcess.run(commandPath + ["--help"], home: home)
            let helpLines = result.stdout.split(separator: "\n").map(String.init)

            XCTAssertEqual(result.exitCode, 0, "\(commandPath.joined(separator: " ")) --help should succeed")
            XCTAssertEqual(result.stderr, "", "\(commandPath.joined(separator: " ")) --help should not write stderr")
            for subcommand in subcommands {
                XCTAssertTrue(
                    helpHasDescription(for: subcommand, in: helpLines),
                    "\(commandPath.joined(separator: " ")) \(subcommand) should have a help description"
                )
            }
        }
    }

    func testAdvancedCommandInputsHaveHelpDescriptions() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")
        let expectedOptionsByCommand: [[String]: [String]] = [
            ["approve"]: ["--field", "--json"],
            ["revoke"]: ["--field", "--json"],
            ["remove"]: ["--yes", "--json"],
            ["pin"]: ["--json"],
            ["unpin"]: ["--json"],
            ["enable"]: ["--json"],
            ["disable"]: ["--json"],
            ["validate"]: ["--json", "--explain"],
            ["template", "recipe"]: ["--kind", "--id", "--name", "--source"],
            ["template", "manifest"]: ["--kind", "--id", "--name", "--source"],
        ]
        let expectedArgumentsByCommand: [[String]: [String]] = [
            ["approve"]: ["<id>"],
            ["revoke"]: ["<id>"],
            ["remove"]: ["<id>"],
            ["pin"]: ["<id>", "<version>"],
            ["unpin"]: ["<id>"],
            ["enable"]: ["<id>"],
            ["disable"]: ["<id>"],
            ["edit"]: ["<id>"],
            ["validate"]: ["<file>"],
        ]

        for (commandPath, options) in expectedOptionsByCommand {
            let result = try CLIProcess.run(commandPath + ["--help"], home: home)
            let helpLines = result.stdout.split(separator: "\n").map(String.init)

            XCTAssertEqual(result.exitCode, 0, "\(commandPath.joined(separator: " ")) --help should succeed")
            XCTAssertEqual(result.stderr, "", "\(commandPath.joined(separator: " ")) --help should not write stderr")
            for option in options {
                XCTAssertTrue(
                    optionHasDescription(option, in: helpLines),
                    "\(commandPath.joined(separator: " ")) \(option) should have a help description"
                )
            }
        }

        for (commandPath, arguments) in expectedArgumentsByCommand {
            let result = try CLIProcess.run(commandPath + ["--help"], home: home)
            let helpLines = result.stdout.split(separator: "\n").map(String.init)

            XCTAssertEqual(result.exitCode, 0, "\(commandPath.joined(separator: " ")) --help should succeed")
            XCTAssertEqual(result.stderr, "", "\(commandPath.joined(separator: " ")) --help should not write stderr")
            for argument in arguments {
                XCTAssertTrue(
                    optionHasDescription(argument, in: helpLines),
                    "\(commandPath.joined(separator: " ")) \(argument) should have a help description"
                )
            }
        }
    }

    private func helpShowsCommand(_ command: String, in lines: [String]) -> Bool {
        lines.contains { line in
            line == "  \(command)" || line.hasPrefix("  \(command) ")
        }
    }

    private func helpHasDescription(for command: String, in lines: [String]) -> Bool {
        lines.contains { line in
            guard line.hasPrefix("  \(command)") else {
                return false
            }
            let remainder = line.dropFirst(2 + command.count)
            return remainder.trimmingCharacters(in: .whitespaces).isEmpty == false
        }
    }

    private func optionHasDescription(_ option: String, in lines: [String]) -> Bool {
        lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed == option || trimmed.hasPrefix("\(option) ") else {
                return false
            }
            guard line.count > 26 else {
                return false
            }
            let descriptionStart = line.index(line.startIndex, offsetBy: 26)
            return line[descriptionStart...].trimmingCharacters(in: .whitespaces).isEmpty == false
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
        let visibleCommands = ["init", "scan", "status", "check", "update", "approvals", "help"]
        let hiddenCommands = ["add", "import", "export", "approve", "revoke", "pin", "unpin", "enable", "disable", "remove", "edit", "background", "config", "guide", "schema", "template", "validate", "tui"]

        for shell in ["bash", "zsh", "fish"] {
            let result = try CLIProcess.run(["--generate-completion-script", shell], home: home)
            let commands = try rootCompletionCommands(from: result.stdout, shell: shell)

            XCTAssertEqual(result.exitCode, 0)
            XCTAssertEqual(result.stderr, "")
            for command in visibleCommands {
                XCTAssertTrue(commands.contains(command), "\(shell) completion missing \(command)")
            }
            for command in hiddenCommands {
                XCTAssertFalse(commands.contains(command), "\(shell) completion should hide \(command)")
            }
        }
    }

    func testReadmeQuickStartStaysFocusedOnFirstRunWorkflow() throws {
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let quickStart = try readmeSection("## Quick Start", before: "## Scope", in: readme)

        for command in ["updatebar scan", "updatebar init", "updatebar approvals <id-from-init>", "updatebar status --json", "updatebar check", "updatebar update --yes"] {
            XCTAssertTrue(quickStart.contains(command), "README Quick Start missing \(command)")
        }
        XCTAssertTrue(quickStart.contains("<candidate-id-from-scan>"))
        XCTAssertFalse(quickStart.contains("number-from-scan"))

        XCTAssertFalse(quickStart.contains("cat > recipe.json"), "README Quick Start should not inline a full recipe")
        XCTAssertFalse(quickStart.contains("updatebar approve <id-from-init>"), "README Quick Start should not lead with advanced approval commands")
        XCTAssertFalse(quickStart.contains("--exit-zero-on-outdated"), "README Quick Start should not lead with hidden automation flags")
        XCTAssertFalse(quickStart.contains("updatebar list"), "README Quick Start should not mention the removed list command")
        XCTAssertLessThanOrEqual(quickStart.split(separator: "\n").count, 35, "README Quick Start should stay short enough to scan")
    }

    func testCliDocsInitSelectMatchesHeadlessSelectionContract() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)
        let initSection = try readmeSection(
            "### `updatebar init",
            before: "### `updatebar import",
            in: docs
        )

        XCTAssertTrue(
            initSection.contains("`--select` accepts comma-separated candidate numbers or ids"),
            "init docs should mention numeric --select values"
        )
        XCTAssertTrue(
            initSection.contains("Numbers refer to the current `updatebar init` candidate list"),
            "init docs should scope numeric --select values"
        )
        XCTAssertTrue(
            initSection.contains("use ids when copying from `updatebar scan`"),
            "init docs should prefer ids for scan output"
        )
        XCTAssertTrue(initSection.contains("all"), "init docs should mention all")
    }

    func testCliDocsScanDocumentsCategoriesAndMetadataSourceRefs() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)
        let scanSection = try readmeSection(
            "### `updatebar scan",
            before: "### `updatebar init",
            in: docs
        )

        XCTAssertTrue(scanSection.contains("`ai-agent`, `package-manager`, `runtime-sdk`"))
        XCTAssertFalse(scanSection.contains("--detectors"))
        XCTAssertTrue(scanSection.contains("metadata-only"))
        XCTAssertTrue(scanSection.contains("source ref"))
    }

    func testCliDocsHideAutomationExitFlagFromPrimarySignatures() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)
        let checkSection = try readmeSection(
            "### `updatebar check",
            before: "### `updatebar status",
            in: docs
        )
        let statusSection = try readmeSection(
            "### `updatebar status",
            before: "### `updatebar update",
            in: docs
        )

        XCTAssertFalse(checkSection.split(separator: "\n").first?.contains("--exit-zero-on-outdated") ?? false)
        XCTAssertFalse(statusSection.split(separator: "\n").first?.contains("--exit-zero-on-outdated") ?? false)
    }

    func testCliDocsStatusDocumentsReadOnlyBehavior() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)
        let statusSection = try readmeSection(
            "### `updatebar status",
            before: "### `updatebar update",
            in: docs
        )

        XCTAssertTrue(statusSection.contains("does not create"))
        XCTAssertTrue(statusSection.contains("manifest.json"))
        XCTAssertTrue(statusSection.contains("state.json"))
        XCTAssertTrue(statusSection.contains("home directory"))
    }

    func testCliDocsExplainHiddenWorkflowExtensionCommands() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)

        XCTAssertTrue(docs.contains("Recipe authoring and import/export"))
        XCTAssertFalse(docs.contains("Recipe authoring, import/export, list"))
        XCTAssertFalse(docs.contains("### `updatebar list"))
        XCTAssertTrue(docs.contains("hidden from default root help and shell completions"))
    }

    func testCliDocsHideDefaultedAllFlagFromUpdateSignature() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)
        let updateSection = try readmeSection(
            "### `updatebar update",
            before: "### `updatebar approve",
            in: docs
        )

        XCTAssertFalse(updateSection.split(separator: "\n").first?.contains("--all") ?? false)
    }

    func testScanInitSpecDocumentsCurrentCategories() throws {
        let spec = try String(contentsOfFile: "docs/scan-init-spec.md", encoding: .utf8)
        let categorySection = try readmeSection(
            "## Categories",
            before: "## Capabilities",
            in: spec
        )

        for category in [
            "ai-agent", "package-manager", "runtime-sdk", "shell-utility",
            "cloud-devops", "library", "codex-skill", "mcp-server",
        ] {
            XCTAssertTrue(categorySection.contains(category), "spec missing \(category)")
        }
        XCTAssertFalse(categorySection.contains("local-service"))
        XCTAssertTrue(categorySection.contains("Unknown category values are rejected"))
    }

    func testCliDocsDoNotAdvertiseUnsupportedJQVersionParse() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)

        XCTAssertFalse(docs.contains("version_parse.jq"))
    }

    private func readmeSection(_ heading: String, before nextHeading: String, in readme: String) throws -> String {
        guard
            let start = readme.range(of: heading)?.upperBound,
            let end = readme[start...].range(of: nextHeading)?.lowerBound
        else {
            XCTFail("README section not found: \(heading)")
            return ""
        }
        return String(readme[start..<end])
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
