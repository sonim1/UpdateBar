import Foundation

public enum VersionParser {
    public enum ParseError: Error, CustomStringConvertible, Equatable {
        case unsupportedJQ
        case invalidRegex(String)
        case missingMatch(String)

        public var description: String {
            switch self {
            case .unsupportedJQ:
                return "version_parse.jq is not supported yet"
            case let .invalidRegex(pattern):
                return "version_parse.regex invalid: \(pattern)"
            case let .missingMatch(pattern):
                return "version_parse.regex did not match output: \(pattern)"
            }
        }
    }

    public static func extract(from raw: String, using parser: VersionParse) throws -> String {
        switch parser {
        case let .regex(pattern):
            return try extractRegex(pattern: pattern, raw: raw)
        case .jq:
            throw ParseError.unsupportedJQ
        }
    }

    private static func extractRegex(pattern: String, raw: String) throws -> String {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            throw ParseError.invalidRegex(pattern)
        }
        guard regex.numberOfCaptureGroups == 1 else {
            throw ParseError.invalidRegex(pattern)
        }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, range: range), match.range(at: 1).location != NSNotFound,
            let capture = Range(match.range(at: 1), in: raw)
        else {
            throw ParseError.missingMatch(pattern)
        }
        return String(raw[capture])
    }
}
