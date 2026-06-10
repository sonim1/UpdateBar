import Foundation

public enum UntrustedRecipeGate {
    public static func canRun(_ recipe: Recipe, field: String) -> Bool {
        TrustPolicy.isApproved(recipe, field: field)
    }
}
