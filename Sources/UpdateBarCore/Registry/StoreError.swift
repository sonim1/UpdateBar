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
