import Foundation
import UpdateBarCore

public enum HistoryLogTimeRange: String, CaseIterable, Equatable, Sendable {
    case all
    case lastDay
    case lastSevenDays
    case lastThirtyDays

    public var title: String {
        switch self {
        case .all: "All time"
        case .lastDay: "Last 24 hours"
        case .lastSevenDays: "Last 7 days"
        case .lastThirtyDays: "Last 30 days"
        }
    }

    fileprivate func includes(_ date: Date, now: Date) -> Bool {
        let interval: TimeInterval?
        switch self {
        case .all: interval = nil
        case .lastDay: interval = 24 * 60 * 60
        case .lastSevenDays: interval = 7 * 24 * 60 * 60
        case .lastThirtyDays: interval = 30 * 24 * 60 * 60
        }
        guard let interval else { return true }
        return date >= now.addingTimeInterval(-interval)
    }
}

public struct HistoryLogFilters: Equatable, Sendable {
    public var query: String
    public var tool: String?
    public var outcome: String?
    public var timeRange: HistoryLogTimeRange

    public init(
        query: String = "",
        tool: String? = nil,
        outcome: String? = nil,
        timeRange: HistoryLogTimeRange = .all
    ) {
        self.query = query
        self.tool = tool
        self.outcome = outcome
        self.timeRange = timeRange
    }
}

public struct HistoryLogRow: Equatable {
    public let date: Date
    public let title: String
    public let detail: String
    public let tool: String?
    public let outcome: String?
    public let failureDetail: String?

    public init(
        date: Date,
        title: String,
        detail: String,
        tool: String? = nil,
        outcome: String? = nil,
        failureDetail: String? = nil
    ) {
        self.date = date
        self.title = title
        self.detail = detail
        self.tool = tool
        self.outcome = outcome
        self.failureDetail = failureDetail
    }
}

public enum HistoryLogPresentation {
    public static func rows(from events: [HistoryEvent]) -> [HistoryLogRow] {
        rows(from: events, filters: HistoryLogFilters(), now: Date())
    }

    public static func rows(
        from events: [HistoryEvent],
        filters: HistoryLogFilters,
        now: Date
    ) -> [HistoryLogRow] {
        events
            .sorted { $0.at > $1.at }
            .map(row(from:))
            .filter { row in
                filters.timeRange.includes(row.date, now: now)
                    && (filters.tool == nil || row.tool == filters.tool)
                    && (filters.outcome == nil || row.outcome == filters.outcome)
                    && matchesQuery(row, query: filters.query)
            }
    }

    private static func row(from event: HistoryEvent) -> HistoryLogRow {
        let tool = event.id.map(SecretRedactor.redact)
        let outcome = event.outcome.map(SecretRedactor.redact)
        switch event.event {
        case .updateFinished:
            return HistoryLogRow(
                date: event.at,
                title: "\(tool ?? "Update") \(outcome ?? "finished")",
                detail: versionDetail(from: event),
                tool: tool,
                outcome: outcome,
                failureDetail: failureDetail(from: event)
            )
        case .checkFinished:
            let outcome = outcome ?? "finished"
            return HistoryLogRow(
                date: event.at,
                title: "Check \(outcome)",
                detail: checkDetail(outdated: event.outdated),
                tool: nil,
                outcome: outcome
            )
        }
    }

    private static func versionDetail(from event: HistoryEvent) -> String {
        var details: [String] = []
        if let from = event.from, let to = event.to {
            let observed = "\(SecretRedactor.redact(from)) → \(SecretRedactor.redact(to))"
            details.append(event.target == nil ? observed : "Observed: \(observed)")
        }
        if let target = event.target {
            details.append("Target: \(SecretRedactor.redact(target))")
        }
        return details.isEmpty ? "No version details" : details.joined(separator: " · ")
    }

    private static func failureDetail(from event: HistoryEvent) -> String? {
        var details: [String] = []
        if let error = event.error {
            details.append(SecretRedactor.redact(error))
        }
        if let exitCode = event.commandExitCode {
            details.append("Exit code: \(exitCode)")
        }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    private static func checkDetail(outdated: Int?) -> String {
        guard let outdated else { return "No update count recorded" }
        return "\(outdated) \(outdated == 1 ? "update" : "updates") available"
    }

    private static func matchesQuery(_ row: HistoryLogRow, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [row.title, row.detail, row.tool, row.outcome, row.failureDetail]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
