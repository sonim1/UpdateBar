import UpdateBarCore
import XCTest

final class ScanCategoryTests: XCTestCase {
    func testScanCategoryNormalizesAliasesAndSeparators() throws {
        XCTAssertEqual(try ScanCategory.filterValue(for: "ai"), "ai-agent")
        XCTAssertEqual(try ScanCategory.filterValue(for: "mcp_server"), "mcp-server")
        XCTAssertEqual(try ScanCategory.filterValue(for: "package manager"), "package-manager")
        XCTAssertEqual(try ScanCategory.filterValue(for: "cloud/devops"), "cloud-devops")
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

    func testScanCategorySelectsFocusedDefaultDetectorsForMetadataOnlyCategories() throws {
        XCTAssertEqual(try ScanCategory.defaultDetectors(for: nil), ScanDetector.allCases)
        XCTAssertEqual(try ScanCategory.defaultDetectors(for: "codex-skill"), [.codexSkill])
        XCTAssertEqual(try ScanCategory.defaultDetectors(for: "mcp"), [.mcpConfig])
        XCTAssertEqual(try ScanCategory.defaultDetectors(for: "ai-agent"), ScanDetector.allCases)
    }

    func testScanCategoryDefaultDetectorsRejectUnknownCategory() {
        XCTAssertThrowsError(try ScanCategory.defaultDetectors(for: "localservice")) { error in
            XCTAssertEqual(
                String(describing: error),
                "localservice: unknown category; expected \(ScanCategory.description)"
            )
        }
    }

    func testScanReportFiltersCandidatesByNormalizedCategoryWithoutDroppingErrors() throws {
        let report = ScanReport(
            candidates: [
                scanCandidate(id: "skill", category: "codex-skill"),
                scanCandidate(id: "server", category: "mcp-server"),
                scanCandidate(id: "agent", category: "ai-agent"),
            ],
            errors: [ScanError(detector: .known, message: "known failed")]
        )

        let filtered = try report.filtered(category: "mcp")

        XCTAssertEqual(filtered.candidates.map(\.id), ["server"])
        XCTAssertEqual(filtered.errors, report.errors)
    }

    func testScanReportRejectsUnknownCategoryFilter() {
        let report = ScanReport(
            candidates: [scanCandidate(id: "agent", category: "ai-agent")],
            errors: []
        )

        XCTAssertThrowsError(try report.filtered(category: "localservice")) { error in
            XCTAssertEqual(
                String(describing: error),
                "localservice: unknown category; expected \(ScanCategory.description)"
            )
        }
    }

    func testScanReportNilCategoryFilterReturnsOriginalReport() throws {
        let report = ScanReport(
            candidates: [scanCandidate(id: "agent", category: "ai-agent")],
            errors: [ScanError(detector: .known, message: "known failed")]
        )

        XCTAssertEqual(try report.filtered(category: nil as String?), report)
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
