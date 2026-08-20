import UpdateBarCore
import UpdateBarMenuBar
import XCTest

#if os(macOS)
    @testable import UpdateBarMenuBarApp
#endif

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

    func testRowsRetainHistoryOlderThanTheOverviewWindow() {
        let oldEvent = HistoryEvent(
            event: .updateFinished,
            id: "old-tool",
            outcome: "updated",
            at: Date(timeIntervalSince1970: 1)
        )

        let rows = HistoryLogPresentation.rows(from: [oldEvent])

        XCTAssertEqual(rows.map(\.title), ["old-tool updated"])
    }

    #if os(macOS)
        @MainActor
        func testDashboardRequestsAllRetainedHistoryForLogs() {
            let requested = expectation(description: "history requested")
            let service = HistoryRecordingService(historyRequested: requested)
            let controller = DashboardPanelController(
                service: service,
                onItemsChanged: {},
                onCheckForUpdates: {}
            )

            controller.reload()

            wait(for: [requested], timeout: 1)
            XCTAssertNil(service.historySince)
        }
    #endif
}

#if os(macOS)
    private final class HistoryRecordingService: MenuBarServicing, @unchecked Sendable {
        private let lock = NSLock()
        private let historyRequested: XCTestExpectation
        private var requestedSince: Date?

        init(historyRequested: XCTestExpectation) {
            self.historyRequested = historyRequested
        }

        var historySince: Date? { lock.withLock { requestedSince } }

        func status(refresh: Bool) throws -> StatusSnapshot {
            StatusSnapshot.from(
                manifest: Manifest(
                    schemaVersion: 1,
                    items: [],
                    provenance: Provenance(
                        createdBy: "test", createdAt: .distantPast, updatedAt: .distantPast
                    )
                ),
                state: State(schemaVersion: 1, generatedAt: .distantPast, items: [:]),
                now: Date()
            )
        }

        func history(since: Date?) throws -> [HistoryEvent] {
            lock.withLock { requestedSince = since }
            historyRequested.fulfill()
            return []
        }

        func scan(category: String?) throws -> ScanReport { fatalError("unused") }
        func registerScannedCandidates(
            _ candidates: [ScanCandidate], selectedIDs: [String], replace: Bool
        ) throws -> InitSummary { fatalError("unused") }
        func loadConfig() throws -> Config { fatalError("unused") }
        func saveConfig(_ config: Config) throws { fatalError("unused") }
        func checkNow(cancellationToken: CancellationToken?) throws { fatalError("unused") }
        func update(
            ids: [String],
            cancellationToken: CancellationToken?,
            onEvent: UpdateProgressHandler?,
            stopSignal: UpdateStopSignal?
        ) throws { fatalError("unused") }
        func updateAllApproved(
            cancellationToken: CancellationToken?,
            onEvent: UpdateProgressHandler?,
            stopSignal: UpdateStopSignal?
        ) throws { fatalError("unused") }
        func approvals(id: String) throws -> [CommandApprovalStatus] { fatalError("unused") }
        func approve(id: String, field: String, cancellationToken: CancellationToken?) throws {
            fatalError("unused")
        }
        func revoke(id: String, field: String, cancellationToken: CancellationToken?) throws {
            fatalError("unused")
        }
        func setEnabled(id: String, enabled: Bool) throws { fatalError("unused") }
    }
#endif
