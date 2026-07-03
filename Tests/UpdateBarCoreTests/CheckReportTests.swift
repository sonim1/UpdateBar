import XCTest
import UpdateBarCore

final class CheckReportTests: XCTestCase {
    func testCheckSummaryCountsDiffersResults() {
        let report = CheckReport(results: [
            checkResult(id: "outdated", status: .outdated),
            checkResult(id: "differs", status: .differs),
            checkResult(id: "error", status: .error)
        ])

        XCTAssertEqual(report.summary.total, 3)
        XCTAssertEqual(report.summary.outdated, 1)
        XCTAssertEqual(report.summary.differs, 1)
        XCTAssertEqual(report.summary.errors, 1)
    }

    func testCheckSummaryDecodesOlderPayloadWithoutDiffers() throws {
        let payload = """
        {"total":1,"outdated":1,"errors":0,"untrusted":0,"disabled":0,"pinned":0}
        """

        let summary = try JSONDecoder().decode(CheckSummary.self, from: Data(payload.utf8))

        XCTAssertEqual(summary.differs, 0)
    }

    func testCheckResultRedactsLegacyMetadataSecrets() {
        let secret = "sk-or-v1-check-secret-value"

        let result = CheckResult(
            id: secret,
            name: "Tool \(secret)",
            current: "1.0.0",
            latest: "2.0.0",
            status: .ok,
            lastChecked: nil,
            error: nil
        )

        XCTAssertEqual(result.id, "[REDACTED]")
        XCTAssertEqual(result.name, "Tool [REDACTED]")
        XCTAssertFalse(String(describing: result).contains(secret))
    }

    private func checkResult(id: String, status: ItemStatus) -> CheckResult {
        CheckResult(
            id: id,
            name: id,
            current: "1.0.0",
            latest: "2.0.0",
            status: status,
            lastChecked: nil,
            error: status == .error ? "failed" : nil
        )
    }
}
