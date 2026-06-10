import XCTest
import UpdateBarCore

final class ExecutionPolicyTests: XCTestCase {
    func testCommandExecutorCapturesSuccessfulOutput() throws {
        let executor = CommandExecutor()
        let result = try executor.run(
            ShellCommand(command: "printf hello", cwd: nil),
            policy: ExecutionPolicy(timeout: 5, maxOutputBytes: 1024)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "hello")
        XCTAssertEqual(result.stderr, "")
    }

    func testCommandExecutorCapturesNonZeroExitAndStderr() throws {
        let executor = CommandExecutor()
        let result = try executor.run(
            ShellCommand(command: "printf nope >&2; exit 7", cwd: nil),
            policy: ExecutionPolicy(timeout: 5, maxOutputBytes: 1024)
        )

        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.stderr, "nope")
    }

    func testCommandExecutorTimesOut() {
        let executor = CommandExecutor()

        XCTAssertThrowsError(
            try executor.run(
                ShellCommand(command: "sleep 2", cwd: nil),
                policy: ExecutionPolicy(timeout: 0.1, maxOutputBytes: 1024)
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("timed out"))
        }
    }

    func testCommandExecutorScrubsProviderSecretsFromEnvironment() throws {
        let executor = CommandExecutor(environment: ["OPENROUTER_API_KEY": "sk-or-v1-secret", "SAFE": "ok"])
        let result = try executor.run(
            ShellCommand(command: "printf ${OPENROUTER_API_KEY:-missing}:${SAFE:-missing}", cwd: nil),
            policy: ExecutionPolicy(timeout: 5, maxOutputBytes: 1024)
        )

        XCTAssertEqual(result.stdout, "missing:missing")
    }

    func testCommandExecutorUsesAllowlistedEnvironmentAndDoesNotSourceShellStartupFiles() throws {
        let home = try temporaryDirectory()
        let startup = home.appendingPathComponent(".zshenv")
        try Data("export GITHUB_TOKEN=from-startup\n".utf8).write(to: startup)
        let executor = CommandExecutor(environment: [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
            "HOME": home.path,
            "ZDOTDIR": home.path,
            "GITHUB_TOKEN": "from-env",
            "CUSTOM_SECRET": "custom-secret"
        ])

        let result = try executor.run(
            ShellCommand(
                command: "printf ${GITHUB_TOKEN:-missing}:${CUSTOM_SECRET:-missing}:${ZDOTDIR:-missing}:${PATH:+path}",
                cwd: nil
            ),
            policy: ExecutionPolicy(timeout: 5, maxOutputBytes: 1024)
        )

        XCTAssertEqual(result.stdout, "missing:missing:missing:path")
    }

    func testCommandExecutorCapsOutput() throws {
        let executor = CommandExecutor()
        let result = try executor.run(
            ShellCommand(command: "python3 - <<'PY'\nprint('x' * 2000)\nPY", cwd: nil),
            policy: ExecutionPolicy(timeout: 5, maxOutputBytes: 32)
        )

        XCTAssertEqual(result.stdout.count, 32)
    }

    func testSecretRedactorMasksKnownAPIKeyPatterns() {
        XCTAssertEqual(
            SecretRedactor.redact("token sk-or-v1-secret-value"),
            "token [REDACTED]"
        )
    }

    func testSecretRedactorMasksGitHubTokenPatternsWithoutEnvironmentKeyName() {
        XCTAssertEqual(
            SecretRedactor.redact("Authorization: Bearer ghp_1234567890abcdefghijklmnopqrstuvwxyz"),
            "Authorization: Bearer [REDACTED]"
        )
        XCTAssertEqual(
            SecretRedactor.redact("token github_pat_11ABCDEF_abcdefghijklmnopqrstuvwxyz0123456789"),
            "token [REDACTED]"
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-execution-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
