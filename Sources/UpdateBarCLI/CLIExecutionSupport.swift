import Foundation
import UpdateBarCore
#if os(Linux)
import Glibc
#else
import Darwin
#endif

func ensureJSONModeCompatibility(json: Bool, jsonStream: Bool) throws {
    guard !(json && jsonStream) else {
        throw ValidationError("--json and --json-stream cannot be combined")
    }
}

func withCancellationToken<T>(
    _ body: (CancellationToken) throws -> T
) throws -> T {
    let cancellationToken = CancellationToken()
    let signalHandler = SignalCancellationHandler(token: cancellationToken)
    defer { signalHandler.cancel() }
    return try body(cancellationToken)
}

func readPromptedLine(_ prompt: String, trailingSpace: Bool = true) -> String? {
    writePrompt(prompt, trailingSpace: trailingSpace)
    guard let line = readLine() else {
        writeStderr("")
        return nil
    }
    if line.isEmpty {
        closePromptLineForPipedInput()
    }
    return line
}

func readYes(_ prompt: String) -> Bool {
    guard let line = readPromptedLine(prompt) else {
        return false
    }
    guard line == "yes" else {
        if !line.isEmpty {
            closePromptLineForPipedInput()
        }
        return false
    }
    return true
}

func requireYes(prompt: String, cancelMessage: String, interactive: Bool = true) throws {
    guard interactive else {
        throw ValidationError(cancelMessage)
    }
    guard readYes(prompt) else {
        throw ValidationError(cancelMessage)
    }
}

func resolveExecutable(_ value: String, environment: [String: String]) -> String? {
    if value.contains("/"), FileManager.default.isExecutableFile(atPath: value) {
        return value
    }
    let pathValue = environment["PATH"] ?? ""
    let pathEntries = pathValue.split(separator: ":").map(String.init)
    for path in pathEntries {
        if path.isEmpty { continue }
        guard (path as NSString).isAbsolutePath else { continue }
        let candidate = URL(fileURLWithPath: path).appendingPathComponent(value).path
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

private func closePromptLineForPipedInput() {
    guard !standardInputIsTTY() else {
        return
    }
    writeStderr("")
}

func standardInputIsTTY() -> Bool {
#if os(Linux)
    Glibc.isatty(STDIN_FILENO) == 1
#else
    Darwin.isatty(STDIN_FILENO) == 1
#endif
}

private final class SignalCancellationHandler {
    private var sources: [DispatchSourceSignal] = []

    init(token: CancellationToken) {
        for signalNumber in [SIGINT, SIGTERM] {
            Self.ignore(signalNumber)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
            source.setEventHandler {
                token.cancel()
            }
            source.resume()
            sources.append(source)
        }
    }

    func cancel() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
    }

    private static func ignore(_ signalNumber: Int32) {
#if os(Linux)
        Glibc.signal(signalNumber, SIG_IGN)
#else
        Darwin.signal(signalNumber, SIG_IGN)
#endif
    }
}
