import XCTest

final class DocumentationSnapshotTests: XCTestCase {
    func testRootHelpShowsPrimaryWorkflowCommandsOnly() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doc-tests")

        let result = try CLIProcess.run(["--help"], home: home)
        let output = result.stdout + result.stderr

        XCTAssertEqual(result.exitCode, 0)
        for command in ["add", "init", "scan", "check", "status", "update", "approve", "revoke"] {
            XCTAssertTrue(output.contains(command), "missing \(command)")
        }
        for command in ["guide", "schema", "template", "validate", "tui"] {
            XCTAssertFalse(output.contains("\n  \(command)"), "support command should be hidden: \(command)")
        }
        for section in ["SETUP SUBCOMMANDS:", "CHECK & UPDATE SUBCOMMANDS:", "MANAGE SUBCOMMANDS:", "SYSTEM SUBCOMMANDS:"] {
            XCTAssertTrue(output.contains(section), "missing section \(section)")
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
        let output = result.stdout + result.stderr

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(output.contains("--yes"))
        XCTAssertTrue(output.contains("--json"))
    }
}
