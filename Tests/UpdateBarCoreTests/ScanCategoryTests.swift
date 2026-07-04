import UpdateBarCore
import XCTest

final class ScanCategoryTests: XCTestCase {
    func testScanCategoryNormalizesAliasesAndSeparators() {
        XCTAssertEqual(ScanCategory.normalizedValue(for: "ai"), "ai-agent")
        XCTAssertEqual(ScanCategory.normalizedValue(for: "mcp_server"), "mcp-server")
        XCTAssertEqual(ScanCategory.normalizedValue(for: "package manager"), "package-manager")
        XCTAssertEqual(ScanCategory.normalizedValue(for: "cloud/devops"), "cloud-devops")
    }

    func testScanCategoryCompletionValuesIncludeAliases() {
        XCTAssertTrue(ScanCategory.completionValues.contains("ai-agent"))
        XCTAssertTrue(ScanCategory.completionValues.contains("mcp-server"))
        XCTAssertTrue(ScanCategory.completionValues.contains("ai"))
        XCTAssertTrue(ScanCategory.completionValues.contains("mcp"))
    }

    func testScanCategoryDescriptionListsSupportedValuesAndAliases() {
        let description = ScanCategory.description

        XCTAssertTrue(description.contains("ai-agent"))
        XCTAssertTrue(description.contains("mcp-server"))
        XCTAssertTrue(description.contains("aliases: ai, mcp"))
    }

    func testScanCategorySelectsFocusedDefaultDetectorsForMetadataOnlyCategories() {
        XCTAssertEqual(ScanCategory.defaultDetectors(for: nil), ScanDetector.allCases)
        XCTAssertEqual(ScanCategory.defaultDetectors(for: "codex-skill"), [.codexSkill])
        XCTAssertEqual(ScanCategory.defaultDetectors(for: "mcp"), [.mcpConfig])
        XCTAssertEqual(ScanCategory.defaultDetectors(for: "ai-agent"), ScanDetector.allCases)
    }
}
