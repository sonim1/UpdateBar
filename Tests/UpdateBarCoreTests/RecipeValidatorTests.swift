import XCTest
import UpdateBarCore

final class RecipeValidatorTests: XCTestCase {
    func testRejectsMalformedRecipeWithRootPaths() throws {
        let result = try RecipeValidator.validate(data: Data(
            """
            {
              "id": "tool"
            }
            """.utf8
        ))

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains("$.name: required"))
        XCTAssertTrue(result.errors.contains("$.source: required"))
    }
}
