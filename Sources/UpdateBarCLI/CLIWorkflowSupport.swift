import Foundation
import UpdateBarCore

func defaultScanDetectors(categoryFilter: String?) -> [ScanDetector] {
    switch categoryFilter {
    case "codex-skill":
        return [.codexSkill]
    case "mcp-server":
        return [.mcpConfig]
    default:
        return ScanDetector.allCases
    }
}

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

func printApprovalAndCheckNextSteps(for ids: [String]) {
    var commands = approvalCommands(for: ids)
    if let check = batchCheckCommand(for: ids) {
        commands.append(check)
    }
    printNextCommands(commands)
}

func printEmptyRegistryNextStep() {
    print("No items registered.")
    printNextCommands(["updatebar init"])
}

func printNextCommands(_ commands: [String], leadingBlank: Bool = true) {
    guard !commands.isEmpty else { return }
    if leadingBlank {
        print("")
    }
    print("Next")
    for command in commands {
        print(command)
    }
}

func approvalCommand(for id: String) -> String {
    "updatebar approvals \(id)"
}

func approvalCommands(for ids: [String]) -> [String] {
    ids.map(approvalCommand)
}

func approveFieldCommand(for id: String, field: String) -> String {
    "updatebar approve \(id) --field \(field)"
}

func checkCommand(for id: String) -> String {
    "updatebar check \(id)"
}

func checkCommands(for ids: [String]) -> [String] {
    ids.map(checkCommand)
}

func batchCheckCommand(for ids: [String]) -> String? {
    let ids = ids.filter { !$0.isEmpty }
    guard !ids.isEmpty else { return nil }
    return "updatebar check \(ids.joined(separator: " "))"
}

func batchUpdateYesCommand(for ids: [String]) -> String? {
    let ids = ids.filter { !$0.isEmpty }
    guard !ids.isEmpty else { return nil }
    return "updatebar update \(ids.joined(separator: " ")) --yes"
}

func normalizedCategory(for value: String) throws -> String {
    let normalized = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "_", with: "-")
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: " ", with: "-")
        .split(separator: "-")
        .filter { !$0.isEmpty }
        .joined(separator: "-")
    guard !normalized.isEmpty else {
        throw ValidationError("category must not be empty")
    }

    let aliases: [String: String] = [
        "aiagent": "ai-agent",
        "packagemanager": "package-manager",
        "runtimesdk": "runtime-sdk",
        "shellutility": "shell-utility",
        "clouddevops": "cloud-devops",
        "mcpserver": "mcp-server",
        "codexskill": "codex-skill",
    ]
    return aliases[normalized] ?? normalized
}

func parseCategoryFilter(_ value: String?) throws -> String? {
    guard let value else {
        return nil
    }
    let category = try normalizedCategory(for: value)
    guard supportedScanCategories.contains(category) else {
        throw ValidationError(
            "\(category): unknown category; expected \(scanCategoryDescription())")
    }
    return category
}

let supportedScanCategories = [
    "ai-agent",
    "package-manager",
    "runtime-sdk",
    "shell-utility",
    "cloud-devops",
    "library",
    "codex-skill",
    "mcp-server",
]

func scanCategoryDescription() -> String {
    supportedScanCategories.joined(separator: ", ")
}
