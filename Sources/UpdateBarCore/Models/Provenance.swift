import Foundation

public struct Provenance: Codable, Equatable {
    public var createdBy: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(createdBy: String, createdAt: Date, updatedAt: Date) {
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
