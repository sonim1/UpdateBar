import Foundation

public struct Duration: Codable, Equatable, Sendable, CustomStringConvertible {
    public var seconds: Int

    public init(seconds: Int) {
        self.seconds = seconds
    }

    public init(minutes: Int) {
        self.seconds = minutes * 60
    }

    public init(hours: Int) {
        self.seconds = hours * 60 * 60
    }

    public init(parse text: String) throws {
        guard text.count >= 2, let unit = text.last else {
            throw ConfigError.invalidValue(key: "duration", value: text)
        }
        let numberText = String(text.dropLast())
        guard let number = Int(numberText), number > 0 else {
            throw ConfigError.invalidValue(key: "duration", value: text)
        }
        switch unit {
        case "m":
            self.init(minutes: number)
        case "h":
            self.init(hours: number)
        case "d":
            self.init(hours: number * 24)
        default:
            throw ConfigError.invalidValue(key: "duration", value: text)
        }
    }

    public var description: String {
        if seconds % 86_400 == 0 { return "\(seconds / 86_400)d" }
        if seconds % 3_600 == 0 { return "\(seconds / 3_600)h" }
        if seconds % 60 == 0 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }
}
