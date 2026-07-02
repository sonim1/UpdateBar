import Foundation

public enum StoreError: Error, CustomStringConvertible, Equatable {
    case corruptFile(path: String, reason: String)
    case writeFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case let .corruptFile(path, reason):
            return "\(path): corrupt file: \(reason)"
        case let .writeFailed(path, reason):
            return "\(path): write failed: \(reason)"
        }
    }
}

func storeErrorReason(for error: Error) -> String {
    switch error {
    case let DecodingError.keyNotFound(key, context):
        return "missing required key \(pathDescription(context.codingPath + [key]))"
    case let DecodingError.typeMismatch(type, context):
        return "\(pathDescription(context.codingPath)): expected \(type)"
    case let DecodingError.valueNotFound(type, context):
        return "\(pathDescription(context.codingPath)): missing \(type)"
    case let DecodingError.dataCorrupted(context):
        return context.debugDescription
    default:
        return String(describing: error)
    }
}

private func pathDescription(_ path: [CodingKey]) -> String {
    guard !path.isEmpty else { return "$" }
    return path.map(\.stringValue).joined(separator: ".")
}
