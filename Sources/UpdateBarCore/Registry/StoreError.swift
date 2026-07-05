import Foundation

public enum StoreError: Error, CustomStringConvertible, Equatable {
    case corruptFile(path: String, reason: String)
    case writeFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case .corruptFile(let path, let reason):
            return "\(SecretRedactor.redact(path)): corrupt file: \(SecretRedactor.redact(reason))"
        case .writeFailed(let path, let reason):
            return "\(SecretRedactor.redact(path)): write failed: \(SecretRedactor.redact(reason))"
        }
    }
}

func storeErrorReason(for error: Error) -> String {
    switch error {
    case DecodingError.keyNotFound(let key, let context):
        return "missing required key \(pathDescription(context.codingPath + [key]))"
    case DecodingError.typeMismatch(let type, let context):
        return "\(pathDescription(context.codingPath)): expected \(type)"
    case DecodingError.valueNotFound(let type, let context):
        return "\(pathDescription(context.codingPath)): missing \(type)"
    case DecodingError.dataCorrupted(let context):
        return context.debugDescription
    default:
        return String(describing: error)
    }
}

private func pathDescription(_ path: [CodingKey]) -> String {
    guard !path.isEmpty else { return "$" }
    return path.map(\.stringValue).joined(separator: ".")
}
