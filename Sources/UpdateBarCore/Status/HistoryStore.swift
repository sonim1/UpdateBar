import Foundation

public struct HistoryEvent: Codable, Equatable {
    public enum Kind: String, Codable, Equatable {
        case updateFinished = "update_finished"
        case checkFinished = "check_finished"
    }

    public var schemaVersion: Int
    public var event: Kind
    public var id: String?
    public var from: String?
    public var to: String?
    public var outcome: String?
    public var outdated: Int?
    public var at: Date

    public init(
        event: Kind,
        id: String? = nil,
        from: String? = nil,
        to: String? = nil,
        outcome: String? = nil,
        outdated: Int? = nil,
        at: Date
    ) {
        self.schemaVersion = 1
        self.event = event
        self.id = id.map(SecretRedactor.redact)
        self.from = from.map(SecretRedactor.redact)
        self.to = to.map(SecretRedactor.redact)
        self.outcome = outcome
        self.outdated = outdated
        self.at = at
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case event
        case id
        case from
        case to
        case outcome
        case outdated
        case at
    }
}

/// Append-only JSONL log of update/check events at
/// `~/.updatebar/history.jsonl`, size-capped by dropping the oldest lines.
/// Reads skip malformed lines so a torn write never poisons the file.
public struct HistoryStore {
    private let fileURL: URL
    private let maxBytes: Int

    public init(paths: AppPaths = AppPaths(), maxBytes: Int = 512 * 1024) {
        self.fileURL = paths.historyFile
        self.maxBytes = maxBytes
    }

    public func append(_ event: HistoryEvent) throws {
        // JSONL requires exactly one line per event; the shared updateBar
        // encoder pretty-prints, so use a compact encoder here.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let line = try encoder.encode(event) + Data("\n".utf8)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existing = (try? Data(contentsOf: fileURL)) ?? Data()
        var combined = existing + line
        if combined.count > maxBytes {
            combined = Self.trimmedToWholeLines(combined.suffix(maxBytes))
        }
        try combined.write(to: fileURL, options: .atomic)
    }

    public func events(since: Date? = nil) throws -> [HistoryEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder.updateBar
        return data.split(separator: UInt8(ascii: "\n")).compactMap { lineData in
            guard let event = try? decoder.decode(HistoryEvent.self, from: Data(lineData)) else {
                return nil
            }
            if let since, event.at < since {
                return nil
            }
            return event
        }
    }

    private static func trimmedToWholeLines(_ data: Data) -> Data {
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")) else { return data }
        return data[data.index(after: newline)...]
    }
}
