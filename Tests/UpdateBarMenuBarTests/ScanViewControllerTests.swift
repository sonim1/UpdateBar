#if os(macOS)
    import AppKit
    @testable import UpdateBarCore
    import UpdateBarMenuBar
    @testable import UpdateBarMenuBarApp
    import XCTest

    @MainActor
    final class ScanViewControllerTests: XCTestCase {
        func testMixedPartialScanKeepsCandidateAndSurfacesRedactedWarning() async throws {
            let secret = "sk-1234567890abcdef"
            let report = ScanReport(
                candidates: [candidate()],
                errors: [
                    ScanError(
                        detector: .npmGlobal,
                        message: "npm failed using \(secret)"
                    )
                ]
            )
            let service = ScanFlowService(
                reports: [report, ScanReport(candidates: [], errors: [])]
            )
            let controller = ScanViewController(service: service, onChanged: {})
            _ = controller.view
            let scanButton = try XCTUnwrap(
                descendants(of: NSButton.self, in: controller.view)
                    .first { $0.title == "Scan" }
            )
            let errorDelivered = expectation(description: "partial scan error delivered")
            var errorMessage = ""
            controller.onError = { error in
                errorMessage = String(describing: error)
                errorDelivered.fulfill()
            }

            scanButton.performClick(nil)
            await fulfillment(of: [errorDelivered], timeout: 2)

            let tableView = try XCTUnwrap(
                descendants(of: NSTableView.self, in: controller.view).first
            )
            XCTAssertEqual(tableView.numberOfRows, 1)
            let nameColumn = try XCTUnwrap(
                tableView.tableColumns.first { $0.identifier.rawValue == "name" }
            )
            let nameCell = try XCTUnwrap(
                controller.tableView(tableView, viewFor: nameColumn, row: 0)
            )
            XCTAssertTrue(
                descendants(of: NSTextField.self, in: nameCell)
                    .contains { $0.stringValue == "Example Tool" }
            )
            XCTAssertEqual(
                descendants(of: ScanCountBadgeView.self, in: controller.view)
                    .map(\.stringValue),
                ["1", "0", "0"]
            )
            XCTAssertNotNil(scanButton.image)
            XCTAssertEqual(scanButton.contentTintColor, .systemRed)
            XCTAssertEqual(scanButton.accessibilityLabel(), "Scan failed. Scan again")
            XCTAssertTrue(errorMessage.contains("1 candidate"))
            XCTAssertTrue(errorMessage.contains("1 detector failed"))
            XCTAssertTrue(errorMessage.contains("npm_global"))
            XCTAssertTrue(errorMessage.contains("[REDACTED]"))
            XCTAssertFalse(errorMessage.contains(secret))

            scanButton.performClick(nil)

            XCTAssertNil(scanButton.image)
            XCTAssertNil(scanButton.contentTintColor)
            XCTAssertEqual(
                scanButton.accessibilityLabel(),
                "Scanning for installed tools"
            )
        }

        func testAllErrorPartialScanKeepsEmptySurfaceAndSurfacesRedactedWarning() async throws {
            let secret = "ghp_abcdefghijklmnopqrstuvwxyz123456"
            let service = ScanFlowService(
                reports: [
                    ScanReport(
                        candidates: [],
                        errors: [
                            ScanError(
                                detector: .brew,
                                message: "brew failed using \(secret)"
                            )
                        ]
                    )
                ]
            )
            let controller = ScanViewController(service: service, onChanged: {})
            _ = controller.view
            let scanButton = try XCTUnwrap(
                descendants(of: NSButton.self, in: controller.view)
                    .first { $0.title == "Scan" }
            )
            let errorDelivered = expectation(description: "empty partial scan error delivered")
            var errorMessage = ""
            controller.onError = { error in
                errorMessage = String(describing: error)
                errorDelivered.fulfill()
            }

            scanButton.performClick(nil)
            await fulfillment(of: [errorDelivered], timeout: 2)

            let tableView = try XCTUnwrap(
                descendants(of: NSTableView.self, in: controller.view).first
            )
            XCTAssertEqual(tableView.numberOfRows, 0)
            XCTAssertEqual(
                descendants(of: ScanCountBadgeView.self, in: controller.view)
                    .map(\.stringValue),
                ["0", "0", "0"]
            )
            XCTAssertNotNil(scanButton.image)
            XCTAssertEqual(scanButton.contentTintColor, .systemRed)
            XCTAssertEqual(scanButton.accessibilityLabel(), "Scan failed. Scan again")
            XCTAssertTrue(errorMessage.contains("no candidates"))
            XCTAssertTrue(errorMessage.contains("1 detector failed"))
            XCTAssertTrue(errorMessage.contains("brew"))
            XCTAssertTrue(errorMessage.contains("[REDACTED]"))
            XCTAssertFalse(errorMessage.contains(secret))
        }

        func testScanCompletionPrefersNewerRegisteredItemSnapshot() async throws {
            let started = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let service = ScanFlowService(
                reports: [ScanReport(candidates: [candidate()], errors: [])],
                snapshots: [snapshot(status: .disabled)],
                scanStarted: started,
                scanRelease: release
            )
            let controller = ScanViewController(service: service, onChanged: {})
            _ = controller.view
            let scanButton = try XCTUnwrap(
                descendants(of: NSButton.self, in: controller.view)
                    .first { $0.title == "Scan" }
            )

            scanButton.performClick(nil)
            XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
            controller.applyRegisteredItems([statusItem(status: .ok)])
            release.signal()

            let tableView = try XCTUnwrap(
                descendants(of: NSTableView.self, in: controller.view).first
            )
            let didLoadRow = await waitUntil { tableView.numberOfRows == 1 }
            XCTAssertTrue(didLoadRow)
            let trackedColumn = try XCTUnwrap(
                tableView.tableColumns.first { $0.identifier.rawValue == "tracked" }
            )
            let trackedCell = try XCTUnwrap(
                controller.tableView(tableView, viewFor: trackedColumn, row: 0)
            )
            let checkbox = try XCTUnwrap(
                descendants(of: NSButton.self, in: trackedCell).first
            )

            XCTAssertEqual(checkbox.state, .on)
        }

        func testClosingDuringScanKeepsScanDisabledUntilWorkFinishes() async throws {
            let started = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let service = ScanFlowService(
                reports: [ScanReport(candidates: [], errors: [])],
                scanStarted: started,
                scanRelease: release
            )
            let controller = ScanViewController(service: service, onChanged: {})
            _ = controller.view
            let scanButton = try XCTUnwrap(
                descendants(of: NSButton.self, in: controller.view)
                    .first { $0.title == "Scan" }
            )

            scanButton.performClick(nil)
            XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
            controller.invalidateScanSession()

            XCTAssertFalse(scanButton.isEnabled)

            release.signal()
            let didFinishScan = await waitUntil { scanButton.isEnabled }
            XCTAssertTrue(didFinishScan)
            XCTAssertEqual(service.scanCallCount, 1)
        }

        private func candidate() -> ScanCandidate {
            ScanCandidate(
                id: "example-tool",
                name: "Example Tool",
                detector: .known,
                category: "developer-tool",
                capability: .metadataOnly,
                confidence: .high,
                installedVersion: "1.2.3",
                sourceRef: nil,
                recipe: nil
            )
        }

        private func statusItem(status: ItemStatus) -> StatusItem {
            StatusItem(
                id: "example-tool",
                name: "Example Tool",
                category: "developer-tool",
                current: nil,
                latest: nil,
                status: status,
                pinned: false,
                lastChecked: nil,
                error: nil
            )
        }

        private func snapshot(status: ItemStatus) -> StatusSnapshot {
            StatusSnapshot(
                generatedAt: Date(),
                summary: StatusSummary(total: 1, outdated: 0, errors: 0),
                items: [statusItem(status: status)]
            )
        }

        private func waitUntil(
            timeout: TimeInterval = 2,
            _ condition: @escaping @MainActor () -> Bool
        ) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() { return true }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            return condition()
        }

        private func descendants<View: NSView>(
            of type: View.Type,
            in root: NSView
        ) -> [View] {
            var matches = root.subviews.compactMap { $0 as? View }
            for subview in root.subviews {
                matches.append(contentsOf: descendants(of: type, in: subview))
            }
            return matches
        }
    }

    private final class ScanFlowService: MenuBarServicing, @unchecked Sendable {
        private let lock = NSLock()
        private var reports: [ScanReport]
        private var snapshots: [StatusSnapshot]
        private let scanStarted: DispatchSemaphore?
        private let scanRelease: DispatchSemaphore?
        private var storedScanCallCount = 0

        init(
            reports: [ScanReport],
            snapshots: [StatusSnapshot] = [],
            scanStarted: DispatchSemaphore? = nil,
            scanRelease: DispatchSemaphore? = nil
        ) {
            self.reports = reports
            self.snapshots = snapshots
            self.scanStarted = scanStarted
            self.scanRelease = scanRelease
        }

        var scanCallCount: Int {
            lock.withLock { storedScanCallCount }
        }

        func status(refresh: Bool) throws -> StatusSnapshot {
            lock.withLock {
                if !snapshots.isEmpty {
                    return snapshots.removeFirst()
                }
                return StatusSnapshot(
                    generatedAt: Date(),
                    summary: StatusSummary(total: 0, outdated: 0, errors: 0),
                    items: []
                )
            }
        }

        func scan(category: String?) throws -> ScanReport {
            let report = lock.withLock {
                storedScanCallCount += 1
                return reports.removeFirst()
            }
            scanStarted?.signal()
            scanRelease?.wait()
            return report
        }

        func registerScannedCandidates(
            _ candidates: [ScanCandidate],
            selectedIDs: [String],
            replace: Bool
        ) throws -> InitSummary {
            fatalError("unused")
        }

        func loadConfig() throws -> Config { fatalError("unused") }
        func saveConfig(_ config: Config) throws { fatalError("unused") }
        func checkNow(cancellationToken: CancellationToken?) throws { fatalError("unused") }
        func update(id: String, cancellationToken: CancellationToken?) throws {
            fatalError("unused")
        }
        func updateAllApproved(cancellationToken: CancellationToken?) throws {
            fatalError("unused")
        }
        func approvals(id: String) throws -> [CommandApprovalStatus] { fatalError("unused") }
        func approve(id: String, field: String, cancellationToken: CancellationToken?) throws {
            fatalError("unused")
        }
        func revoke(id: String, field: String, cancellationToken: CancellationToken?) throws {
            fatalError("unused")
        }
        func setEnabled(id: String, enabled: Bool) throws { fatalError("unused") }
        func history(since: Date?) throws -> [HistoryEvent] { fatalError("unused") }
    }
#endif
