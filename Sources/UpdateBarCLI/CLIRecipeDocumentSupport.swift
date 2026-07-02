import Foundation

func isManifestDocument(_ data: Data) throws -> Bool {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return false
    }
    return object["schema_version"] != nil || object["items"] != nil || object["provenance"] != nil
}
