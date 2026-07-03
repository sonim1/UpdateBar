import Foundation

public struct InitSummary: Codable, Equatable {
    public var added: [String]
    public var replaced: [String]
    public var skipped: [String]

    public init(added: [String], replaced: [String], skipped: [String]) {
        self.added = added
        self.replaced = replaced
        self.skipped = skipped
    }
}

public struct InitService {
    private let registryService: RegistryService

    public init(registryService: RegistryService = RegistryService()) {
        self.registryService = registryService
    }

    public func register(
        candidates: [ScanCandidate],
        selectedIDs: [String],
        replace: Bool
    ) throws -> InitSummary {
        let selectedIDs = unique(selectedIDs)
        let candidatesByID = Dictionary(
            candidates.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var recipesByID: [String: Recipe] = [:]
        var errors: [String] = []

        for id in selectedIDs {
            guard let candidate = candidatesByID[id] else {
                errors.append("\(id): not found")
                continue
            }
            guard candidate.capability == .full, let recipe = candidate.recipe else {
                errors.append("\(id): not importable (\(candidate.capability.rawValue))")
                continue
            }
            recipesByID[id] = TrustPolicy.untrustedCopy(recipe)
        }

        guard errors.isEmpty else {
            throw InitServiceError.invalidSelection(errors)
        }

        var manifest = try registryService.exportManifest()
        var added: [String] = []
        var replaced: [String] = []
        var skipped: [String] = []

        for id in selectedIDs {
            guard let recipe = recipesByID[id] else { continue }
            if manifest.item(id: recipe.id) != nil {
                guard replace else {
                    skipped.append(recipe.id)
                    continue
                }
                _ = try registryService.addRecipe(recipe, replace: true)
                manifest = manifest.replacing(item: recipe)
                replaced.append(recipe.id)
            } else {
                _ = try registryService.addRecipe(recipe, replace: false)
                manifest = manifest.replacing(item: recipe)
                added.append(recipe.id)
            }
        }

        return InitSummary(added: added, replaced: replaced, skipped: skipped)
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

public enum InitServiceError: Error, CustomStringConvertible {
    case invalidSelection([String])

    public var description: String {
        switch self {
        case .invalidSelection(let errors):
            return errors.map(SecretRedactor.redact).joined(separator: "\n")
        }
    }
}
