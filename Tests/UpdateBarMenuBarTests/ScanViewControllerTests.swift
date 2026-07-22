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

        init(reports: [ScanReport]) {
            self.reports = reports
        }

        func status(refresh: Bool) throws -> StatusSnapshot {
            StatusSnapshot(
                generatedAt: Date(),
                summary: StatusSummary(total: 0, outdated: 0, errors: 0),
                items: []
            )
        }

        func scan(category: String?) throws -> ScanReport {
            lock.lock()
            defer { lock.unlock() }
            return reports.removeFirst()
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
