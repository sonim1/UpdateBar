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

    func testCliDocsDocumentDataDirectoryEnvironmentPrecedence() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)

        XCTAssertTrue(docs.contains("`UPDATEBAR_HOME`"))
        XCTAssertTrue(docs.contains("`HOME/.updatebar`"))
        XCTAssertTrue(docs.contains("explicit test or alternate data directory"))
    }

    func testSecurityDocsListAllSecretRejectedRecipeFields() throws {
        let docs = try String(contentsOfFile: "docs/security.md", encoding: .utf8)

        for field in [
            "id",
            "name",
            "category",
            "path",
            "pin",
            "source.ref",
            "source.branch",
            "check.cmd",
            "check.file",
            "latest.cmd",
            "latest.pattern",
            "version_parse.regex",
            "update.cmd",
            "update.cwd",
        ] {
            XCTAssertTrue(docs.contains("`\(field)`"), "security docs missing \(field)")
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

    func testAddHelpDocumentsSingleItemManifestAndStdinInput() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        let result = try CLIProcess.run(["add", "--help"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("single-item manifest"))
        XCTAssertTrue(result.stdout.contains("'-' for stdin"))
    }

    func testAddHelpUsesFileValueNameForFromOption() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        let result = try CLIProcess.run(["add", "--help"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("--from <file>"))
        XCTAssertFalse(result.stdout.contains("--from <from>"))
    }

    func testEditHelpDocumentsVisualAndEditorLookup() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        let result = try CLIProcess.run(["edit", "--help"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("$VISUAL"))
        XCTAssertTrue(result.stdout.contains("$EDITOR"))
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

    func testCliDocsExplainUnknownItemIDRecovery() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)

        XCTAssertTrue(docs.contains("If an item id is not found"))
        XCTAssertTrue(docs.contains("`updatebar status`"))
    }

    func testCliDocsExplainMalformedJSONDecodeErrors() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)

        XCTAssertTrue(docs.contains("Malformed JSON"))
        XCTAssertTrue(docs.contains("`decode_error`"))
        XCTAssertTrue(docs.contains("document is not valid JSON"))
    }

    func testCliDocsDocumentJSONLContractValidityRules() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)

        XCTAssertTrue(docs.contains("`event` and `type` must match"))
        XCTAssertTrue(docs.contains("Check events never include update payload fields"))
        XCTAssertTrue(docs.contains("update events never include check payload fields"))
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
        for column in ["`FIELD`", "`STATUS`", "`COMMAND`", "`DETAIL`"] {
            XCTAssertTrue(approvalsSection.contains(column), "approvals docs missing \(column)")
        }
        XCTAssertTrue(approvalsSection.contains("Next"))
        XCTAssertTrue(approvalsSection.contains("If a command field is not found"))
        XCTAssertTrue(approvalsSection.contains("`updatebar approvals <id>`"))
    }

    func testInitHelpDocumentsSelectNumbersAndAll() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        let result = try CLIProcess.run(["init", "--help"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("numbers"))
        XCTAssertTrue(result.stdout.contains("all"))
        XCTAssertTrue(result.stdout.contains("Without --select"))
        XCTAssertTrue(result.stdout.contains("Use ids copied from `updatebar scan`"))
    }

    func testInitHelpUsesSelectionValueNameForSelectOption() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        let result = try CLIProcess.run(["init", "--help"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("--select <selection>"))
        XCTAssertFalse(result.stdout.contains("--select <select>"))
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

    func testValidateHelpDocumentsRecipeManifestAndStdinInputs() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        let result = try CLIProcess.run(["validate", "--help"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("recipe or manifest"))
        XCTAssertTrue(result.stdout.contains("'-' for stdin"))
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

    func testBackgroundDocsDocumentHumanStatusColumns() throws {
        let backgroundDocs = try String(contentsOfFile: "docs/background.md", encoding: .utf8)
        let cliDocs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)
        let backgroundInstallSection = try readmeSection(
            "### `updatebar background install",
            before: "### `updatebar background status",
            in: cliDocs
        )
        let backgroundStatusSection = try readmeSection(
            "### `updatebar background status",
            before: "### `updatebar background uninstall",
            in: cliDocs
        )
        let backgroundUninstallSection = try readmeSection(
            "### `updatebar background uninstall",
            before: "### `updatebar config",
            in: cliDocs
        )

        for column in ["`STATUS`", "`LABEL`", "`PATH`"] {
            XCTAssertTrue(backgroundDocs.contains(column), "background docs missing \(column)")
            XCTAssertTrue(backgroundInstallSection.contains(column), "cli docs missing background install \(column)")
            XCTAssertTrue(backgroundStatusSection.contains(column), "cli docs missing background status \(column)")
            XCTAssertTrue(backgroundUninstallSection.contains(column), "cli docs missing background uninstall \(column)")
        }
    }

    func testBackgroundDocsDocumentManualLaunchctlSteps() throws {
        let backgroundDocs = try String(contentsOfFile: "docs/background.md", encoding: .utf8)
        let cliDocs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)
        let backgroundInstallSection = try readmeSection(
            "### `updatebar background install",
            before: "### `updatebar background status",
            in: cliDocs
        )
        let backgroundUninstallSection = try readmeSection(
            "### `updatebar background uninstall",
            before: "### `updatebar config",
            in: cliDocs
        )

        XCTAssertTrue(backgroundDocs.contains("launchctl bootstrap gui/$(id -u)"))
        XCTAssertTrue(backgroundDocs.contains("launchctl bootout gui/$(id -u)/com.updatebar.check"))
        XCTAssertTrue(backgroundInstallSection.contains("launchctl bootstrap gui/$(id -u)"))
        XCTAssertTrue(backgroundUninstallSection.contains("launchctl bootout gui/$(id -u)/com.updatebar.check"))
    }

    func testBackgroundDocsDocumentJSONLabelField() throws {
        let backgroundDocs = try String(contentsOfFile: "docs/background.md", encoding: .utf8)
        let cliDocs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)

        XCTAssertTrue(backgroundDocs.contains("`label`"))
        XCTAssertTrue(cliDocs.contains("`label`"))
        XCTAssertTrue(backgroundDocs.contains("`installed`"))
        XCTAssertTrue(backgroundDocs.contains("`removed`"))
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

    func testCompletionDocsDescribeFocusedCommandSurface() throws {
        let docs = try String(contentsOfFile: "docs/completions.md", encoding: .utf8)

        for command in ["init", "scan", "status", "check", "update", "approvals", "help"] {
            XCTAssertTrue(docs.contains("`\(command)`"), "completion docs missing visible command \(command)")
        }
        for phrase in ["import/export", "advanced item-management", "background/configuration", "support commands"] {
            XCTAssertTrue(docs.contains(phrase), "completion docs missing hidden command category \(phrase)")
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
        XCTAssertTrue(
            initSection.contains("`updatebar init --select all --json`"),
            "init docs should show the headless add-all form"
        )
        XCTAssertTrue(
            initSection.contains("`all` must be used by itself"),
            "init docs should explain that all cannot be combined with explicit selections"
        )
        XCTAssertTrue(
            initSection.contains("If a selected id is not found"),
            "init docs should explain invalid selected id recovery"
        )
        XCTAssertTrue(
            initSection.contains("rerun `updatebar scan"),
            "init docs should point invalid selected ids back to scan"
        )
        XCTAssertTrue(initSection.contains("all"), "init docs should mention all")
        for column in ["`ITEM`", "`ID`", "`CATEGORY`", "`SOURCE`"] {
            XCTAssertTrue(initSection.contains(column), "init docs missing \(column)")
        }
    }

    func testCliDocsInitDocumentsReviewOnlyScanGuidance() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)
        let scanSpec = try String(contentsOfFile: "docs/scan-init-spec.md", encoding: .utf8)
        let initSection = try readmeSection(
            "### `updatebar init",
            before: "### `updatebar import",
            in: docs
        )

        XCTAssertTrue(initSection.contains("review-only"))
        XCTAssertTrue(initSection.contains("updatebar scan --category"))
        XCTAssertTrue(initSection.contains("without `--category`"))
        XCTAssertTrue(initSection.contains("look for importable"))
        XCTAssertTrue(initSection.contains("Scan detector errors"))
        XCTAssertTrue(initSection.contains("stderr"))
        XCTAssertTrue(scanSpec.contains("updatebar scan --category"))
        XCTAssertTrue(scanSpec.contains("without `--category`"))
        XCTAssertTrue(scanSpec.contains("look for importable"))
        XCTAssertTrue(scanSpec.contains("read-only"))
        XCTAssertTrue(scanSpec.contains("choose and register"))
        XCTAssertTrue(scanSpec.contains("Scan detector errors"))
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
        XCTAssertTrue(scanSection.contains("`scan` is read-only"))
        XCTAssertTrue(scanSection.contains("choose and register"))
        XCTAssertTrue(scanSection.contains("metadata-only"))
        XCTAssertTrue(scanSection.contains("source ref"))
        XCTAssertTrue(scanSection.contains("review-only"))
        XCTAssertTrue(scanSection.contains("look for importable candidates"))
        XCTAssertTrue(scanSection.contains("`updatebar init --select all`"))
        XCTAssertTrue(scanSection.contains("preserve the same `--category` filter"))
        for column in ["`ITEM`", "`ID`", "`CATEGORY`", "`SOURCE`", "`CAPABILITY`"] {
            XCTAssertTrue(scanSection.contains(column), "scan docs missing \(column)")
        }
    }

    func testCliDocsScanDocumentsEmptyResultGuidance() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)
        let scanSpec = try String(contentsOfFile: "docs/scan-init-spec.md", encoding: .utf8)
        let scanSection = try readmeSection(
            "### `updatebar scan",
            before: "### `updatebar init",
            in: docs
        )

        XCTAssertTrue(scanSection.contains("No candidates found"))
        XCTAssertTrue(scanSection.contains("without `--category`"))
        XCTAssertTrue(scanSpec.contains("No candidates found"))
    }

    func testTUIDocsUseDirectBuildAndOverrideSetup() throws {
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let troubleshooting = try String(contentsOfFile: "docs/troubleshooting.md", encoding: .utf8)
        let tuiReadme = try String(contentsOfFile: "tui/README.md", encoding: .utf8)
        let combined = [readme, troubleshooting, tuiReadme].joined(separator: "\n")

        XCTAssertTrue(combined.contains("npm --prefix tui install"))
        XCTAssertTrue(combined.contains("npm --prefix tui run build"))
        XCTAssertTrue(combined.contains("UPDATEBAR_TUI=$PWD/tui/dist/index.js updatebar tui"))
        XCTAssertFalse(combined.contains("npm link"))
    }

    func testMenuBarTroubleshootingDocumentsInstalledAppDebugCommand() throws {
        let troubleshooting = try String(contentsOfFile: "docs/troubleshooting.md", encoding: .utf8)

        XCTAssertTrue(troubleshooting.contains("APP=${APP:-/Applications/UpdateBar.app}"))
        XCTAssertTrue(troubleshooting.contains("UPDATEBAR_BIN=\"$APP/Contents/Resources/updatebar\""))
        XCTAssertTrue(troubleshooting.contains("\"$APP/Contents/MacOS/UpdateBar\""))
        XCTAssertTrue(troubleshooting.contains("~/UpdateBar.app"))
    }

    func testTroubleshootingDocumentsHomebrewXcodeLicenseRecovery() throws {
        let troubleshooting = try String(contentsOfFile: "docs/troubleshooting.md", encoding: .utf8)

        XCTAssertTrue(troubleshooting.contains("Xcode license"))
        XCTAssertTrue(troubleshooting.contains("sudo xcodebuild -license accept"))
        XCTAssertTrue(troubleshooting.contains("brew tap sonim1/tap"))
    }

    func testTUISourceDocsRunTheLocalBuiltCLI() throws {
        let readme = try String(contentsOfFile: "README.md", encoding: .utf8)
        let tuiReadme = try String(contentsOfFile: "tui/README.md", encoding: .utf8)
        let readmeTUISection = try readmeSection("### Ink TUI", before: "## Quick Start", in: readme)
        let tuiSourceSection = try readmeSection(
            "## Run From Source",
            before: "## Install Locally",
            in: tuiReadme
        )

        for section in [readmeTUISection, tuiSourceSection] {
            XCTAssertTrue(section.contains("swift build --product updatebar"))
            XCTAssertTrue(
                section.contains(
                    "UPDATEBAR_BIN=$PWD/.build/debug/updatebar UPDATEBAR_TUI=$PWD/tui/dist/index.js .build/debug/updatebar tui"
                )
            )
            XCTAssertFalse(section.contains("UPDATEBAR_TUI=$PWD/tui/dist/index.js updatebar tui"))
        }
    }

    func testCliDocsDocumentTUICommandSetup() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)
        let tuiSection = try readmeSection(
            "### `updatebar tui",
            before: "### `updatebar schema",
            in: docs
        )

        XCTAssertTrue(tuiSection.contains("hidden from default root help"))
        XCTAssertTrue(tuiSection.contains("updatebar-tui"))
        XCTAssertTrue(tuiSection.contains("UPDATEBAR_TUI"))
        XCTAssertTrue(tuiSection.contains("tui/dist/index.js"))
        XCTAssertTrue(tuiSection.contains("npm --prefix tui run build"))
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
        for column in ["`ID`", "`STATUS`", "`CURRENT`", "`LATEST`", "`DETAIL`"] {
            XCTAssertTrue(checkSection.contains(column), "check docs missing \(column)")
        }
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
        for column in ["`ID`", "`OUTCOME`", "`CURRENT`", "`LATEST`", "`DETAIL`"] {
            XCTAssertTrue(updateSection.contains(column), "update docs missing \(column)")
        }
        XCTAssertTrue(updateSection.contains("`updatebar init`"))
        XCTAssertTrue(updateSection.contains("no items are registered"))
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

    func testScanInitSpecDocumentsHumanOutputColumns() throws {
        let spec = try String(contentsOfFile: "docs/scan-init-spec.md", encoding: .utf8)

        XCTAssertTrue(spec.contains("ITEM\tID\tCATEGORY\tSOURCE\tCAPABILITY"))
        XCTAssertTrue(spec.contains("ITEM\tID\tCATEGORY\tSOURCE"))
        XCTAssertTrue(spec.contains("[1] gh 2.74.0\tbrew.gh\tcloud-devops\tbrew"))
    }

    func testCliDocsDoNotAdvertiseUnsupportedJQVersionParse() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)

        XCTAssertFalse(docs.contains("version_parse.jq"))
    }

    func testCliDocsTemplateDocumentsSecretOverrideRejection() throws {
        let docs = try String(contentsOfFile: "docs/cli.md", encoding: .utf8)
        let recipeTemplateSection = try readmeSection(
            "### `updatebar template recipe",
            before: "### `updatebar template manifest",
            in: docs
        )
        let manifestTemplateSection = try readmeTail(
            "### `updatebar template manifest",
            in: docs
        )

        for section in [recipeTemplateSection, manifestTemplateSection] {
            XCTAssertTrue(section.contains("literal secrets"))
            XCTAssertTrue(section.contains("must match"))
            XCTAssertTrue(section.contains("^[a-z0-9][a-z0-9._-]*$"))
            XCTAssertTrue(section.contains("--id"))
            XCTAssertTrue(section.contains("--name"))
            XCTAssertTrue(section.contains("--source"))
        }
    }

    func testCurrentArchitectureMatchesReducedCLISurfaceAndMenuBarAdapter() throws {
        let architecture = try String(contentsOfFile: "current-architecture.md", encoding: .utf8)
        let cliSurface = try readmeSection(
            "## 4. Current CLI Surface",
            before: "## 5. Recipe Lifecycle",
            in: architecture
        )
        let activeSurface = try readmeSection(
            "Default root-help surface:",
            before: "Removed:",
            in: cliSurface
        )

        XCTAssertFalse(activeSurface.contains("updatebar list"))
        XCTAssertFalse(activeSurface.contains("updatebar version"))
        XCTAssertFalse(architecture.contains("updatebar update <id|--all>"))
        XCTAssertFalse(architecture.contains("thin local wrapper around CLI status/actions"))
        XCTAssertFalse(architecture.contains("never reads/writes manifest/state/config files directly"))
        XCTAssertTrue(architecture.contains("updatebar update [ids]"))
        XCTAssertTrue(architecture.contains("direct UpdateBarCore adapter by default"))
        XCTAssertTrue(architecture.contains("UPDATEBAR_MENUBAR_ADAPTER=cli"))
        XCTAssertTrue(architecture.contains("HOME/.updatebar"))
        XCTAssertTrue(architecture.contains("UPDATEBAR_HOME"))
        XCTAssertTrue(architecture.contains("updatebar list"))
        XCTAssertTrue(architecture.contains("updatebar version"))
    }

    func testMenuBarDocsMatchDataDirectoryPrecedence() throws {
        let docs = try String(contentsOfFile: "docs/menu-bar.md", encoding: .utf8)
        let nextPlan = try String(contentsOfFile: "next-plan.md", encoding: .utf8)
        let menuBarSpec = try String(
            contentsOfFile: "openspec/changes/add-ink-tui-menubar-architecture/specs/macos-menubar/spec.md",
            encoding: .utf8
        )

        XCTAssertTrue(docs.contains("HOME/.updatebar"))
        XCTAssertTrue(docs.contains("UPDATEBAR_HOME"))
        XCTAssertTrue(docs.contains("Open Config"))
        XCTAssertTrue(docs.contains("Refresh Status"))
        XCTAssertTrue(nextPlan.contains("Refresh Status"))
        XCTAssertTrue(menuBarSpec.contains("Refresh Status"))
    }

    func testTroubleshootingDocsExplainManualCorruptStoreRecovery() throws {
        let docs = try String(contentsOfFile: "docs/troubleshooting.md", encoding: .utf8)

        XCTAssertTrue(docs.contains("Corrupt Store Files"))
        XCTAssertTrue(docs.contains("state.json"))
        XCTAssertTrue(docs.contains("manifest.json"))
        XCTAssertTrue(docs.contains("updatebar check"))
        XCTAssertTrue(docs.contains("updatebar validate"))
        XCTAssertTrue(docs.contains("updatebar import"))
        XCTAssertTrue(docs.contains("Make a backup"))
    }

    func testNextPlanDoesNotRecommendDeletingCorruptState() throws {
        let plan = try String(contentsOfFile: "next-plan.md", encoding: .utf8)

        XCTAssertFalse(plan.contains("delete\n  `state.json`"))
        XCTAssertTrue(plan.contains("move `state.json` aside"))
    }

    func testPlanningDocsMatchCurrentCoreOwnedMenuBarArchitecture() throws {
        let currentPlan = try String(contentsOfFile: "current-plan.md", encoding: .utf8)
        let nextPlan = try String(contentsOfFile: "next-plan.md", encoding: .utf8)

        for document in [currentPlan, nextPlan] {
            XCTAssertTrue(document.contains("UpdateBarCore is the source of truth"))
            XCTAssertTrue(document.contains("direct UpdateBarCore"))
            XCTAssertFalse(document.contains("CLI is the single writer"))
            XCTAssertFalse(document.contains("App process never writes `manifest.json`, `state.json`, or config directly"))
        }
    }

    func testCurrentPlanUsesCurrentAgentWorkflowCommands() throws {
        let plan = try String(contentsOfFile: "current-plan.md", encoding: .utf8)

        XCTAssertFalse(plan.contains("updatebar add --manual"))
        XCTAssertFalse(plan.contains("updatebar help agent"))
        XCTAssertFalse(plan.contains("updatebar help recipe"))
        XCTAssertFalse(plan.contains("updatebar trust/approve"))
        XCTAssertFalse(plan.contains("Current `--trust`"))
        XCTAssertTrue(plan.contains("updatebar guide agent"))
        XCTAssertTrue(plan.contains("updatebar guide recipe"))
        XCTAssertTrue(plan.contains("updatebar approvals <id>"))
        XCTAssertTrue(plan.contains("`add --trust` is removed"))
    }

    func testPrdIsMarkedAsHistoricalSnapshot() throws {
        let prd = try String(contentsOfFile: "PRD.md", encoding: .utf8)

        XCTAssertTrue(prd.contains("Historical PRD snapshot"))
        XCTAssertTrue(prd.contains("[`current-plan.md`](current-plan.md)"))
        XCTAssertTrue(prd.contains("[`current-architecture.md`](current-architecture.md)"))
        XCTAssertTrue(prd.contains("[`next-plan.md`](next-plan.md)"))
        XCTAssertTrue(prd.contains("Do not use this file as the source of truth for new implementation work."))
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

    private func readmeTail(_ heading: String, in readme: String) throws -> String {
        guard let start = readme.range(of: heading)?.upperBound else {
            XCTFail("README section not found: \(heading)")
            return ""
        }
        return String(readme[start...])
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
