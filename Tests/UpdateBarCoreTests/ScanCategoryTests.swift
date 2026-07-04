import UpdateBarCore
import XCTest

final class ScanCategoryTests: XCTestCase {
    func testScanCategoryNormalizesAliasesAndSeparators() {
        XCTAssertEqual(ScanCategory.normalizedValue(for: "ai"), "ai-agent")
        XCTAssertEqual(ScanCategory.normalizedValue(for: "mcp_server"), "mcp-server")
        XCTAssertEqual(ScanCategory.normalizedValue(for: "package manager"), "package-manager")
        XCTAssertEqual(ScanCategory.normalizedValue(for: "cloud/devops"), "cloud-devops")
    }

    func testScanCategoryFilterValueValidatesInput() throws {
        XCTAssertNil(try ScanCategory.filterValue(for: nil))
        XCTAssertEqual(try ScanCategory.filterValue(for: "mcp"), "mcp-server")
        XCTAssertThrowsError(try ScanCategory.filterValue(for: "___")) { error in
            XCTAssertEqual(String(describing: error), "category must not be empty")
        }
        XCTAssertThrowsError(try ScanCategory.filterValue(for: "localservice")) { error in
            XCTAssertEqual(
                String(describing: error),
                "localservice: unknown category; expected \(ScanCategory.description)"
            )
        }
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

    func testScanReportFiltersCandidatesByNormalizedCategoryWithoutDroppingErrors() {
        let report = ScanReport(
            candidates: [
                scanCandidate(id: "skill", category: "codex-skill"),
                scanCandidate(id: "server", category: "mcp-server"),
                scanCandidate(id: "agent", category: "ai-agent"),
            ],
            errors: [ScanError(detector: .known, message: "known failed")]
        )

        let filtered = report.filtered(category: "mcp")

        XCTAssertEqual(filtered.candidates.map(\.id), ["server"])
        XCTAssertEqual(filtered.errors, report.errors)
    }

    func testScanReportNilCategoryFilterReturnsOriginalReport() {
        let report = ScanReport(
            candidates: [scanCandidate(id: "agent", category: "ai-agent")],
            errors: [ScanError(detector: .known, message: "known failed")]
        )

        XCTAssertEqual(report.filtered(category: nil as String?), report)
    }

    private func scanCandidate(id: String, category: String) -> ScanCandidate {
        ScanCandidate(
            id: id,
            name: id,
            detector: .known,
            category: category,
            capability: .metadataOnly,
            confidence: .medium,
            installedVersion: nil,
            sourceRef: nil,
            recipe: nil
        )
    }
}
