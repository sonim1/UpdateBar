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

func readYes(_ prompt: String) -> Bool {
    writePrompt(prompt)
    return readLine() == "yes"
}

func requireYes(prompt: String, cancelMessage: String, interactive: Bool = true) throws {
    guard interactive else {
        throw ValidationError(cancelMessage)
    }
    guard readYes(prompt) else {
        throw ValidationError(cancelMessage)
    }
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
