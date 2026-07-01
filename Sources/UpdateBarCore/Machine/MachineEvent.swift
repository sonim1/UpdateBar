import Foundation

public struct MachineEvent: Codable, Equatable {
    public var event: MachineEventType
    public var operation: MachineOperation
    public var runId: String?
    public var timestamp: Date
    public var itemId: String?
    public var message: String?
    public var level: MachineLogLevel?
    public var result: UpdateResult?
    public var results: [UpdateResult]?
    public var summary: UpdateSummary?
    public var checkResult: CheckResult?
    public var checkResults: [CheckResult]?
    public var checkSummary: CheckSummary?
    public var error: String?

    public init(
        event: MachineEventType,
        operation: MachineOperation,
        timestamp: Date,
        runId: String? = nil,
        itemId: String? = nil,
        message: String? = nil,
        level: MachineLogLevel? = nil,
        result: UpdateResult? = nil,
        results: [UpdateResult]? = nil,
        summary: UpdateSummary? = nil,
        checkResult: CheckResult? = nil,
        checkResults: [CheckResult]? = nil,
        checkSummary: CheckSummary? = nil,
        error: String? = nil
    ) {
        self.event = event
        self.operation = operation
        self.runId = runId
        self.timestamp = timestamp
        self.itemId = itemId
        self.message = message
        self.level = level
        self.result = result
        self.results = results
        self.summary = summary
        self.checkResult = checkResult
        self.checkResults = checkResults
        self.checkSummary = checkSummary
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case event
        case type
        case operation
        case runId = "run_id"
        case timestamp
        case itemId = "item_id"
        case message
        case level
        case result
        case results
        case summary
        case checkResult = "check_result"
        case checkResults = "check_results"
        case checkSummary = "check_summary"
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decodeIfPresent(MachineEventType.self, forKey: .event)
            ?? container.decode(MachineEventType.self, forKey: .type)
        operation = try container.decode(MachineOperation.self, forKey: .operation)
        runId = try container.decodeIfPresent(String.self, forKey: .runId)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        itemId = try container.decodeIfPresent(String.self, forKey: .itemId)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        level = try container.decodeIfPresent(MachineLogLevel.self, forKey: .level)
        result = try container.decodeIfPresent(UpdateResult.self, forKey: .result)
        results = try container.decodeIfPresent([UpdateResult].self, forKey: .results)
        summary = try container.decodeIfPresent(UpdateSummary.self, forKey: .summary)
        checkResult = try container.decodeIfPresent(CheckResult.self, forKey: .checkResult)
        checkResults = try container.decodeIfPresent([CheckResult].self, forKey: .checkResults)
        checkSummary = try container.decodeIfPresent(CheckSummary.self, forKey: .checkSummary)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(event, forKey: .event)
        try container.encode(event, forKey: .type)
        try container.encode(operation, forKey: .operation)
        try container.encodeIfPresent(runId, forKey: .runId)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(itemId, forKey: .itemId)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(level, forKey: .level)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(results, forKey: .results)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(checkResult, forKey: .checkResult)
        try container.encodeIfPresent(checkResults, forKey: .checkResults)
        try container.encodeIfPresent(checkSummary, forKey: .checkSummary)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

public enum MachineEventType: String, Codable, Equatable {
    case started
    case itemStarted = "item_started"
    case log
    case itemFinished = "item_finished"
    case cancelled
    case failed
    case finished
}

public enum MachineOperation: String, Codable, Equatable {
    case check
    case update
}

public enum MachineLogLevel: String, Codable, Equatable {
    case debug
    case info
    case warning
    case error
}
