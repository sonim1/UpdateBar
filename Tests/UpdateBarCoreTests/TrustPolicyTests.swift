import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class TrustPolicyTests: XCTestCase {
    func testCmdLatestStrategyRequiresLatestCommandApproval() throws {
        var recipe = try loadRecipe()
        recipe.latest.strategy = .cmd
        recipe.latest.cmd = "tool latest"
        TestApprovals.approveAllCommands(in: &recipe)
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

        TestApprovals.approveAllCommands(in: &recipe)

        XCTAssertTrue(TrustPolicy.isApproved(recipe, field: "check.cmd"))
        XCTAssertTrue(TrustPolicy.isApproved(recipe, field: "update.cmd"))
        XCTAssertEqual(recipe.trust.level, .trusted)
    }

    func testChangingCommandInvalidatesPreviousApproval() throws {
        var recipe = try loadRecipe()
        TestApprovals.approveAllCommands(in: &recipe)
        XCTAssertTrue(TrustPolicy.isApproved(recipe, field: "update.cmd"))

        recipe.update.cmd = "npm update -g @anthropic-ai/claude-code"

        XCTAssertFalse(TrustPolicy.isApproved(recipe, field: "update.cmd"))
        XCTAssertTrue(TrustPolicy.isApproved(recipe, field: "check.cmd"))
    }

    func testUnapprovedCheckCommandFieldsAreOrderedAndExcludeUpdate() throws {
        var recipe = try loadRecipe()
        recipe.latest = LatestSpec(strategy: .cmd, cmd: "tool latest", pattern: nil)
        recipe.trust.level = .untrusted
        recipe.trust.approvedCommands = [:]

        XCTAssertEqual(
            TrustPolicy.unapprovedCheckCommandFields(recipe),
            ["check.cmd", "latest.cmd"])

        recipe.check = .file(path: "/tmp/version")
        XCTAssertEqual(TrustPolicy.unapprovedCheckCommandFields(recipe), ["latest.cmd"])

        recipe.latest = LatestSpec(strategy: .brew, cmd: nil, pattern: nil)
        XCTAssertEqual(TrustPolicy.unapprovedCheckCommandFields(recipe), [])
    }

    private func loadRecipe() throws -> Recipe {
        let data = try Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json"))
        return try XCTUnwrap(JSONDecoder.updateBar.decode(Manifest.self, from: data).items.first)
    }
}
