import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class HistoryLogPresentationTests: XCTestCase {
    func testRowsSortNewestFirstAndDescribeUpdateVersions() {
        let older = HistoryEvent(
            event: .updateFinished,
            id: "tool",
            from: "1.0.0",
            to: "1.1.0",
            outcome: "updated",
            at: Date(timeIntervalSince1970: 1_000)
        )
        let newer = HistoryEvent(
            event: .checkFinished,
            outcome: "completed",
            outdated: 2,
            at: Date(timeIntervalSince1970: 2_000)
        )

        let rows = HistoryLogPresentation.rows(from: [older, newer])

        XCTAssertEqual(rows.map(\.title), ["Check completed", "tool updated"])
        XCTAssertEqual(rows.map(\.detail), ["2 updates available", "1.0.0 → 1.1.0"])
        XCTAssertEqual(rows.map(\.date), [newer.at, older.at])
    }

    func testUpdateWithoutVersionsKeepsUsefulOutcome() {
        let event = HistoryEvent(
            event: .updateFinished,
            id: "tool",
            outcome: "failed",
            at: Date(timeIntervalSince1970: 1_000)
        )

        let row = try? XCTUnwrap(HistoryLogPresentation.rows(from: [event]).first)

        XCTAssertEqual(row?.title, "tool failed")
        XCTAssertEqual(row?.detail, "No version details")
    }

    func testEmptyHistoryProducesNoRows() {
        XCTAssertTrue(HistoryLogPresentation.rows(from: []).isEmpty)
    }
}
