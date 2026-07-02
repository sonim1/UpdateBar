import ArgumentParser
import Foundation
import UpdateBarCore
#if os(Linux)
import Glibc
#else
import Darwin
#endif

func handleCLIError(_ error: Error, arguments: [String]) -> Never {
    if error is ExitCode {
        let exitCode = UpdateBar.exitCode(for: error)
        terminate(processExitCode(for: exitCode))
    }

    let exitCode = UpdateBar.exitCode(for: error)
    if exitCode == .success {
        let message = sanitizedErrorMessage(for: error)
        if !message.isEmpty {
            writeStdout(message)
        }
        terminate(0)
    }

    if requestedJSONOutput(arguments),
        !JSONOutputTracker.shared.didWrite
    {
        writeJSONError(error, code: exitCode)
        terminate(processExitCode(for: exitCode))
    }

    let message = sanitizedErrorMessage(for: error)
    if !message.isEmpty {
        writeStderr(message)
    }
    terminate(processExitCode(for: exitCode))
}

private func requestedJSONOutput(_ arguments: [String]) -> Bool {
    arguments.contains("--json") || arguments.contains("--json-stream")
        || arguments.contains(where: { $0.hasPrefix("--json=") || $0.hasPrefix("--json-stream=") })
}

private func writeJSONError(_ error: Error, code exitCode: ExitCode) {
    let message = sanitizedErrorMessage(for: error)
    let payload = ErrorEnvelope(
        ok: false,
        code: errorCode(for: error, exitCode: exitCode),
        errors: [message]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    if let data = try? encoder.encode(payload) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private func errorCode(for error: Error, exitCode: ExitCode) -> String {
    if exitCode == .validationFailure {
        return "usage_error"
    }
    if error is ValidationError {
        return "usage_error"
    }
    if error is ConfigError {
        return "config_error"
    }
    if error is RegistryError {
        return "registry_error"
    }
    if error is DecodingError {
        return "decode_error"
    }
    return "runtime_error"
}

private func processExitCode(for exitCode: ExitCode) -> Int32 {
    exitCode == .validationFailure ? 1 : exitCode.rawValue
}

private func terminate(_ code: Int32) -> Never {
#if os(Linux)
    Glibc.exit(code)
#else
    Darwin.exit(code)
#endif
}
