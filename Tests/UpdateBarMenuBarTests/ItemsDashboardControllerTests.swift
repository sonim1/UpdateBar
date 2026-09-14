#if os(macOS)
    import AppKit
    import UpdateBarCore
    import UpdateBarMenuBar
    import XCTest

    @testable import UpdateBarMenuBarApp

    @MainActor
    final class ItemsDashboardControllerTests: XCTestCase {
        func testApplyPreservesAcknowledgementAcrossProgressTicksAndRevalidatesChanges() {
            let store = ItemsDashboardStore(
                service: ItemsRecordingService(), onChanged: {}, actions: actions()
            )
            let command = approval(fingerprint: "one")
            store.apply(model(command: command))
            store.setAcknowledged(true, id: "tool", field: command.field)

            var progressTick = model(command: command)
            progressTick.update(
                state: state(), approvals: ["tool": [command]], activeActionTitle: "Checking"
            )
            store.apply(progressTick)

            XCTAssertTrue(store.model.isAcknowledged(id: "tool", field: command.field))

            store.apply(model(command: approval(fingerprint: "two")))
            XCTAssertFalse(store.model.isAcknowledged(id: "tool", field: command.field))
        }

        func testUpdateResolvesCanonicalVisibleTargetsAtClickTime() {
            var updated: [[String]] = []
            var callbacks = actions()
            callbacks.update = { updated.append($0) }
            let store = ItemsDashboardStore(
                service: ItemsRecordingService(), onChanged: {}, actions: callbacks
            )
            store.apply(model(items: [item("alpha"), item("beta")]))
            store.setQuery("beta")

            store.update()

            XCTAssertEqual(updated, [["beta"]])
            XCTAssertEqual(store.primaryAction.title, "Update visible (1)")
        }

        func testBusyStateBlocksCheckUpdateAndApprovalButAllowsSupportedStop() {
            var checks = 0
            var updates = 0
            var approvals = 0
            var stops = 0
            var callbacks = actions()
            callbacks.check = { checks += 1 }
            callbacks.update = { _ in updates += 1 }
            callbacks.setApproval = { _, _, _ in approvals += 1 }
            callbacks.stop = { stops += 1 }
            let store = ItemsDashboardStore(
                service: ItemsRecordingService(), onChanged: {}, actions: callbacks
            )
            let command = approval(fingerprint: "one")
            var busy = model(command: command)
            busy.update(
                state: state(), approvals: ["tool": [command]],
                activeActionTitle: "Updating items", isUpdateAction: true
            )
            store.apply(busy)
            store.setAcknowledged(true, id: "tool", field: command.field)

            store.check()
            store.update()
            store.setApproval(id: "tool", field: command.field)
            store.stop()

            XCTAssertEqual(checks, 0)
            XCTAssertEqual(updates, 0)
            XCTAssertEqual(approvals, 0)
            XCTAssertEqual(stops, 1)
        }

        func testUnsupportedStoppingNeverDispatchesStop() {
            var stops = 0
            var callbacks = actions()
            callbacks.stop = { stops += 1 }
            let store = ItemsDashboardStore(
                service: ItemsRecordingService(), onChanged: {}, actions: callbacks,
                supportsStopping: false
            )
            var busy = model(items: [item("tool")])
            busy.update(
                state: state([item("tool")]), approvals: [:],
                activeActionTitle: "Updating items", isUpdateAction: true
            )
            store.apply(busy)

            store.stop()

            XCTAssertEqual(stops, 0)
            XCTAssertFalse(store.supportsStopping)
        }

        func testRetryUsesOnlyCanonicalRetryIDsAndHasNoFallbackTargets() {
            var retried: [[String]] = []
            var callbacks = actions()
            callbacks.retry = { retried.append($0) }
            let store = ItemsDashboardStore(
                service: ItemsRecordingService(), onChanged: {}, actions: callbacks
            )
            var progress = MenuBarItemProgress()
            progress.apply(.planned([planItem("failed"), planItem("removed")]))
            progress.apply(.itemFinished(result("failed", outcome: .failed)))
            progress.apply(.itemFinished(result("removed", outcome: .failed)))
            let failed = item("failed", status: .error)
            var snapshot = MenuBarPopoverModel()
            snapshot.update(state: state([failed]), approvals: [:], progress: progress)
            store.apply(snapshot)

            store.retryFailed()

            XCTAssertEqual(retried, [["failed"]])
        }

        func testReviewedApprovalResetsAcknowledgementAndDoesNotCheckOrUpdate() {
            var reviewed: CommandApprovalStatus?
            var checks = 0
            var updates = 0
            var callbacks = actions()
            callbacks.check = { checks += 1 }
            callbacks.update = { _ in updates += 1 }
            callbacks.setApproval = { _, command, approving in
                XCTAssertTrue(approving)
                reviewed = command
            }
            let store = ItemsDashboardStore(
                service: ItemsRecordingService(), onChanged: {}, actions: callbacks
            )
            let command = approval(fingerprint: "one")
            store.apply(model(command: command))
            store.setAcknowledged(true, id: "tool", field: command.field)

            store.setApproval(id: "tool", field: command.field)

            XCTAssertEqual(reviewed, command)
            XCTAssertFalse(store.model.isAcknowledged(id: "tool", field: command.field))
            XCTAssertEqual(checks, 0)
            XCTAssertEqual(updates, 0)
        }

        func testEnableMutationRunsThroughServiceAndWaitsForMatchingSnapshot() async {
            let service = ItemsRecordingService()
            let changed = expectation(description: "changed")
            let store = ItemsDashboardStore(
                service: service, onChanged: { changed.fulfill() }, actions: actions()
            )
            store.apply(model(items: [item("tool", status: .disabled)]))

            store.setEnabled(id: "tool", enabled: true)
            await fulfillment(of: [changed], timeout: 2)

            XCTAssertEqual(service.enabledCalls, [.init(id: "tool", enabled: true)])
            XCTAssertTrue(store.isMutationPending(id: "tool"))
            store.apply(model(items: [item("tool", status: .disabled)]))
            XCTAssertTrue(store.isMutationPending(id: "tool"))
            store.apply(model(items: [item("tool", status: .ok)]))
            XCTAssertFalse(store.isMutationPending(id: "tool"))
        }

        func testControllerRetainsHostingControllerAcrossCanonicalApplies() {
            _ = NSApplication.shared
            let controller = ManageItemsViewController(
                service: ItemsRecordingService(), onChanged: {}, actions: actions()
            )
            let host = controller.hostingController

            controller.apply(model: model(items: [item("tool")]))
            controller.apply(model: model(items: [item("tool", status: .ok)]))

            XCTAssertTrue(controller.hostingController === host)
            XCTAssertTrue(controller.view === host.view)
        }

        private func actions() -> MenuBarPopoverActions {
            MenuBarPopoverActions(
                check: {}, update: { _ in }, retry: { _ in }, setApproval: { _, _, _ in },
                stop: {}, dashboard: { _ in }, more: {}
            )
        }

        private func model(
            items: [StatusItem]? = nil, command: CommandApprovalStatus? = nil
        ) -> MenuBarPopoverModel {
            let items = items ?? [item("tool", status: .untrusted)]
            var result = MenuBarPopoverModel()
            result.update(
                state: state(items),
                approvals: command.map { ["tool": [$0]] } ?? [:]
            )
            return result
        }

        private func state(_ providedItems: [StatusItem]? = nil) -> MenuBarState {
            let items = providedItems ?? [item("tool", status: .untrusted)]
            return MenuBarState(
                title: "Items", badgeValue: nil,
                outdatedItems: items.filter { $0.status == .outdated },
                approvalItems: items.filter { $0.status == .untrusted },
                errorItems: items.filter { $0.status == .error },
                okItems: items.filter { $0.status == .ok }, allItems: items
            )
        }

        private func item(_ id: String, status: ItemStatus = .outdated) -> StatusItem {
            StatusItem(
                id: id, name: id.capitalized, category: "cli", current: "1", latest: "2",
                status: status, pinned: false, lastChecked: nil,
                error: status == .error ? "failed" : nil
            )
        }

        private func approval(fingerprint: String) -> CommandApprovalStatus {
            CommandApprovalStatus(
                field: "update.cmd", approved: false, fingerprint: fingerprint,
                command: "tool update", cwd: "/tmp"
            )
        }

        private func planItem(_ id: String) -> UpdatePlanItem {
            UpdatePlanItem(
                id: id, name: id, decision: .willUpdate, current: "1", latest: "2",
                commandFingerprint: "fingerprint"
            )
        }

        private func result(_ id: String, outcome: UpdateOutcome) -> UpdateResult {
            UpdateResult(
                id: id, name: id, outcome: outcome, current: "1", latest: "2",
                error: outcome == .failed ? "bad" : nil, commandFingerprint: "fingerprint"
            )
        }
    }

    private final class ItemsRecordingService: MenuBarServicing, @unchecked Sendable {
        struct EnabledCall: Equatable {
            var id: String
            var enabled: Bool
        }

        private let lock = NSLock()
        private var calls: [EnabledCall] = []
        var enabledCalls: [EnabledCall] { lock.withLock { calls } }

        func setEnabled(id: String, enabled: Bool) throws {
            lock.withLock { calls.append(EnabledCall(id: id, enabled: enabled)) }
        }

        func status(refresh: Bool) throws -> StatusSnapshot { fatalError("unused") }
        func scan(category: String?) throws -> ScanReport { fatalError("unused") }
        func registerScannedCandidates(
            _ candidates: [ScanCandidate], selectedIDs: [String], replace: Bool
        ) throws -> InitSummary { fatalError("unused") }
        func loadConfig() throws -> Config { fatalError("unused") }
        func saveConfig(_ config: Config) throws { fatalError("unused") }
        func checkNow(cancellationToken: CancellationToken?) throws { fatalError("unused") }
        func update(
            ids: [String], cancellationToken: CancellationToken?,
            onEvent: UpdateProgressHandler?, stopSignal: UpdateStopSignal?
        ) throws { fatalError("unused") }
        func updateAllApproved(
            cancellationToken: CancellationToken?, onEvent: UpdateProgressHandler?,
            stopSignal: UpdateStopSignal?
        ) throws { fatalError("unused") }
        func approvals(id: String) throws -> [CommandApprovalStatus] { fatalError("unused") }
        func approve(id: String, field: String, cancellationToken: CancellationToken?) throws {
            fatalError("unused")
        }
        func revoke(id: String, field: String, cancellationToken: CancellationToken?) throws {
            fatalError("unused")
        }
        func history(since: Date?) throws -> [HistoryEvent] { fatalError("unused") }
    }
#endif
