import Foundation
import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class MenuBarPopoverModelTests: XCTestCase {
    func testPreservesDeselectionAcrossSnapshotsAndPrunesDeletedItems() {
        let first = item("first")
        let second = item("second")
        var model = MenuBarPopoverModel()
        model.update(state: state([first, second]), approvals: [:])
        XCTAssertEqual(model.selectedIDs, ["first", "second"])

        model.setSelected(false, id: "first")
        model.showDetails(id: "first")
        model.update(state: state([first, second, item("new")]), approvals: [:])

        XCTAssertEqual(model.selectedIDs, ["second", "new"])
        XCTAssertEqual(model.detailItem?.id, "first")

        model.update(state: state([second]), approvals: [:])
        model.update(state: state([first, second]), approvals: [:])
        XCTAssertEqual(model.selectedIDs, ["first", "second"])
        XCTAssertNil(model.detailItem)
    }

    func testNewVersionPairIsSelectedAfterPreviousUpdateSucceeds() {
        let original = item("tool")
        var model = MenuBarPopoverModel()
        model.update(state: state([original]), approvals: [:])
        XCTAssertEqual(model.selectedIDs, ["tool"])

        var current = original
        current.status = .ok
        current.current = "2.0"
        model.update(state: state([current]), approvals: [:])
        XCTAssertTrue(model.selectedIDs.isEmpty)

        var newer = current
        newer.status = .outdated
        newer.latest = "3.0"
        model.update(state: state([newer]), approvals: [:])
        XCTAssertEqual(model.selectedIDs, ["tool"])
    }

    func testSameVersionChoicesSurviveIntermediateCheckingWithUnknownVersions() {
        let items = [item("deselected"), item("selected")]
        var model = MenuBarPopoverModel()
        model.update(state: state(items), approvals: [:])
        model.setSelected(false, id: "deselected")

        let checking = items.map { item in
            var transient = item
            transient.status = .checking
            transient.current = nil
            transient.latest = nil
            return transient
        }
        model.update(state: state(checking), approvals: [:])
        XCTAssertTrue(model.selectedIDs.isEmpty)

        model.update(state: state(items), approvals: [:])
        XCTAssertEqual(model.selectedIDs, ["selected"])
    }

    func testExcludesPinnedDisabledAndUnapprovedItemsEvenWhenStateIsStale() {
        var pinned = item("pinned")
        pinned.pinned = true
        let items = [
            item("eligible"), pinned, item("disabled", status: .disabled),
            item("untrusted", status: .untrusted), item("changed"),
        ]
        var model = MenuBarPopoverModel()
        model.update(
            state: state(items), approvals: ["changed": [approval(approved: false)]]
        )
        XCTAssertEqual(model.selectedIDs, ["eligible"])
        XCTAssertEqual(model.eligibleItems.map(\.id), ["eligible"])

        model.setSelected(true, id: "changed")
        XCTAssertEqual(model.selectedIDs, ["eligible"])

        model.update(
            state: state(items), approvals: ["eligible": [approval(approved: false)]]
        )
        XCTAssertFalse(model.selectedIDs.contains("eligible"))
    }

    func testLastCheckedUsesMostRecentItemDateAndRemainsNilWithoutChecks() {
        var older = item("older")
        older.lastChecked = Date(timeIntervalSince1970: 100)
        var newer = item("newer")
        newer.lastChecked = Date(timeIntervalSince1970: 200)
        var model = MenuBarPopoverModel()
        model.update(state: state([older, newer]), approvals: [:])
        XCTAssertEqual(model.lastChecked, newer.lastChecked)

        model.update(state: state([item("unchecked", status: .checking)]), approvals: [:])
        XCTAssertNil(model.lastChecked)
        XCTAssertFalse(model.isAllCurrent)
        XCTAssertFalse(model.isFirstRun)
        model.update(state: state([]), approvals: [:])
        XCTAssertTrue(model.isFirstRun)
    }

    func testCommandAcknowledgementIsPerFieldAndRequiredBeforeApproval() {
        let check = approval(field: "check.cmd", approved: false)
        let update = approval(field: "update.cmd", approved: false)
        var model = MenuBarPopoverModel()
        model.update(
            state: state([item("tool", status: .untrusted)]),
            approvals: ["tool": [check, update]]
        )

        XCTAssertNil(model.reviewedApproval(id: "tool", field: "check.cmd"))
        model.setAcknowledged(true, id: "tool", field: "check.cmd")
        XCTAssertEqual(model.reviewedApproval(id: "tool", field: "check.cmd"), check)
        XCTAssertNil(model.reviewedApproval(id: "tool", field: "update.cmd"))
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

    func testApprovedCommandsWithCachedUntrustedStatusAreReadyToCheckButNotUpdate() {
        let commands = ["check.cmd", "latest.cmd", "update.cmd"].map {
            approval(field: $0, approved: true)
        }
        var model = MenuBarPopoverModel()
        model.update(
            state: state([item("tool", status: .untrusted)]), approvals: ["tool": commands]
        )

        XCTAssertTrue(model.approvalItems.isEmpty)
        XCTAssertEqual(model.readyToCheckItems.map(\.id), ["tool"])
        XCTAssertTrue(model.eligibleItems.isEmpty)
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

    func testReadinessRequiresNonemptyFullyApprovedCommandStatuses() {
        let snapshot = state([item("tool", status: .untrusted)])
        var model = MenuBarPopoverModel()
        for commands in [
            [],
            [approval(field: "check.cmd", approved: true), approval(approved: false)],
        ] {
            model.update(state: snapshot, approvals: ["tool": commands])
            XCTAssertEqual(model.approvalItems.map(\.id), ["tool"])
            XCTAssertTrue(model.readyToCheckItems.isEmpty)
        }
    }

    func testAcknowledgementResetsForEveryChangedCommandIdentityField() {
        let original = approval(approved: false)
        var variants = [CommandApprovalStatus]()
        var changed = original
        changed.fingerprint = "different"
        variants.append(changed)
        changed = original
        changed.command = "tool update --changed"
        variants.append(changed)
        changed = original
        changed.cwd = "/different folder"
        variants.append(changed)
        changed = original
        changed.approved = true
        variants.append(changed)

        for variant in variants {
            var model = MenuBarPopoverModel()
            model.update(state: state([item("tool")]), approvals: ["tool": [original]])
            model.setAcknowledged(true, id: "tool", field: original.field)
            XCTAssertTrue(model.isAcknowledged(id: "tool", field: original.field))

            model.update(state: state([item("tool")]), approvals: ["tool": [variant]])
            XCTAssertFalse(model.isAcknowledged(id: "tool", field: original.field))
        }
    }

    func testAcknowledgementResetsWhenItemStatusChangesOrFieldDisappears() {
        let command = approval(approved: false)
        var model = MenuBarPopoverModel()
        model.update(state: state([item("tool")]), approvals: ["tool": [command]])
        model.setAcknowledged(true, id: "tool", field: command.field)
        model.update(
            state: state([item("tool", status: .error)]), approvals: ["tool": [command]]
        )
        XCTAssertFalse(model.isAcknowledged(id: "tool", field: command.field))

        model.setAcknowledged(true, id: "tool", field: command.field)
        model.update(state: state([item("tool", status: .error)]), approvals: [:])
        model.update(
            state: state([item("tool", status: .error)]), approvals: ["tool": [command]]
        )
        XCTAssertFalse(model.isAcknowledged(id: "tool", field: command.field))
    }

    func testUnchangedRefreshPreservesAcknowledgementAndBusyPreventsMutation() {
        let command = approval(approved: false)
        let snapshot = state([item("tool")])
        var model = MenuBarPopoverModel()
        model.update(state: snapshot, approvals: ["tool": [command]])
        model.setAcknowledged(true, id: "tool", field: command.field)
        model.update(
            state: snapshot, approvals: ["tool": [command]], activeActionTitle: "Check Now"
        )
        XCTAssertTrue(model.isAcknowledged(id: "tool", field: command.field))
        XCTAssertNil(model.reviewedApproval(id: "tool", field: command.field))
        XCTAssertTrue(model.isBusy)
        XCTAssertFalse(model.isUpdating)

        model.update(state: snapshot, approvals: ["tool": [command]])
        XCTAssertEqual(model.reviewedApproval(id: "tool", field: command.field), command)
    }

    func testProgressDistinguishesQueuedRunningSucceededAndFailedAndRetainsResults() {
        let ids = ["queued", "running", "success", "failure"]
        var progress = MenuBarItemProgress()
        progress.apply(.planned(ids.map(planItem)))
        progress.apply(.itemStarted(id: "running", name: "running"))
        progress.apply(.itemFinished(result("success", outcome: .updated)))
        progress.apply(.itemFinished(result("failure", outcome: .failed)))
        var model = MenuBarPopoverModel()
        model.update(
            state: state(ids.map { item($0) }), approvals: [:], progress: progress,
            activeActionTitle: "Update Selected", isUpdateAction: true
        )
        XCTAssertEqual(model.phase(for: "queued"), .queued)
        XCTAssertEqual(model.phase(for: "running"), .running)
        XCTAssertEqual(model.phase(for: "success"), .succeeded)
        XCTAssertEqual(model.phase(for: "failure"), .failed)
        XCTAssertEqual(model.progress.completedCount, 2)
        XCTAssertEqual(model.progress.totalCount, 4)
        XCTAssertTrue(model.isUpdating)

        progress.inFlightIDs = []
        model.update(state: state(ids.map { item($0) }), approvals: [:], progress: progress)
        XCTAssertEqual(model.phase(for: "queued"), .notStarted)
        XCTAssertEqual(model.phase(for: "success"), .succeeded)
        XCTAssertEqual(model.phase(for: "failure"), .failed)
        XCTAssertEqual(model.retryIDs, ["failure"])
        XCTAssertFalse(model.isUpdating)
    }

    func testRetryContainsOnlyFailedItemsStillAllowedToRun() {
        let ids = ["success", "failure", "pinned", "disabled", "unapproved", "cancelled"]
        var progress = MenuBarItemProgress()
        progress.apply(.planned(ids.map(planItem)))
        for id in ids {
            let outcome: UpdateOutcome =
                id == "success" ? .updated : (id == "cancelled" ? .cancelled : .failed)
            progress.apply(.itemFinished(result(id, outcome: outcome)))
        }
        var pinned = item("pinned", status: .error)
        pinned.pinned = true
        var model = MenuBarPopoverModel()
        model.update(
            state: state([
                item("success", status: .ok), item("failure", status: .error), pinned,
                item("disabled", status: .disabled), item("unapproved", status: .error),
                item("cancelled", status: .error),
            ]),
            approvals: ["unapproved": [approval(approved: false)]], progress: progress
        )
        XCTAssertEqual(model.retryIDs, ["failure"])
        XCTAssertEqual(model.phase(for: "cancelled"), .cancelled)
    }

    private func item(_ id: String, status: ItemStatus = .outdated) -> StatusItem {
        StatusItem(
            id: id, name: id, category: "cli", current: "1.0", latest: "2.0", status: status,
            pinned: false, lastChecked: nil, error: status == .error ? "Command failed" : nil
        )
    }

    private func state(_ items: [StatusItem]) -> MenuBarState {
        MenuBarState(
            title: "Updates", badgeValue: nil,
            outdatedItems: items.filter { $0.status == .outdated },
            approvalItems: items.filter { $0.status == .untrusted },
            errorItems: items.filter { $0.status == .error },
            okItems: items.filter { $0.status == .ok }, allItems: items
        )
    }

    private func approval(
        field: String = "update.cmd", approved: Bool
    ) -> CommandApprovalStatus {
        CommandApprovalStatus(
            field: field, approved: approved, fingerprint: "fingerprint",
            command: "tool update", cwd: "/working folder"
        )
    }

    private func planItem(_ id: String) -> UpdatePlanItem {
        UpdatePlanItem(
            id: id, name: id, decision: .willUpdate, current: "1.0", latest: "2.0",
            commandFingerprint: "fingerprint"
        )
    }

    private func result(_ id: String, outcome: UpdateOutcome) -> UpdateResult {
        UpdateResult(
            id: id, name: id, outcome: outcome, current: "1.0", latest: "2.0",
            error: outcome == .failed ? "Command failed" : nil, commandFingerprint: "fingerprint"
        )
    }
}
