import Foundation

public struct Config: Equatable, Sendable {
    public var refresh: RefreshConfig
    public var security: SecurityConfig
    public var update: UpdateConfig
    public var schedule: ScheduleConfig = .default

    public static let knownKeys = [
        "refresh.interval",
        "security.require_https_source",
        "update.max_concurrent",
        "schedule.mode",
        "schedule.time",
    ]

    public static let `default` = Config(
        refresh: RefreshConfig(interval: Duration(hours: 6)),
        security: SecurityConfig(requireHTTPSSource: true),
        update: UpdateConfig(maxConcurrent: 3)
    )

    public mutating func set(_ key: String, value: String) throws {
        switch key {
        case "refresh.interval":
            do {
                refresh.interval = try Duration(parse: value)
            } catch {
                throw ConfigError.invalidValue(key: key, value: value)
            }
        case "security.require_https_source":
            security.requireHTTPSSource = try parseBool(key: key, value: value)
        case "update.max_concurrent":
            update.maxConcurrent = try parseConcurrency(key: key, value: value)
        case "schedule.mode":
            guard let mode = ScheduleMode(rawValue: value) else {
                throw ConfigError.invalidValue(key: key, value: value)
            }
            schedule.mode = mode
        case "schedule.time":
            guard ScheduleConfig.components(for: value) != nil else {
                throw ConfigError.invalidValue(key: key, value: value)
            }
            schedule.time = value
        default:
            throw ConfigError.unknownKey(key)
        }
    }

    public func get(_ key: String) -> String? {
        switch key {
        case "refresh.interval": refresh.interval.description
        case "security.require_https_source": String(security.requireHTTPSSource)
        case "update.max_concurrent": String(update.maxConcurrent)
        case "schedule.mode": schedule.mode.rawValue
        case "schedule.time": schedule.time
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

    private func parseConcurrency(key: String, value: String) throws -> Int {
        guard let parsed = Int(value), UpdateConfig.validRange.contains(parsed) else {
            throw ConfigError.invalidValue(key: key, value: value)
        }
        return parsed
    }
}

public enum ScheduleMode: String, CaseIterable, Sendable {
    case off
    case check
    case checkAndUpdate = "check_and_update"
}

public struct ScheduleConfig: Equatable, Sendable {
    public var mode: ScheduleMode
    public var time: String

    public static let `default` = ScheduleConfig(mode: .check, time: "09:00")

    public init(mode: ScheduleMode, time: String) {
        self.mode = mode
        self.time = time
    }

    public static func components(for time: String) -> DateComponents? {
        let bytes = Array(time.utf8)
        guard bytes.count == 5, bytes[2] == 58,
            [bytes[0], bytes[1], bytes[3], bytes[4]].allSatisfy({ (48...57).contains($0) }),
            let hour = Int(time.prefix(2)), let minute = Int(time.suffix(2)),
            hour < 24, minute < 60
        else { return nil }
        return DateComponents(hour: hour, minute: minute, second: 0)
    }
}

public struct RefreshConfig: Equatable, Sendable {
    public var interval: Duration
}

public struct SecurityConfig: Equatable, Sendable {
    public var requireHTTPSSource: Bool
}

public struct UpdateConfig: Equatable, Sendable {
    /// How many recipes may update at once. Upper bound is deliberately small:
    /// each slot is a real package-manager subprocess.
    public static let validRange = 1...8

    public var maxConcurrent: Int
}

public enum ConfigError: Error, CustomStringConvertible, Equatable, Sendable {
    case unknownKey(String)
    case invalidValue(key: String, value: String)
    case corruptConfig(String)
    case writeFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case .unknownKey(let key):
            return "\(redacted(key)): unknown config key"
        case .invalidValue(let key, let value):
            return "\(redacted(key)): invalid value \(redacted(value))"
        case .corruptConfig(let message):
            return "config.toml: \(redacted(message))"
        case .writeFailed(let path, let reason):
            return "\(redacted(path)): write failed: \(redacted(reason))"
        }
    }

    private func redacted(_ text: String) -> String {
        SecretRedactor.redact(text)
    }
}
