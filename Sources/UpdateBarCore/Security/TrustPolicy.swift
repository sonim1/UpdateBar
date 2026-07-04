import Foundation

public enum TrustPolicy {
    public static func isApproved(_ recipe: Recipe, field: String) -> Bool {
        guard recipe.trust.level == .trusted else { return false }
        guard let current = recipe.commandFingerprints()[field] else { return false }
        return recipe.trust.approvedCommands[field] == current
    }

    public static func isCheckApproved(_ recipe: Recipe) -> Bool {
        if case .command = recipe.check, !isApproved(recipe, field: "check.cmd") {
            return false
        }
        if recipe.latest.strategy == .cmd, !isApproved(recipe, field: "latest.cmd") {
            return false
        }
        return recipe.trust.level == .trusted
    }

    public static func hasApprovedCommandFingerprints(_ recipe: Recipe) -> Bool {
        guard recipe.trust.level == .trusted else { return false }
        return recipe.commandFingerprints().allSatisfy { field, fingerprint in
            recipe.trust.approvedCommands[field] == fingerprint
        }
    }

    public static func untrustedCopy(_ recipe: Recipe) -> Recipe {
        var copy = recipe
        copy.trust.level = .untrusted
        copy.trust.approvedCommands = [:]
        return copy
    }
}
