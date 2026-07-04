import Foundation
import UpdateBarCore

func parseList(_ raw: String, separators: CharacterSet = .whitespaceAndComma) -> [String] {
    raw
        .components(separatedBy: separators)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
}

extension CharacterSet {
    static let whitespaceAndComma: CharacterSet = {
        CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines)
    }()
}

func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var results: [String] = []
    for value in values where seen.insert(value).inserted {
        results.append(value)
    }
    return results
}

func printApprovalNextSteps(for ids: [String]) {
    printNextCommands(approvalCommands(for: ids))
}

func printEmptyRegistryNextStep() {
    writeStdout("No items registered.")
    printNextCommands(["updatebar scan", "updatebar init"])
}

func printNextCommands(_ commands: [String], leadingBlank: Bool = true) {
    guard !commands.isEmpty else { return }
    if leadingBlank {
        writeStdout("")
    }
    writeStdout("Next")
    for command in commands {
        writeStdout(command)
    }
}

func approvalCommand(for id: String) -> String {
    "updatebar approvals \(displayID(id))"
}

func approvalCommands(for ids: [String]) -> [String] {
    ids.map(approvalCommand)
}

func approveFieldCommand(for id: String, field: String) -> String {
    "updatebar approve \(displayID(id)) --field \(field)"
}

func checkCommand(for id: String) -> String {
    "updatebar check \(displayID(id))"
}

func checkCommands(for ids: [String]) -> [String] {
    ids.map(checkCommand)
}

func batchCheckCommand(for ids: [String]) -> String? {
    let ids = ids.filter { !$0.isEmpty }
    guard !ids.isEmpty else { return nil }
    return "updatebar check \(ids.map(displayID).joined(separator: " "))"
}

func batchUpdateYesCommand(for ids: [String]) -> String? {
    let ids = ids.filter { !$0.isEmpty }
    guard !ids.isEmpty else { return nil }
    return "updatebar update \(ids.map(displayID).joined(separator: " ")) --yes"
}

private func displayID(_ id: String) -> String {
    SecretRedactor.redact(id)
}
