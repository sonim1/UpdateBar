import Foundation
import UpdateBarCore

public struct HistoryLogRow: Equatable {
    public let date: Date
    public let title: String
    public let detail: String

    public init(date: Date, title: String, detail: String) {
        self.date = date
        self.title = title
        self.detail = detail
    }
}

public enum HistoryLogPresentation {
    public static func rows(from events: [HistoryEvent]) -> [HistoryLogRow] {
        events
            .sorted { $0.at > $1.at }
            .map(row(from:))
    }

    private static func row(from event: HistoryEvent) -> HistoryLogRow {
        switch event.event {
        case .updateFinished:
            return HistoryLogRow(
                date: event.at,
                title: "\(event.id ?? "Update") \(event.outcome ?? "finished")",
                detail: versionDetail(from: event)
            )
        case .checkFinished:
            let outcome = event.outcome ?? "finished"
            return HistoryLogRow(
                date: event.at,
                title: "Check \(outcome)",
                detail: checkDetail(outdated: event.outdated)
            )
        }
    }

    private static func versionDetail(from event: HistoryEvent) -> String {
        guard let from = event.from, let to = event.to else {
            return "No version details"
        }
        return "\(from) → \(to)"
    }

    private static func checkDetail(outdated: Int?) -> String {
        guard let outdated else { return "No update count recorded" }
        return "\(outdated) \(outdated == 1 ? "update" : "updates") available"
    }
}
