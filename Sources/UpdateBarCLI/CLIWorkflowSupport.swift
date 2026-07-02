import Foundation
import UpdateBarCore

func parseScanDetectors(
    _ value: String?,
    categoryFilter: String? = nil
) throws -> [ScanDetector] {
    guard let value, !value.isEmpty else {
        return defaultScanDetectors(categoryFilter: categoryFilter)
    }
    let values = parseList(value)
    guard !values.isEmpty else {
        throw ValidationError("detectors: expected \(scanDetectorDescription())")
    }
    var seen = Set<String>()
    var detectors: [ScanDetector] = []
    for detector in values where seen.insert(detector).inserted {
        guard let parsed = ScanDetector(rawValue: detector) else {
            throw ValidationError(
                "\(detector): unknown detector; expected \(scanDetectorDescription())")
        }
        detectors.append(parsed)
    }
    return detectors
}

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

func scanDetectorDescription() -> String {
    let values = ScanDetector.allCases.map(\.rawValue)
    guard let last = values.last else {
        return ""
    }
    guard values.count > 1 else {
        return last
    }
    return "\(values.dropLast().joined(separator: ", ")), or \(last)"
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
    guard !ids.isEmpty else { return }
    printNextCommands(
        ids.map { "updatebar approvals \($0)" }
            + ["updatebar check \(ids.joined(separator: " "))"]
    )
}

func printEmptyRegistryNextStep() {
    print("No items registered.")
    printNextCommands(["updatebar init"])
}

func printNextCommands(_ commands: [String]) {
    guard !commands.isEmpty else { return }
    print("")
    print("Next")
    for command in commands {
        print(command)
    }
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

struct InitPayload: Encodable {
    var ok: Bool
    var added: [String]
    var replaced: [String]
    var skipped: [String]
    var errors: [String]

    init(summary: InitSummary, errors: [String]) {
        self.ok = errors.isEmpty
        self.added = summary.added
        self.replaced = summary.replaced
        self.skipped = summary.skipped
        self.errors = errors
    }

    init(added: [String], replaced: [String], skipped: [String], errors: [String]) {
        self.ok = errors.isEmpty
        self.added = added
        self.replaced = replaced
        self.skipped = skipped
        self.errors = errors
    }
}
