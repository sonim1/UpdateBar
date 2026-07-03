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

    func testStatusThrowsJSONErrorPayloadForHardFailure() {
        let runner = RecordingRunner(
            result: CommandResult(
                exitCode: 1,
                stdout: #"{"ok":false,"errors":["bad config from json"]}"#,
                stderr: ""
            )
        )
        let client = UpdateBarCLIClient(executablePath: "/tmp/updatebar", runner: runner)

        XCTAssertThrowsError(try client.status(refresh: false)) { error in
            XCTAssertEqual(String(describing: error), "updatebar exited 1: bad config from json")
        }
    }

    func testPrefersStructuredJSONErrorOverStderrFallback() {
        let runner = RecordingRunner(
            result: CommandResult(
                exitCode: 1,
                stdout: #"{"ok":false,"code":"usage_error","errors":["structured failure"]}"#,
                stderr: "human fallback"
            )
        )
        let client = UpdateBarCLIClient(executablePath: "/tmp/updatebar", runner: runner)

        XCTAssertThrowsError(try client.approve(id: "tool", field: "update.cmd")) { error in
            XCTAssertEqual(
                String(describing: error),
                "updatebar exited 1: structured failure"
            )
        }
    }

    func testRedactsStructuredJSONErrorDetails() {
        let runner = RecordingRunner(
            result: CommandResult(
                exitCode: 1,
                stdout: #"{"ok":false,"errors":["failed sk-or-v1-secret-value"]}"#,
                stderr: ""
            )
        )
        let client = UpdateBarCLIClient(executablePath: "/tmp/updatebar", runner: runner)

        XCTAssertThrowsError(try client.status(refresh: false)) { error in
            let message = String(describing: error)
            XCTAssertFalse(message.contains("sk-or-v1-secret-value"))
            XCTAssertTrue(message.contains("[REDACTED]"))
        }
    }

    func testRedactsStderrFallbackErrorDetails() {
        let runner = RecordingRunner(
            result: CommandResult(exitCode: 1, stdout: "", stderr: "failed sk-or-v1-secret-value")
        )
        let client = UpdateBarCLIClient(executablePath: "/tmp/updatebar", runner: runner)

        XCTAssertThrowsError(try client.status(refresh: false)) { error in
            let message = String(describing: error)
            XCTAssertFalse(message.contains("sk-or-v1-secret-value"))
            XCTAssertTrue(message.contains("[REDACTED]"))
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
                    arguments: ["update", "--yes", "--json"]),
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
                    arguments: ["update", "--yes", "--json"]),
            ])
    }

    func testUpdateActionsAllowApprovalBlockedExitCode() throws {
        let runner = RecordingRunner(result: CommandResult(exitCode: 3, stdout: "[]", stderr: ""))
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
                    arguments: ["update", "--yes", "--json"]),
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

    func testProcessRunnerCancelsRunningProcess() throws {
        let runner = ProcessRunner(timeout: 5)
        let token = CancellationToken()

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            token.cancel()
        }

        XCTAssertThrowsError(try runner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "sleep 5"],
            cancellationToken: token
        )) { error in
            XCTAssertEqual(error as? UpdateBarCLIClientError, .cancelled)
        }
    }

    func testProcessRunnerTimesOut() throws {
        let runner = ProcessRunner(timeout: 0.2)

        XCTAssertThrowsError(try runner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "sleep 5"]
        )) { error in
            XCTAssertEqual(error as? UpdateBarCLIClientError, .timedOut)
        }
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
