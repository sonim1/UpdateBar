import Foundation

public protocol CommandRunning {
    func run(_ command: ShellCommand, policy: ExecutionPolicy) throws -> CommandResult
}

public struct CommandExecutor: CommandRunning {
    private let environment: [String: String]
    private let fileManager: FileManager

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.fileManager = fileManager
    }

    public func run(_ command: ShellCommand, policy: ExecutionPolicy) throws -> CommandResult {
        if let cwd = command.cwd, !fileManager.fileExists(atPath: cwd) {
            throw ExecutionError.invalidWorkingDirectory(cwd)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command.command]
        if let cwd = command.cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        process.environment = scrubbedEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw ExecutionError.launchFailed(String(describing: error))
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + policy.timeout) == .timedOut {
            process.terminate()
            throw ExecutionError.timedOut(command: command.command)
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: Self.decodeAndCap(outData, limit: policy.maxOutputBytes),
            stderr: Self.decodeAndCap(errData, limit: policy.maxOutputBytes)
        )
    }

    private func scrubbedEnvironment() -> [String: String] {
        let allowedKeys = Set(["PATH", "HOME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR", "USER"])
        return environment.filter { allowedKeys.contains($0.key) }
    }

    private static func decodeAndCap(_ data: Data, limit: Int) -> String {
        let capped = data.prefix(max(0, limit))
        return String(decoding: capped, as: UTF8.self)
    }
}
