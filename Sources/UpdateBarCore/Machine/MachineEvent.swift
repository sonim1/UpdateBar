import Foundation

public struct MachineEvent: Codable, Equatable {
    public var event: MachineEventType
    public var operation: MachineOperation
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
        case operation
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
