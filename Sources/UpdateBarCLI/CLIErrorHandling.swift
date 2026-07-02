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
        for message in sanitizedErrorMessages(for: error, arguments: arguments) where !message.isEmpty {
            writeStdout(message)
        }
        terminate(0)
    }

    if requestedJSONOutput(arguments),
        !JSONOutputTracker.shared.didWrite
    {
        writeJSONError(error, code: exitCode, arguments: arguments)
        terminate(processExitCode(for: exitCode))
    }

    for message in sanitizedErrorMessages(for: error, arguments: arguments) where !message.isEmpty {
        writeStderr(message)
    }
    terminate(processExitCode(for: exitCode))
}

private func requestedJSONOutput(_ arguments: [String]) -> Bool {
    arguments.contains("--json") || arguments.contains("--json-stream")
        || arguments.contains(where: { $0.hasPrefix("--json=") || $0.hasPrefix("--json-stream=") })
}

private func writeJSONError(_ error: Error, code exitCode: ExitCode, arguments: [String]) {
    let payload = ErrorEnvelope(
        ok: false,
        code: errorCode(for: error, exitCode: exitCode),
        errors: sanitizedErrorMessages(for: error, arguments: arguments)
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
    if error is DecodingError || isJSONSyntaxError(error) {
        return "decode_error"
    }
    return "runtime_error"
}

private func sanitizedErrorMessages(for error: Error, arguments: [String]) -> [String] {
    let message = sanitizedErrorMessage(for: error)
    let messages = message.isEmpty ? [] : [message]
    guard let recoveryHint = recoveryHint(for: error, arguments: arguments) else {
        return messages
    }
    return messages + [recoveryHint]
}

private func recoveryHint(for error: Error, arguments: [String]) -> String? {
    switch error {
    case RegistryError.itemNotFound:
        return "Run updatebar status to list registered item ids."
    case RegistryError.commandFieldNotFound:
        guard let id = approvalCommandID(from: arguments) else {
            return nil
        }
        return "Run updatebar approvals \(id) to review command fields."
    default:
        return nil
    }
}

private func approvalCommandID(from arguments: [String]) -> String? {
    guard let command = arguments.first,
          command == "approve" || command == "revoke"
    else {
        return nil
    }

    var index = 1
    while index < arguments.count {
        let argument = arguments[index]
        if argument == "--field" {
            index += 2
            continue
        }
        if argument.hasPrefix("--field=") || argument == "--json" {
            index += 1
            continue
        }
        if argument.hasPrefix("-") {
            index += 1
            continue
        }
        return argument
    }
    return nil
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
