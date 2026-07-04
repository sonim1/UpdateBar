import Foundation

public enum ManifestValidator {
    public static func validate(data: Data) throws -> ValidationResult {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            return ValidationResult(errors: ["$: must be an object"])
        }

        var errors: [String] = []
        errors += validateSchemaVersion(root)
        errors += validateProvenance(root)

        guard root.keys.contains("items") else {
            errors.append("items: required")
            return ValidationResult(errors: errors)
        }

        guard let rawItems = root["items"] as? [Any] else {
            errors.append("items: must be an array")
            return ValidationResult(errors: errors)
        }

        var ids: [String: Int] = [:]
        for (index, rawItem) in rawItems.enumerated() {
            guard let item = rawItem as? [String: Any] else {
                errors.append("items[\(index)]: must be an object")
                continue
            }
            errors.append(contentsOf: RecipeValidator.validateRaw(item, path: "items[\(index)]"))
            if let id = item["id"] as? String {
                if let firstIndex = ids[id] {
                    let redactedID = SecretRedactor.redact(id)
                    errors.append("items[\(index)].id: duplicate id \(redactedID)")
                    errors.append("items[\(firstIndex)].id: duplicate id \(redactedID)")
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

    private static func validateSchemaVersion(_ root: [String: Any]) -> [String] {
        guard root.keys.contains("schema_version") else {
            return ["schema_version: required"]
        }
        guard !isJSONBoolean(root["schema_version"]),
            let schemaVersion = root["schema_version"] as? Int
        else {
            return ["schema_version: must be integer 1"]
        }
        if schemaVersion != 1 {
            return ["schema_version: unsupported value \(schemaVersion)"]
        }
        return []
    }

    private static func validateProvenance(_ root: [String: Any]) -> [String] {
        guard root.keys.contains("provenance") else {
            return ["provenance: required"]
        }
        guard let provenance = root["provenance"] as? [String: Any] else {
            return ["provenance: must be an object"]
        }

        var errors: [String] = []
        errors += requireString(provenance, "created_by", path: "provenance")
        errors += requireISO8601DateString(provenance, "created_at", path: "provenance")
        errors += requireISO8601DateString(provenance, "updated_at", path: "provenance")
        return errors
    }

    private static func requireString(_ object: [String: Any], _ key: String, path: String)
        -> [String]
    {
        nonEmptyString(object[key]) ? [] : ["\(path).\(key): required"]
    }

    private static func requireISO8601DateString(
        _ object: [String: Any], _ key: String, path: String
    ) -> [String] {
        guard object.keys.contains(key),
            let string = object[key] as? String,
            nonEmptyString(string),
            ISO8601DateFormatter().date(from: string) != nil
        else {
            return ["\(path).\(key): must be an ISO-8601 date string"]
        }
        return []
    }

    private static func nonEmptyString(_ value: Any?) -> Bool {
        guard let string = value as? String else { return false }
        return string.contains { !$0.isWhitespace }
    }

    private static func isJSONBoolean(_ value: Any?) -> Bool {
        guard let object = value as AnyObject? else { return false }
        return CFGetTypeID(object) == CFBooleanGetTypeID()
    }
}
