import ArgumentParser
import Foundation
import UpdateBarCore

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the latest stored status without running updates."
    )

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    @Flag(name: .long, help: .hidden)
    var refresh = false

    @Flag(name: .long, help: .hidden)
    var exitZeroOnOutdated = false

    func run() throws {
        let snapshot = try StatusService().snapshot(refresh: refresh)
        if json {
            try printJSON(snapshot)
        } else {
            printHuman(snapshot)
        }

        if !exitZeroOnOutdated, snapshot.summary.outdated > 0 {
            throw ExitCode(10)
        }
    }

    private func printHuman(_ snapshot: StatusSnapshot) {
        if snapshot.items.isEmpty {
            printEmptyRegistryNextStep()
            return
        }

        for item in snapshot.items {
            print("\(item.id)\t\(item.status.rawValue)")
        }

        let untrusted = snapshot.items.filter { $0.status == .untrusted }
        let checking = snapshot.items.filter { $0.status == .checking }
        guard !untrusted.isEmpty || !checking.isEmpty else {
            return
        }

        let untrustedCommands = untrusted.map(\.id).flatMap { id in
            [approvalCommand(for: id), checkCommand(for: id)]
        }
        printNextCommands(untrustedCommands + checkCommands(for: checking.map(\.id)))
    }
}
