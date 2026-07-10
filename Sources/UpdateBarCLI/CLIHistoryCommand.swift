import ArgumentParser
import Foundation
import UpdateBarCore

struct HistoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Show recorded update and check events."
    )

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    @Option(name: .long, help: "Only show events at or after this ISO-8601 date-time.")
    var since: String?

    func run() throws {
        let sinceDate = try parsedSince()
        let events = try HistoryStore().events(since: sinceDate)
        if json {
            try printJSON(events)
            return
        }
        printHuman(events)
    }

    private func parsedSince() throws -> Date? {
        guard let since else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: since) {
            return date
        }
        formatter.formatOptions = [.withFullDate]
        if let date = formatter.date(from: since) {
            return date
        }
        throw ValidationError(
            "--since must be an ISO-8601 date or date-time, for example 2026-07-01 or 2026-07-01T00:00:00Z."
        )
    }

    private func printHuman(_ events: [HistoryEvent]) {
        guard !events.isEmpty else {
            writeStdout("No history recorded yet. Events appear after updates and checks run.")
            return
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        writeStdout("AT\tEVENT\tID\tDETAIL")
        for event in events {
            let detail: String
            switch event.event {
            case .updateFinished:
                let transition = [event.from, event.to].compactMap { $0 }
                    .joined(separator: " -> ")
                detail = [transition, event.outcome ?? ""].filter { !$0.isEmpty }
                    .joined(separator: " · ")
            case .checkFinished:
                detail = "\(event.outdated ?? 0) outdated"
            }
            writeStdout(
                [
                    formatter.string(from: event.at),
                    event.event.rawValue,
                    event.id ?? "-",
                    detail,
                ].joined(separator: "\t"))
        }
    }
}
