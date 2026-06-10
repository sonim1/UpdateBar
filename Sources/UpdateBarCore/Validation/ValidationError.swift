import Foundation

public struct ValidationResult: Equatable {
    public var isValid: Bool { errors.isEmpty }
    public var errors: [String]

    public init(errors: [String]) {
        self.errors = errors
    }
}
