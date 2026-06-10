import Foundation

public enum TrustPolicy {
    public static func effectiveLevel(for recipe: Recipe) -> TrustLevel {
        if recipe.latest.strategy == .cmd || recipe.hasCommandFields && recipe.source.kind == .custom {
            return .elevated
        }
        return recipe.trust.level
    }

    public static func isApproved(_ recipe: Recipe, field: String) -> Bool {
        guard recipe.trust.level == .trusted else { return false }
        guard let current = recipe.commandFingerprints()[field] else { return false }
        return recipe.trust.approvedCommands[field] == current
    }

    public static func approveAllCommands(in recipe: inout Recipe) {
        recipe.trust.approvedCommands = recipe.commandFingerprints()
        recipe.trust.level = .trusted
    }

    public static func untrustedCopy(_ recipe: Recipe) -> Recipe {
        var copy = recipe
        copy.trust.level = .untrusted
        copy.trust.approvedCommands = [:]
        return copy
    }
}
