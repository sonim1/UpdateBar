import Foundation
import UpdateBarCore

public enum TestApprovals {
    public static func approveAllCommands(in recipe: inout Recipe) {
        recipe.trust.approvedCommands = recipe.commandFingerprints()
        recipe.trust.level = .trusted
    }
}
