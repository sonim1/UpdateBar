import UpdateBarCore
import XCTest

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

final class ExecutionPolicyTests: XCTestCase {
    func testCommandExecutorCapturesSuccessfulOutput() throws {
        let executor = CommandExecutor()
        let result = try executor.run(
            ShellCommand(command: "printf hello", cwd: nil),
            policy: ExecutionPolicy(timeout: 30, maxOutputBytes: 1024)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "hello")
        XCTAssertEqual(result.stderr, "")
    }

    func testCommandExecutorCapturesNonZeroExitAndStderr() throws {
        let executor = CommandExecutor()
        let result = try executor.run(
            ShellCommand(command: "printf nope >&2; exit 7", cwd: nil),
            policy: ExecutionPolicy(timeout: 30, maxOutputBytes: 1024)
        )

        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.stderr, "nope")
    }

    func testCommandExecutorRejectsFileWorkingDirectory() throws {
        let file = try temporaryDirectory().appendingPathComponent("not-a-directory")
        try Data("not a directory".utf8).write(to: file)
        let executor = CommandExecutor()

        XCTAssertThrowsError(
            try executor.run(
                ShellCommand(command: "pwd", cwd: file.path),
                policy: ExecutionPolicy(timeout: 30, maxOutputBytes: 1024)
            )
        ) { error in
            XCTAssertEqual(error as? ExecutionError, .invalidWorkingDirectory(file.path))
        }
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

    func testCommandExecutorCancelsRunningCommand() {
        let token = CancellationToken()
        let executor = CommandExecutor(cancellationToken: token)

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            token.cancel()
        }

        XCTAssertThrowsError(
            try executor.run(
                ShellCommand(command: "sleep 5", cwd: nil),
                policy: ExecutionPolicy(timeout: 30, maxOutputBytes: 1024)
            )
        ) { error in
            XCTAssertEqual(error as? ExecutionError, .cancelled(command: "sleep 5"))
        }
    }

    func testCommandExecutorTimeoutStopsFiniteDescendantBeforeItWrites() throws {
        let root = try temporaryDirectory()
        let marker = root.appendingPathComponent("timeout-descendant")
        let executor = CommandExecutor()
        let command =
            "(trap '' INT TERM; sleep 2; printf written > \(ShellQuote.single(marker.path))) "
            + "</dev/null >/dev/null 2>&1 & wait"
        let started = Date()

        XCTAssertThrowsError(
            try executor.run(
                ShellCommand(command: command, cwd: nil),
                policy: ExecutionPolicy(timeout: 0.05, maxOutputBytes: 1024)
            )
        ) { error in
            guard case .timedOut = error as? ExecutionError else {
                return XCTFail("expected timeout, got \(error)")
            }
        }

        Thread.sleep(forTimeInterval: max(0, 2.3 - Date().timeIntervalSince(started)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testCommandExecutorCancellationStopsFiniteDescendantBeforeItWrites() throws {
        let root = try temporaryDirectory()
        let marker = root.appendingPathComponent("cancelled-descendant")
        let token = CancellationToken()
        let executor = CommandExecutor(cancellationToken: token)
        let command =
            "(trap '' INT TERM; sleep 2; printf written > \(ShellQuote.single(marker.path))) "
            + "</dev/null >/dev/null 2>&1 & wait"
        let started = Date()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            token.cancel()
        }

        XCTAssertThrowsError(
            try executor.run(
                ShellCommand(command: command, cwd: nil),
                policy: ExecutionPolicy(timeout: 5, maxOutputBytes: 1024)
            )
        ) { error in
            guard case .cancelled = error as? ExecutionError else {
                return XCTFail("expected cancellation, got \(error)")
            }
        }

        Thread.sleep(forTimeInterval: max(0, 2.3 - Date().timeIntervalSince(started)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testCommandExecutorOwnsDistinctProcessGroup() throws {
        let running = try CommandExecutor().prepare(
            ShellCommand(command: "sleep 0.1", cwd: nil),
            policy: ExecutionPolicy(timeout: 5, maxOutputBytes: 1024)
        ).start()

        XCTAssertEqual(running.processIdentifier, running.processGroupIdentifier)
        XCTAssertNotEqual(running.processGroupIdentifier, getpgrp())
        XCTAssertEqual(try running.wait().exitCode, 0)
    }

    func testLaunchFailsClosedWhenProcessGroupIsNotOwned() throws {
        let root = try temporaryDirectory()
        let marker = root.appendingPathComponent("ownership-failure")
        let prepared = try SubprocessLifecycle.prepare(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "trap '' TERM; /bin/sleep 2; printf written > \(ShellQuote.single(marker.path))",
            ],
            environment: [:],
            timeout: 5,
            maxOutputBytes: 1024,
            cancellationToken: nil,
            commandDescription: "ownership failure fixture",
            processGroupIdentifier: { _ in
                Thread.sleep(forTimeInterval: 0.05)
                return getpgrp()
            }
        )

        XCTAssertThrowsError(try prepared.start()) { error in
            guard case .launchFailed = error as? ExecutionError else {
                return XCTFail("expected launch failure, got \(error)")
            }
        }
        Thread.sleep(forTimeInterval: 2.3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testCancellingOneCommandDoesNotStopConcurrentCommand() throws {
        let root = try temporaryDirectory()
        let cancelledMarker = root.appendingPathComponent("cancelled")
        let completedMarker = root.appendingPathComponent("completed")
        let token = CancellationToken()
        let cancelled = try CommandExecutor(cancellationToken: token).prepare(
            ShellCommand(
                command:
                    "(trap '' INT TERM; sleep 2; printf written > "
                    + "\(ShellQuote.single(cancelledMarker.path))) & wait",
                cwd: nil
            ),
            policy: ExecutionPolicy(timeout: 5, maxOutputBytes: 1024)
        ).start()
        let independent = try CommandExecutor().prepare(
            ShellCommand(
                command: "sleep 0.3; printf written > \(ShellQuote.single(completedMarker.path))",
                cwd: nil
            ),
            policy: ExecutionPolicy(timeout: 5, maxOutputBytes: 1024)
        ).start()
        XCTAssertNotEqual(cancelled.processGroupIdentifier, independent.processGroupIdentifier)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            token.cancel()
        }

        XCTAssertThrowsError(try cancelled.wait()) { error in
            guard case .cancelled = error as? ExecutionError else {
                return XCTFail("expected cancellation, got \(error)")
            }
        }
        XCTAssertEqual(try independent.wait().exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelledMarker.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: completedMarker.path))
    }

    func testExecutionErrorDescriptionsRedactSecretLikeValues() {
        let secret = "sk-or-v1-secret-value"
        let errors: [ExecutionError] = [
            .invalidWorkingDirectory("/tmp/\(secret)"),
            .timedOut(command: "printf \(secret)"),
            .launchFailed("launch \(secret)"),
            .cancelled(command: "printf \(secret)"),
        ]

        for error in errors {
            let message = String(describing: error)
            XCTAssertTrue(message.contains("[REDACTED]"), "\(error)")
            XCTAssertFalse(message.contains(secret), "\(error)")
        }
    }

    func testCommandExecutorDoesNotWaitForBackgroundChildrenAfterShellExits() throws {
        #if os(Linux)
            throw XCTSkip("Linux /bin/sh keeps background jobs attached under Foundation Process")
        #endif

        let executor = CommandExecutor()
        let started = Date()

        let result = try executor.run(
            ShellCommand(command: "sleep 3 </dev/null >/dev/null 2>&1 & printf done", cwd: nil),
            policy: ExecutionPolicy(timeout: 30, maxOutputBytes: 1024)
        )

        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "done")
    }

    func testCommandExecutorScrubsProviderSecretsFromEnvironment() throws {
        let executor = CommandExecutor(environment: [
            "OPENROUTER_API_KEY": "sk-or-v1-secret", "SAFE": "ok",
        ])
        let result = try executor.run(
            ShellCommand(
                command: "printf ${OPENROUTER_API_KEY:-missing}:${SAFE:-missing}", cwd: nil),
            policy: ExecutionPolicy(timeout: 30, maxOutputBytes: 1024)
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
            "CUSTOM_SECRET": "custom-secret",
        ])

        let result = try executor.run(
            ShellCommand(
                command:
                    "printf ${GITHUB_TOKEN:-missing}:${CUSTOM_SECRET:-missing}:${ZDOTDIR:-missing}:${PATH:+path}",
                cwd: nil
            ),
            policy: ExecutionPolicy(timeout: 30, maxOutputBytes: 1024)
        )

        XCTAssertEqual(result.stdout, "missing:missing:missing:path")
    }

    func testCommandExecutorDropsRelativePathEntries() throws {
        let root = try temporaryDirectory()
        let work = root.appendingPathComponent("work")
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(work.appendingPathComponent("tool"), body: "printf bad")
        try writeExecutable(bin.appendingPathComponent("tool"), body: "printf safe")
        let executor = CommandExecutor(environment: [
            "PATH": ".:\(bin.path)"
        ])

        let result = try executor.run(
            ShellCommand(command: "tool", cwd: work.path),
            policy: ExecutionPolicy(timeout: 30, maxOutputBytes: 1024)
        )

        XCTAssertEqual(result.stdout, "safe")
    }

    func testCommandExecutorCapsOutput() throws {
        let executor = CommandExecutor()
        let result = try executor.run(
            ShellCommand(
                command: "i=0; while [ $i -lt 200 ]; do printf x; i=$((i + 1)); done",
                cwd: nil
            ),
            policy: ExecutionPolicy(timeout: 30, maxOutputBytes: 32)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.count, 32)
    }

    func testSecretRedactorMasksKnownAPIKeyPatterns() {
        XCTAssertEqual(
            SecretRedactor.redact("token sk-or-v1-secret-value"),
            "token [REDACTED]"
        )
    }

    func testSecretRedactorMasksGitHubTokenPatternsWithoutEnvironmentKeyName() {
        for prefix in ["ghp", "gho", "ghu", "ghs", "ghr"] {
            XCTAssertEqual(
                SecretRedactor.redact(
                    "Authorization: Bearer \(prefix)_1234567890abcdefghijklmnopqrstuvwxyz"),
                "Authorization: Bearer [REDACTED]"
            )
        }
        XCTAssertEqual(
            SecretRedactor.redact("token github_pat_11ABCDEF_abcdefghijklmnopqrstuvwxyz0123456789"),
            "token [REDACTED]"
        )
    }

    func testSecretRedactorMasksCloudKeyPatternsWithoutEnvironmentKeyName() {
        XCTAssertEqual(
            SecretRedactor.redact("aws AKIAIOSFODNN7EXAMPLE"),
            "aws [REDACTED]"
        )
        XCTAssertEqual(
            SecretRedactor.redact("google AIzaSyA1234567890abcdefghijklmnopqrstuv"),
            "google [REDACTED]"
        )
    }

    func testSecretRedactorMasksPackageManagerAndCloudTokenEnvironmentNames() {
        let redacted = SecretRedactor.redact(
            "NPM_TOKEN=npm_secret HOMEBREW_GITHUB_API_TOKEN=brew-secret AWS_SECRET_ACCESS_KEY=aws-secret"
        )

        XCTAssertFalse(redacted.contains("npm_secret"))
        XCTAssertFalse(redacted.contains("brew-secret"))
        XCTAssertFalse(redacted.contains("aws-secret"))
        XCTAssertEqual(redacted, "[REDACTED] [REDACTED] [REDACTED]")
    }

    func testSecretRedactorMasksDeploymentTokenEnvironmentNames() {
        let redacted = SecretRedactor.redact(
            #"CLOUDFLARE_API_TOKEN=cf-secret CF_API_TOKEN=cf-short VERCEL_TOKEN=vercel-secret {"env":{"SUPABASE_ACCESS_TOKEN":"supabase secret"}}"#
        )

        XCTAssertFalse(redacted.contains("cf-secret"))
        XCTAssertFalse(redacted.contains("cf-short"))
        XCTAssertFalse(redacted.contains("vercel-secret"))
        XCTAssertFalse(redacted.contains("supabase secret"))
        XCTAssertEqual(redacted.components(separatedBy: "[REDACTED]").count - 1, 4)
    }

    func testSecretRedactorMasksJSONStyleTokenValues() {
        let redacted = SecretRedactor.redact(
            #"{"env":{"NPM_TOKEN":"npm-secret","AWS_SESSION_TOKEN":"aws-secret"}}"#
        )

        XCTAssertFalse(redacted.contains("npm-secret"))
        XCTAssertFalse(redacted.contains("aws-secret"))
        XCTAssertTrue(redacted.contains("[REDACTED]"))
    }

    func testSecretRedactorMasksQuotedTokenValuesWithSpaces() {
        let redacted = SecretRedactor.redact(
            #"NPM_TOKEN="npm secret" {"env":{"AWS_SESSION_TOKEN":"aws secret"}}"#
        )

        XCTAssertFalse(redacted.contains("npm secret"))
        XCTAssertFalse(redacted.contains("aws secret"))
        XCTAssertFalse(redacted.contains("secret"))
        XCTAssertEqual(redacted.components(separatedBy: "[REDACTED]").count - 1, 2)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-execution-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeExecutable(_ url: URL, body: String) throws {
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
