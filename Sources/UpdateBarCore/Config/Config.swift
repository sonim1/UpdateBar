import Foundation

public struct Config: Equatable, Sendable {
    public var refresh: RefreshConfig
    public var security: SecurityConfig

    public static let `default` = Config(
        refresh: RefreshConfig(interval: Duration(hours: 6)),
        security: SecurityConfig(requireHTTPSSource: true)
    )

    public mutating func set(_ key: String, value: String) throws {
        switch key {
        case "refresh.interval":
            refresh.interval = try Duration(parse: value)
        case "security.require_https_source":
            security.requireHTTPSSource = try parseBool(key: key, value: value)
        default:
            throw ConfigError.unknownKey(key)
        }
    }

    public func get(_ key: String) -> String? {
        switch key {
        case "refresh.interval": refresh.interval.description
        case "security.require_https_source": String(security.requireHTTPSSource)
        default: nil
        }
    }

    private func parseBool(key: String, value: String) throws -> Bool {
        switch value.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: throw ConfigError.invalidValue(key: key, value: value)
        }
    }
}

public struct RefreshConfig: Equatable, Sendable {
    public var interval: Duration
}

public struct SecurityConfig: Equatable, Sendable {
    public var requireHTTPSSource: Bool
}

public enum ConfigError: Error, CustomStringConvertible, Equatable, Sendable {
    case unknownKey(String)
    case invalidValue(key: String, value: String)
    case corruptConfig(String)

    public var description: String {
        switch self {
        case let .unknownKey(key):
            return "\(redacted(key)): unknown config key"
        case let .invalidValue(key, value):
            return "\(redacted(key)): invalid value \(redacted(value))"
        case let .corruptConfig(message):
            return "config.toml: \(redacted(message))"
        }
    }

    private func redacted(_ text: String) -> String {
        SecretRedactor.redact(text)
    }
}
