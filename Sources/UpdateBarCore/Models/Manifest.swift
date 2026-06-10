import Foundation

public struct Manifest: Codable, Equatable {
    public var schemaVersion: Int
    public var items: [Recipe]
    public var provenance: Provenance

    public init(schemaVersion: Int, items: [Recipe], provenance: Provenance) {
        self.schemaVersion = schemaVersion
        self.items = items
        self.provenance = provenance
    }

    public func item(id: String) -> Recipe? {
        items.first { $0.id == id }
    }

    public func replacing(item replacement: Recipe) -> Manifest {
        var copy = self
        if let index = copy.items.firstIndex(where: { $0.id == replacement.id }) {
            copy.items[index] = replacement
        } else {
            copy.items.append(replacement)
        }
        return copy
    }

    public func removing(id: String) -> Manifest {
        var copy = self
        copy.items.removeAll { $0.id == id }
        return copy
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case items
        case provenance
    }
}
