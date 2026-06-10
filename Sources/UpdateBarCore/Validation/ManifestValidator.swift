import Foundation

public enum ManifestValidator {
    public static func validate(data: Data) throws -> ValidationResult {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            return ValidationResult(errors: ["$: must be an object"])
        }

        var errors: [String] = []
        if let schemaVersion = root["schema_version"] as? Int {
            if schemaVersion != 1 {
                errors.append("schema_version: unsupported value \(schemaVersion)")
            }
        } else {
            errors.append("schema_version: required")
        }

        guard let items = root["items"] as? [[String: Any]] else {
            errors.append("items: required")
            return ValidationResult(errors: errors)
        }

        var ids: [String: Int] = [:]
        for (index, item) in items.enumerated() {
            errors.append(contentsOf: RecipeValidator.validateRaw(item, path: "items[\(index)]"))
            if let id = item["id"] as? String {
                if let firstIndex = ids[id] {
                    errors.append("items[\(index)].id: duplicate id \(id)")
                    errors.append("items[\(firstIndex)].id: duplicate id \(id)")
                } else {
                    ids[id] = index
                }
            }
        }

        if errors.isEmpty {
            do {
                _ = try JSONDecoder.updateBar.decode(Manifest.self, from: data)
            } catch {
                errors.append("manifest: \(error)")
            }
        }
        return ValidationResult(errors: Array(Set(errors)).sorted())
    }
}
