import ArgumentParser
import Foundation
import UpdateBarCore

struct UpdateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Run approved update commands for outdated items."
    )

    @Argument(help: "Item ids to update. Updates every outdated item when omitted.")
    var ids: [String] = []

    @Flag(name: .long, help: .hidden)
    var all = false

    @Flag(name: .long, help: "Run without an interactive confirmation prompt.")
    var yes = false

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    @Flag(name: .long, help: "Print newline-delimited JSON progress events.")
    var jsonStream = false

    func run() throws {
        if all, !ids.isEmpty {
            throw ValidationError("--all cannot be combined with explicit item ids")
        }

        try ensureJSONModeCompatibility(json: json, jsonStream: jsonStream)

        let config = try ConfigStore().load()
        let itemIDs = unique(ids)
        let updateAll = all || itemIDs.isEmpty
        let results: [UpdateResult] = try withCancellationToken { cancellationToken in
            let runner = UpdateRunner(
                config: config,
                commandRunner: CommandExecutor(cancellationToken: cancellationToken),
                githubToken: ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
                    ?? ProcessInfo.processInfo.environment["GH_TOKEN"],
                confirm: confirmUpdate
            )

            if jsonStream {
                try runJSONStream(runner: runner, ids: itemIDs, all: updateAll)
                return []
            }

            return try runner.update(ids: itemIDs, all: updateAll, assumeYes: yes)
        }

        if jsonStream {
            return
        }

        if json {
            try printJSON(results)
        } else {
            printHuman(results)
        }

        try enforceExitCodes(results)
    }

    private func printHuman(_ results: [UpdateResult]) {
        if results.isEmpty {
            print("No approved outdated items to update.")
            return
        }

        for result in results {
            print("\(result.id)\t\(result.outcome.rawValue)")
        }

        let blocked = results.filter { $0.outcome == .skippedUntrusted }
        let cancelled = results.filter { $0.outcome == .cancelled }
        guard !blocked.isEmpty || !cancelled.isEmpty else {
            return
        }
        var commands = blocked.map { "updatebar approvals \($0.id)" }
        if !cancelled.isEmpty {
            let ids = cancelled.map(\.id).joined(separator: " ")
            commands.append("updatebar update \(ids) --yes")
        }
        printNextCommands(commands)
    }

    private func runJSONStream(runner: UpdateRunner, ids: [String], all: Bool) throws {
        let writer = JSONLWriter()
        try writer.write(MachineEvent(
            event: .started,
            operation: .update,
            timestamp: Date()
        ))

        var results: [UpdateResult] = []
        do {
            let plan = try runner.plan(ids: ids, all: all)
            try writer.write(MachineEvent(
                event: .log,
                operation: .update,
                timestamp: Date(),
                message: "planned \(plan.count) item(s)",
                level: .info
            ))

            for item in plan {
                try writer.write(MachineEvent(
                    event: .itemStarted,
                    operation: .update,
                    timestamp: Date(),
                    itemId: item.id,
                    message: item.name
                ))
                let itemResults = try runner.update(ids: [item.id], all: false, assumeYes: yes)
                let result = itemResults.first ?? UpdateResult(
                    id: item.id,
                    name: item.name,
                    outcome: .missing,
                    current: item.current,
                    latest: item.latest,
                    error: "missing update result",
                    commandFingerprint: item.commandFingerprint
                )
                results.append(result)
                try writer.write(MachineEvent(
                    event: .itemFinished,
                    operation: .update,
                    timestamp: Date(),
                    itemId: result.id,
                    result: result
                ))
                if result.outcome == .cancelled {
                    break
                }
            }
        } catch {
            try writer.write(MachineEvent(
                event: .failed,
                operation: .update,
                timestamp: Date(),
                error: sanitizedErrorMessage(for: error)
            ))
            throw error
        }

        let report = UpdateReport(results: results)
        if results.contains(where: { $0.outcome == .cancelled }) {
            try writer.write(MachineEvent(
                event: .cancelled,
                operation: .update,
                timestamp: Date(),
                summary: report.summary,
                error: "cancelled"
            ))
        }
        try writer.write(MachineEvent(
            event: .finished,
            operation: .update,
            timestamp: Date(),
            results: report.results,
            summary: report.summary
        ))

        try enforceExitCodes(results)
    }

    private func enforceExitCodes(_ results: [UpdateResult]) throws {
        if results.contains(where: { $0.outcome.isHardFailure }) {
            throw ExitCode(2)
        }
        if results.contains(where: { $0.outcome == .skippedUntrusted }) {
            throw ExitCode(3)
        }
    }

    private func confirmUpdate(_ item: UpdatePlanItem) -> Bool {
        if json || jsonStream {
            return false
        }
        return readYes("Update \(item.id)? Type yes to continue:")
    }
}
