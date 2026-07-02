import ArgumentParser
import Foundation
import UpdateBarCore

struct CheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Refresh current/latest versions for registered items."
    )

    @Argument(help: "Item ids to check. Checks every registered item when omitted.")
    var ids: [String] = []

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    @Flag(name: .long, help: "Print newline-delimited JSON progress events.")
    var jsonStream = false

    @Flag(name: .long, help: "Ignore refresh TTL and check every selected item now.")
    var force = false

    @Flag(name: .long, help: .hidden)
    var exitZeroOnOutdated = false

    func run() throws {
        try ensureJSONModeCompatibility(json: json, jsonStream: jsonStream)
        let config = try ConfigStore().load()
        let itemIDs = unique(ids)
        let results: [CheckResult] = try withCancellationToken { cancellationToken in
            let service = RegistryService(
                config: config,
                commandRunner: CommandExecutor(cancellationToken: cancellationToken),
                githubToken: ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
                    ?? ProcessInfo.processInfo.environment["GH_TOKEN"]
            )

            if jsonStream {
                try runJSONStream(service: service, ids: itemIDs)
                return []
            }

            return try service.check(ids: itemIDs, force: force)
        }

        if jsonStream {
            return
        }

        if json {
            try printJSON(results)
        } else {
            try printHuman(results)
        }

        if !exitZeroOnOutdated, results.contains(where: { $0.status == .outdated }) {
            throw ExitCode(10)
        }
    }

    private func printHuman(_ results: [CheckResult]) throws {
        if results.isEmpty {
            printEmptyRegistryNextStep()
            return
        }

        for result in results {
            print("\(result.id)\t\(result.status.rawValue)")
        }

        let manifest = try ManifestStore().load()
        let blocked = results.filter { $0.status == .untrusted }
        let updateApprovalNeeded = results.filter { result in
            guard result.status == .outdated,
                  let recipe = manifest.item(id: result.id)
            else {
                return false
            }
            return !TrustPolicy.isApproved(recipe, field: "update.cmd")
        }
        guard !blocked.isEmpty || !updateApprovalNeeded.isEmpty else {
            return
        }

        printNextCommands(
            approvalCommands(for: blocked.map(\.id) + updateApprovalNeeded.map(\.id))
        )
    }

    private func runJSONStream(service: RegistryService, ids: [String]) throws {
        let writer = JSONLWriter()
        try writer.write(MachineEvent(
            event: .started,
            operation: .check,
            timestamp: Date()
        ))

        var streamedResults: [CheckResult] = []
        let results: [CheckResult]
        do {
            results = try service.check(ids: ids, force: force) { event in
                switch event.phase {
                case .itemStarted:
                    try writer.write(MachineEvent(
                        event: .itemStarted,
                        operation: .check,
                        timestamp: Date(),
                        itemId: event.id,
                        message: event.name
                    ))
                case .itemFinished:
                    if let result = event.result {
                        streamedResults.append(result)
                    }
                    try writer.write(MachineEvent(
                        event: .itemFinished,
                        operation: .check,
                        timestamp: Date(),
                        itemId: event.id,
                        checkResult: event.result
                    ))
                }
            }
        } catch let error as ExecutionError where error.isCancellation {
            let report = CheckReport(results: streamedResults)
            try writer.write(MachineEvent(
                event: .cancelled,
                operation: .check,
                timestamp: Date(),
                checkSummary: report.summary,
                error: sanitizedErrorMessage(for: error)
            ))
            try writer.write(MachineEvent(
                event: .finished,
                operation: .check,
                timestamp: Date(),
                checkResults: report.results,
                checkSummary: report.summary
            ))
            throw ExitCode(2)
        } catch {
            try writer.write(MachineEvent(
                event: .failed,
                operation: .check,
                timestamp: Date(),
                error: sanitizedErrorMessage(for: error)
            ))
            throw error
        }

        let report = CheckReport(results: results)
        try writer.write(MachineEvent(
            event: .finished,
            operation: .check,
            timestamp: Date(),
            checkResults: report.results,
            checkSummary: report.summary
        ))

        if !exitZeroOnOutdated, results.contains(where: { $0.status == .outdated }) {
            throw ExitCode(10)
        }
    }
}
