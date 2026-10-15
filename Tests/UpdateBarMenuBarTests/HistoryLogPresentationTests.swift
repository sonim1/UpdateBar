import UpdateBarCore
import UpdateBarMenuBar
import XCTest

#if os(macOS)
    import AppKit
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

    func testRowsFilterBySearchToolOutcomeAndTimeAndRetainFailureMetadata() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let matching = HistoryEvent(
            event: .updateFinished,
            id: "example-tool",
            from: "1.0.0",
            to: "1.1.0",
            outcome: "failed",
            target: "2.0.0",
            error: "command reported an error",
            commandExitCode: 4,
            at: now.addingTimeInterval(-60)
        )
        let stale = HistoryEvent(
            event: .updateFinished,
            id: "example-tool",
            outcome: "failed",
            at: now.addingTimeInterval(-8 * 24 * 60 * 60)
        )
        let success = HistoryEvent(
            event: .updateFinished,
            id: "other-tool",
            outcome: "updated",
            at: now.addingTimeInterval(-60)
        )

        let rows = HistoryLogPresentation.rows(
            from: [stale, success, matching],
            filters: HistoryLogFilters(
                query: "example",
                tool: "example-tool",
                outcome: "failed",
                timeRange: .lastSevenDays
            ),
            now: now
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.detail, "Observed: 1.0.0 → 1.1.0 · Target: 2.0.0")
        XCTAssertEqual(
            rows.first?.failureDetail,
            "command reported an error · Exit code: 4"
        )
    }

    #if os(macOS)
        @MainActor
        func testDashboardRequestsAllRetainedHistoryForLogs() {
            let requested = expectation(description: "history requested")
            let service = HistoryRecordingService(historyRequested: requested)
            let controller = DashboardPanelController(
                service: service,
                onItemsChanged: {},
                itemActions: MenuBarPopoverActions(
                    check: {}, update: { _ in }, retry: { _ in },
                    setApproval: { _, _, _ in }, stop: {}, dashboard: { _ in }, more: {}
                ),
                onCheckForUpdates: {}
            )

            controller.reload()

            wait(for: [requested], timeout: 1)
            XCTAssertNil(service.historySince)
        }

        @MainActor
        func testLongFailureDetailStaysScrollableAndFiltersClearSelection() throws {
            _ = NSApplication.shared
            let controller = LogsViewController()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.contentViewController = controller
            let diagnostic = String(repeating: "diagnostic detail\n", count: 200)
            controller.apply(events: [
                HistoryEvent(
                    event: .updateFinished,
                    id: "example-tool",
                    outcome: "failed",
                    error: diagnostic,
                    at: Date()
                )
            ])
            controller.view.layoutSubtreeIfNeeded()
            let table = try XCTUnwrap(
                descendants(of: NSTableView.self, in: controller.view).first
            )
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            controller.tableViewSelectionDidChange(Notification(name: .init("selection")))
            controller.view.layoutSubtreeIfNeeded()

            let detailScroll = try XCTUnwrap(
                descendants(of: NSScrollView.self, in: controller.view).first {
                    $0.accessibilityIdentifier() == "logs-failure-detail"
                }
            )
            let tableScroll = try XCTUnwrap(
                descendants(of: NSScrollView.self, in: controller.view).first {
                    $0.accessibilityIdentifier() == "logs-table"
                }
            )
            let textView = try XCTUnwrap(detailScroll.documentView as? NSTextView)
            XCTAssertEqual(textView.string, diagnostic)
            XCTAssertTrue(textView.isSelectable)
            XCTAssertLessThanOrEqual(detailScroll.frame.height, 128)
            XCTAssertGreaterThan(tableScroll.frame.height, detailScroll.frame.height)

            let search = try XCTUnwrap(
                descendants(of: NSSearchField.self, in: controller.view).first {
                    $0.accessibilityIdentifier() == "logs-search"
                }
            )
            search.stringValue = "does-not-match"
            controller.controlTextDidChange(Notification(name: .init("filter"), object: search))

            XCTAssertEqual(table.numberOfRows, 0)
            XCTAssertEqual(table.selectedRow, -1)
            XCTAssertTrue(detailScroll.isHidden)
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
        func approve(
            id: String, field: String, expectedFingerprint: String?,
            cancellationToken: CancellationToken?
        ) throws {
            fatalError("unused")
        }
        func revoke(id: String, field: String, cancellationToken: CancellationToken?) throws {
            fatalError("unused")
        }
        func setEnabled(id: String, enabled: Bool) throws { fatalError("unused") }
        func setPinned(id: String, pinned: Bool) throws { fatalError("unused") }
    }
#endif

#if os(macOS)
    @MainActor
    private func descendants<View: NSView>(of type: View.Type, in root: NSView) -> [View] {
        var matches = root.subviews.compactMap { $0 as? View }
        for subview in root.subviews {
            matches.append(contentsOf: descendants(of: type, in: subview))
        }
        return matches
    }
#endif
