import Foundation

public enum CommandApprovalStore {
    public static func approveAllCommands(in recipe: inout Recipe) {
        TrustPolicy.approveAllCommands(in: &recipe)
    }

    public static func isApproved(_ recipe: Recipe, field: String) -> Bool {
        TrustPolicy.isApproved(recipe, field: field)
    }
}
