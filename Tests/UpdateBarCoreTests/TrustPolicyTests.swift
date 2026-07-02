import XCTest
import UpdateBarCore
import UpdateBarTestSupport

final class TrustPolicyTests: XCTestCase {
    func testCmdLatestStrategyRequiresLatestCommandApproval() throws {
        var recipe = try loadRecipe()
        recipe.latest.strategy = .cmd
        recipe.latest.cmd = "tool latest"
        TrustPolicy.approveAllCommands(in: &recipe)
        recipe.latest.cmd = "tool latest v2"

        XCTAssertFalse(TrustPolicy.isCheckApproved(recipe))
        XCTAssertFalse(TrustPolicy.hasApprovedCommandFingerprints(recipe))
    }

    func testUntrustedRecipeCannotRunCommandFields() throws {
        var recipe = try loadRecipe()
        recipe.trust.level = .untrusted

        XCTAssertFalse(TrustPolicy.isApproved(recipe, field: "check.cmd"))
        XCTAssertFalse(TrustPolicy.isApproved(recipe, field: "update.cmd"))
    }

    func testApprovingCommandsStoresCurrentFingerprints() throws {
        var recipe = try loadRecipe()
        recipe.trust.level = .untrusted

        TrustPolicy.approveAllCommands(in: &recipe)

        XCTAssertTrue(TrustPolicy.isApproved(recipe, field: "check.cmd"))
        XCTAssertTrue(TrustPolicy.isApproved(recipe, field: "update.cmd"))
        XCTAssertEqual(recipe.trust.level, .trusted)
    }

    func testChangingCommandInvalidatesPreviousApproval() throws {
        var recipe = try loadRecipe()
        TrustPolicy.approveAllCommands(in: &recipe)
        XCTAssertTrue(TrustPolicy.isApproved(recipe, field: "update.cmd"))

        recipe.update.cmd = "npm update -g @anthropic-ai/claude-code"

        XCTAssertFalse(TrustPolicy.isApproved(recipe, field: "update.cmd"))
        XCTAssertTrue(TrustPolicy.isApproved(recipe, field: "check.cmd"))
    }

    private func loadRecipe() throws -> Recipe {
        let data = try Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json"))
        return try XCTUnwrap(JSONDecoder.updateBar.decode(Manifest.self, from: data).items.first)
    }
}
