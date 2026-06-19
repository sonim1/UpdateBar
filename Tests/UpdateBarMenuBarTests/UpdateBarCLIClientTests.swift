import Foundation
import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class UpdateBarCLIClientTests: XCTestCase {
    func testStatusTreatsOutdatedExitCodeAsSuccessAndDecodesSnapshot() throws {
        let runner = RecordingRunner(
            result: CommandResult(
                exitCode: 10,
                stdout: """
                    {"generated_at":"2026-06-10T00:00:00Z","items":[],"summary":{"errors":0,"outdated":0,"total":0}}
                    """,
                stderr: ""
            )
        )
        let client = UpdateBarCLIClient(executablePath: "/tmp/updatebar", runner: runner)

        let snapshot = try client.status(refresh: true)

        XCTAssertEqual(snapshot.summary.total, 0)
        XCTAssertEqual(
            runner.calls,
            [
                CommandCall(
                    executablePath: "/tmp/updatebar",
                    arguments: ["status", "--json", "--exit-zero-on-outdated", "--refresh"])
            ])
    }

    func testStatusThrowsForHardFailure() {
        let runner = RecordingRunner(
            result: CommandResult(exitCode: 1, stdout: "", stderr: "bad config")
        )
        let client = UpdateBarCLIClient(executablePath: "/tmp/updatebar", runner: runner)

        XCTAssertThrowsError(try client.status(refresh: false)) { error in
            XCTAssertEqual(String(describing: error), "updatebar exited 1: bad config")
        }
    }

    func testUpdateActionsUseHeadlessJSONFlags() throws {
        let runner = RecordingRunner(result: CommandResult(exitCode: 0, stdout: "[]", stderr: ""))
        let client = UpdateBarCLIClient(executablePath: "/tmp/updatebar", runner: runner)

        try client.checkNow()
        try client.update(id: "tool")
        try client.updateAllApproved()

        XCTAssertEqual(
            runner.calls,
            [
                CommandCall(
                    executablePath: "/tmp/updatebar",
                    arguments: ["check", "--json", "--force", "--exit-zero-on-outdated"]),
                CommandCall(
                    executablePath: "/tmp/updatebar",
                    arguments: ["update", "tool", "--yes", "--json"]),
                CommandCall(
                    executablePath: "/tmp/updatebar",
                    arguments: ["update", "--all", "--yes", "--json"]),
            ])
    }

    func testUpdateActionsAllowPartialFailureExitCode() throws {
        let runner = RecordingRunner(result: CommandResult(exitCode: 2, stdout: "[]", stderr: ""))
        let client = UpdateBarCLIClient(executablePath: "/tmp/updatebar", runner: runner)

        try client.update(id: "tool")
        try client.updateAllApproved()

        XCTAssertEqual(
            runner.calls,
            [
                CommandCall(
                    executablePath: "/tmp/updatebar",
                    arguments: ["update", "tool", "--yes", "--json"]),
                CommandCall(
                    executablePath: "/tmp/updatebar",
                    arguments: ["update", "--all", "--yes", "--json"]),
            ])
    }

    func testApprovalActionsUseJSONContract() throws {
        let runner = RecordingRunner(
            result: CommandResult(
                exitCode: 0,
                stdout: """
                    [
                      {"approved":false,"field":"latest.cmd","fingerprint":"abc","command":"tool latest"},
                      {"approved":true,"field":"update.cmd","fingerprint":"def","command":"tool update","cwd":"/tmp/tool"}
                    ]
                    """,
                stderr: ""
            )
        )
        let client = UpdateBarCLIClient(executablePath: "/tmp/updatebar", runner: runner)

        let approvals = try client.approvals(id: "tool")
        try client.approve(id: "tool", field: "update.cmd")
        try client.revoke(id: "tool", field: "update.cmd")

        XCTAssertEqual(approvals.map(\.field), ["latest.cmd", "update.cmd"])
        XCTAssertEqual(approvals.map(\.approved), [false, true])
        XCTAssertEqual(approvals.map(\.command), ["tool latest", "tool update"])
        XCTAssertEqual(approvals.map(\.cwd), [nil, "/tmp/tool"])
        XCTAssertEqual(
            runner.calls,
            [
                CommandCall(
                    executablePath: "/tmp/updatebar", arguments: ["approvals", "tool", "--json"]),
                CommandCall(
                    executablePath: "/tmp/updatebar",
                    arguments: ["approve", "tool", "--field", "update.cmd", "--json"]),
                CommandCall(
                    executablePath: "/tmp/updatebar",
                    arguments: ["revoke", "tool", "--field", "update.cmd", "--json"]),
            ])
    }

    func testProcessRunnerCapsLargeOutput() throws {
        let runner = ProcessRunner(timeout: 5, maxOutputBytes: 8)

        let result = try runner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf '1234567890abcdef'; printf 'fedcba0987654321' >&2"]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "12345678")
        XCTAssertEqual(result.stderr, "fedcba09")
    }
}

private final class RecordingRunner: UpdateBarProcessRunning, @unchecked Sendable {
    private let result: CommandResult
    private(set) var calls: [CommandCall] = []

    init(result: CommandResult) {
        self.result = result
    }

    func run(executablePath: String, arguments: [String]) throws -> CommandResult {
        calls.append(CommandCall(executablePath: executablePath, arguments: arguments))
        return result
    }
}
