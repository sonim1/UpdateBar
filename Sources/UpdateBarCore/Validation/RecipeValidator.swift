import Foundation

public enum RecipeValidator {
    private static let sourceKinds = Set(["git", "npm", "github_release", "brew", "http", "custom"])
    private static let versionSchemes = Set(["semver", "commit", "calver", "opaque"])
    private static let latestStrategies = Set([
        "git_tags", "git_head", "npm_registry", "github_release", "brew", "http_regex", "cmd"
    ])
    private static let trustLevels = Set(["trusted", "untrusted", "elevated"])

    public static func validate(data: Data) throws -> ValidationResult {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let item = object as? [String: Any] else {
            return ValidationResult(errors: ["$: must be an object"])
        }

        var errors = validateRaw(item, path: "$")
        if errors.isEmpty {
            do {
                _ = try JSONDecoder.updateBar.decode(Recipe.self, from: data)
            } catch {
                errors.append("recipe: \(error)")
            }
        }
        return ValidationResult(errors: Array(Set(errors)).sorted())
    }

    static func validateRaw(_ item: [String: Any], path: String) -> [String] {
        var errors: [String] = []
        errors += requireString(item, "id", path: path)
        errors += requireString(item, "name", path: path)
        errors += requireString(item, "category", path: path)
        errors += requireString(item, "version_scheme", path: path)
        errors += requireOptionalStringIfPresent(item, "path", path: path)
        errors += requireOptionalStringIfPresent(item, "pin", path: path)

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
        errors += requireBooleanIfPresent(item, "enabled", path: path)
        errors += requireBooleanIfPresent(item, "notify", path: path)
        if let update = item["update"] as? [String: Any] {
            errors += requireString(update, "cmd", path: "\(path).update")
            errors += requireOptionalStringIfPresent(update, "cwd", path: "\(path).update")
            errors += requireBooleanIfPresent(update, "requires_write", path: "\(path).update")
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
        errors += requireOptionalStringIfPresent(source, "branch", path: path)
        if let kind = source["kind"] as? String, !sourceKinds.contains(kind) {
            errors.append("\(path).kind: unsupported value \(kind)")
        }
        return errors
    }

    private static func validateCheck(_ check: [String: Any], path: String) -> [String] {
        let hasCmdField = check.keys.contains("cmd")
        let hasFileField = check.keys.contains("file")
        let hasQueryField = check.keys.contains("query")
        let hasCmd = nonEmptyString(check["cmd"])
        let hasFile = nonEmptyString(check["file"])
        let hasQuery = nonEmptyString(check["query"])
        if hasCmdField && (hasFileField || hasQueryField) {
            return ["\(path): exactly one of cmd or file/query is required"]
        }
        if hasCmd && !hasFile && !hasQuery { return [] }
        if !hasCmd && hasFile && hasQuery { return [] }
        return ["\(path): exactly one of cmd or file/query is required"]
    }

    private static func validateLatest(_ latest: [String: Any], path: String) -> [String] {
        var errors = requireString(latest, "strategy", path: path)
        errors += requireOptionalStringIfPresent(latest, "cmd", path: path)
        errors += requireOptionalStringIfPresent(latest, "pattern", path: path)
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
        let hasRegexField = versionParse.keys.contains("regex")
        let hasJQField = versionParse.keys.contains("jq")
        let hasRegex = nonEmptyString(versionParse["regex"])
        let hasJQ = nonEmptyString(versionParse["jq"])
        if hasRegexField && hasJQField {
            errors.append("\(path): exactly one of regex or jq is required")
        } else if !hasRegex && !hasJQ {
            errors.append("\(path): exactly one of regex or jq is required")
        }
        if hasJQField {
            errors.append("\(path).jq: unsupported until runtime support is implemented")
        }
        return errors
    }

    private static func validateTrust(_ trust: [String: Any], path: String) -> [String] {
        var errors = requireString(trust, "level", path: path)
        if let level = trust["level"] as? String, !trustLevels.contains(level) {
            errors.append("\(path).level: unsupported value \(level)")
        }
        if let approvedCommands = trust["approved_commands"] as? [String: Any] {
            for (field, fingerprint) in approvedCommands where !(fingerprint is String) {
                errors.append("\(path).approved_commands[\(field)]: must be a string")
            }
        } else {
            errors.append("\(path).approved_commands: required")
        }
        return errors
    }

    private static func requireString(_ object: [String: Any], _ key: String, path: String) -> [String] {
        nonEmptyString(object[key]) ? [] : ["\(path).\(key): required"]
    }

    private static func requireBooleanIfPresent(_ object: [String: Any], _ key: String, path: String) -> [String] {
        guard object.keys.contains(key), !(object[key] is Bool) else { return [] }
        return ["\(path).\(key): must be a boolean when provided"]
    }

    private static func requireOptionalStringIfPresent(_ object: [String: Any], _ key: String, path: String) -> [String] {
        guard object.keys.contains(key) else { return [] }
        if object[key] is String || object[key] is NSNull { return [] }
        return ["\(path).\(key): must be a string or null when provided"]
    }

    private static func nonEmptyString(_ value: Any?) -> Bool {
        guard let string = value as? String else { return false }
        return string.contains { !$0.isWhitespace }
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
