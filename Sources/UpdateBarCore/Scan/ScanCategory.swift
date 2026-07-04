import Foundation

public enum ScanCategory {
    public static let supportedValues = [
        "ai-agent",
        "package-manager",
        "runtime-sdk",
        "shell-utility",
        "cloud-devops",
        "library",
        "codex-skill",
        "mcp-server",
    ]

    public static let completionValues = supportedValues + ["ai", "mcp"]

    public static var description: String {
        "\(supportedValues.joined(separator: ", ")); aliases: ai, mcp"
    }

    public static func normalizedValue(for value: String) -> String {
        let normalized =
            value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return aliases[normalized] ?? normalized
    }

    public static func filterValue(for value: String?) throws -> String? {
        guard let value else {
            return nil
        }
        let category = normalizedValue(for: value)
        guard !category.isEmpty else {
            throw ScanCategoryError.empty
        }
        guard supportedValues.contains(category) else {
            throw ScanCategoryError.unknown(category)
        }
        return category
    }

    public static func defaultDetectors(for category: String?) -> [ScanDetector] {
        guard let category else {
            return ScanDetector.allCases
        }
        switch normalizedValue(for: category) {
        case "codex-skill":
            return [.codexSkill]
        case "mcp-server":
            return [.mcpConfig]
        default:
            return ScanDetector.allCases
        }
    }

    private static let aliases: [String: String] = [
        "ai": "ai-agent",
        "aiagent": "ai-agent",
        "mcp": "mcp-server",
        "packagemanager": "package-manager",
        "runtimesdk": "runtime-sdk",
        "shellutility": "shell-utility",
        "clouddevops": "cloud-devops",
        "mcpserver": "mcp-server",
        "codexskill": "codex-skill",
    ]
}

public enum ScanCategoryError: Error, CustomStringConvertible {
    case empty
    case unknown(String)

    public var description: String {
        switch self {
        case .empty:
            return "category must not be empty"
        case .unknown(let category):
            return "\(category): unknown category; expected \(ScanCategory.description)"
        }
    }
}
