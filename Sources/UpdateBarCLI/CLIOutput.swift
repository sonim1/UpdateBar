import ArgumentParser
import Foundation
import UpdateBarCore

struct ErrorEnvelope: Encodable {
    var ok: Bool
    var code: String
    var errors: [String]
}

struct ValidationError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    JSONOutputTracker.shared.markDidWrite()
    print(String(decoding: data, as: UTF8.self))
}

func sanitizedErrorMessage(for error: Error) -> String {
    let rawMessage = UpdateBar.fullMessage(for: error).isEmpty
        ? String(describing: error)
        : UpdateBar.fullMessage(for: error)
    let normalizedMessage = rawMessage.hasPrefix("Error: ")
        ? String(rawMessage.dropFirst("Error: ".count))
        : rawMessage
    return SecretRedactor.redact(normalizedMessage)
}

func writeStderr(_ message: String, addNewline: Bool = true) {
    let value = addNewline ? "\(message)\n" : message
    FileHandle.standardError.write(Data(SecretRedactor.redact(value).utf8))
}

func writeStdout(_ message: String, addNewline: Bool = true) {
    let value = addNewline ? "\(message)\n" : message
    FileHandle.standardOutput.write(Data(SecretRedactor.redact(value).utf8))
}

func writePrompt(_ prompt: String, trailingSpace: Bool = true) {
    writeStderr(prompt + (trailingSpace ? " " : ""), addNewline: false)
}

struct JSONLWriter {
    let runID: String

    init(runID: String = UUID().uuidString) {
        self.runID = runID
    }

    func write(_ event: MachineEvent) throws {
        var event = event
        if event.runId == nil {
            event.runId = runID
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(event)
        JSONOutputTracker.shared.markDidWrite()
        print(String(decoding: data, as: UTF8.self))
    }
}

final class JSONOutputTracker: @unchecked Sendable {
    static let shared = JSONOutputTracker()
    private let lock = NSLock()
    private var wrote = false

    var didWrite: Bool {
        lock.lock()
        defer { lock.unlock() }
        return wrote
    }

    func markDidWrite() {
        lock.lock()
        wrote = true
        lock.unlock()
    }
}

func readInputData(_ path: String) throws -> Data {
    if path == "-" {
        return FileHandle.standardInput.readDataToEndOfFile()
    }
    do {
        return try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
        throw ValidationError("\(path): input file could not be read (\(error.localizedDescription))")
    }
}

func writeOutputData(_ data: Data, to path: String) throws {
    do {
        try data.write(to: URL(fileURLWithPath: path))
    } catch {
        throw ValidationError("\(path): output file could not be written (\(error.localizedDescription))")
    }
}
