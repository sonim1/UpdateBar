enum RecipeValidator {
    private static let sourceKinds = Set(["git", "npm", "github_release", "brew", "http", "custom"])
    private static let versionSchemes = Set(["semver", "commit", "calver", "opaque"])
    private static let latestStrategies = Set([
        "git_tags", "git_head", "npm_registry", "github_release", "brew", "http_regex", "cmd"
    ])
    private static let trustLevels = Set(["trusted", "untrusted", "elevated"])

    static func validateRaw(_ item: [String: Any], path: String) -> [String] {
        var errors: [String] = []
        errors += requireString(item, "id", path: path)
        errors += requireString(item, "name", path: path)
        errors += requireString(item, "category", path: path)
        errors += requireString(item, "version_scheme", path: path)

        if let id = item["id"] as? String, !matchesID(id) {
            errors.append("\(path).id: must match ^[a-z0-9][a-z0-9._-]*$")
        }
        if let source = item["source"] as? [String: Any] {
            errors += validateSource(source, path: "\(path).source")
        } else {
            errors.append("\(path).source: required")
        }
        if let scheme = item["version_scheme"] as? String, !versionSchemes.contains(scheme) {
            errors.append("\(path).version_scheme: unsupported value \(scheme)")
        }
        if let check = item["check"] as? [String: Any] {
            errors += validateCheck(check, path: "\(path).check")
        } else {
            errors.append("\(path).check: required")
        }
        if let latest = item["latest"] as? [String: Any] {
            errors += validateLatest(latest, path: "\(path).latest")
        } else {
            errors.append("\(path).latest: required")
        }
        if let versionParse = item["version_parse"] as? [String: Any] {
            errors += validateVersionParse(versionParse, path: "\(path).version_parse")
        } else {
            errors.append("\(path).version_parse: required")
        }
        if let update = item["update"] as? [String: Any] {
            errors += requireString(update, "cmd", path: "\(path).update")
        } else {
            errors.append("\(path).update: required")
        }
        if let trust = item["trust"] as? [String: Any] {
            errors += validateTrust(trust, path: "\(path).trust")
        } else {
            errors.append("\(path).trust: required")
        }
        if item.keys.contains("sync") {
            errors.append("\(path).sync: unsupported in schema_version 1")
        }
        return errors
    }

    private static func validateSource(_ source: [String: Any], path: String) -> [String] {
        var errors: [String] = []
        errors += requireString(source, "kind", path: path)
        errors += requireString(source, "ref", path: path)
        if let kind = source["kind"] as? String, !sourceKinds.contains(kind) {
            errors.append("\(path).kind: unsupported value \(kind)")
        }
        return errors
    }

    private static func validateCheck(_ check: [String: Any], path: String) -> [String] {
        let hasCmd = check["cmd"] is String
        let hasFile = check["file"] is String
        let hasQuery = check["query"] is String
        if hasCmd && !hasFile && !hasQuery { return [] }
        if !hasCmd && hasFile && hasQuery { return [] }
        return ["\(path): exactly one of cmd or file/query is required"]
    }

    private static func validateLatest(_ latest: [String: Any], path: String) -> [String] {
        var errors = requireString(latest, "strategy", path: path)
        guard let strategy = latest["strategy"] as? String else {
            return errors
        }
        if !latestStrategies.contains(strategy) {
            errors.append("\(path).strategy: unsupported value \(strategy)")
        }
        if strategy == "cmd", !nonEmptyString(latest["cmd"]) {
            errors.append("\(path).cmd: required when latest.strategy is cmd")
        }
        if strategy == "http_regex", !nonEmptyString(latest["pattern"]) {
            errors.append("\(path).pattern: required when latest.strategy is http_regex")
        }
        return errors
    }

    private static func validateVersionParse(_ versionParse: [String: Any], path: String) -> [String] {
        var errors: [String] = []
        let hasRegex = versionParse["regex"] is String
        let hasJQ = versionParse["jq"] is String
        if hasRegex == hasJQ {
            errors.append("\(path): exactly one of regex or jq is required")
        }
        if hasJQ {
            errors.append("\(path).jq: unsupported until runtime support is implemented")
        }
        return errors
    }

    private static func validateTrust(_ trust: [String: Any], path: String) -> [String] {
        var errors = requireString(trust, "level", path: path)
        if let level = trust["level"] as? String, !trustLevels.contains(level) {
            errors.append("\(path).level: unsupported value \(level)")
        }
        if !(trust["approved_commands"] is [String: Any]) {
            errors.append("\(path).approved_commands: required")
        }
        return errors
    }

    private static func requireString(_ object: [String: Any], _ key: String, path: String) -> [String] {
        nonEmptyString(object[key]) ? [] : ["\(path).\(key): required"]
    }

    private static func nonEmptyString(_ value: Any?) -> Bool {
        guard let string = value as? String else { return false }
        return !string.isEmpty
    }

    private static func matchesID(_ id: String) -> Bool {
        guard let first = id.utf8.first, isIDStartByte(first) else { return false }
        return id.utf8.dropFirst().allSatisfy(isIDContinuationByte)
    }

    private static func isIDStartByte(_ byte: UInt8) -> Bool {
        isLowercaseASCIILetter(byte) || isASCIIDigit(byte)
    }

    private static func isIDContinuationByte(_ byte: UInt8) -> Bool {
        isIDStartByte(byte)
            || byte == UInt8(ascii: ".")
            || byte == UInt8(ascii: "_")
            || byte == UInt8(ascii: "-")
    }

    private static func isLowercaseASCIILetter(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }
}
