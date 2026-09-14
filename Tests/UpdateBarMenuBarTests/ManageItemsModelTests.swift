import UpdateBarCore
import XCTest

@testable import UpdateBarMenuBar

final class ManageItemsModelTests: XCTestCase {
    func testPartitionsEveryItemIntoExactlyOneStatusSection() {
        let items = [
            item("ready", .outdated), item("untrusted", .untrusted),
            item("approved-check", .untrusted), item("error", .error),
            item("differs", .differs), item("checking", .checking), item("current", .ok),
            item("disabled", .disabled), item("pinned", .outdated, pinned: true),
        ]
        var popover = model(items: items, approvalIDs: ["untrusted"])
        popover.update(
            state: state(items),
            approvals: [
                "untrusted": [approval(approved: false)],
                "approved-check": [approval(approved: true)],
            ]
        )

        let sections = ManageItemsModel().sections(from: popover, query: "")

        XCTAssertEqual(sections.map(\.kind), ManageItemsSectionKind.allCases)
        XCTAssertEqual(ids(in: .ready, sections), ["ready"])
        XCTAssertEqual(ids(in: .review, sections), ["approved-check", "untrusted"])
        XCTAssertEqual(ids(in: .attention, sections), ["checking", "differs", "error"])
        XCTAssertEqual(ids(in: .current, sections), ["current"])
        XCTAssertEqual(ids(in: .paused, sections), ["disabled", "pinned"])
        XCTAssertEqual(Set(sections.flatMap { $0.items.map(\.id) }), Set(items.map(\.id)))
        XCTAssertEqual(sections.reduce(0) { $0 + $1.items.count }, items.count)
    }

    func testCanonicalEligibilityExcludesPinnedAndUnapprovedItems() {
        let items = [
            item("ready", .outdated), item("pinned-flag", .outdated, pinned: true),
            item("pinned-status", .pinned), item("untrusted", .untrusted),
            item("approval-attention", .outdated),
        ]
        var popover = model(items: items, approvalIDs: ["approval-attention"])
        popover.update(
            state: state(items, approvalIDs: ["approval-attention"]),
            approvals: ["approval-attention": [approval(approved: false)]]
        )

        let action = ManageItemsModel().primaryAction(from: popover, query: "", selectedIDs: [])

        XCTAssertEqual(action.title, "Update all (1)")
        XCTAssertEqual(action.ids, ["ready"])
    }

    func testSearchFiltersAcrossIdentityAndVersionAndExpandsCollapsedSections() {
        let items = [
            item("python", .ok, name: "Python", category: "runtime", current: "3.13.2"),
            item("ruby", .disabled, name: "Ruby", category: "language", current: "3.3.2"),
        ]
        let popover = model(items: items)

        let versionMatch = ManageItemsModel().sections(from: popover, query: "3.13")
        let categoryMatch = ManageItemsModel().sections(from: popover, query: "language")

        XCTAssertEqual(ids(in: .current, versionMatch), ["python"])
        XCTAssertTrue(versionMatch.first { $0.kind == .current }?.isExpanded == true)
        XCTAssertEqual(ids(in: .paused, categoryMatch), ["ruby"])
        XCTAssertTrue(categoryMatch.first { $0.kind == .paused }?.isExpanded == true)
    }

    func testSearchClearsSelectionAndScopesUnselectedActionToVisibleEligibleItems() {
        let items = [
            item("alpha", .outdated, name: "Alpha"), item("beta", .outdated, name: "Beta"),
            item("current", .ok, name: "Alpha Current"),
        ]
        let popover = model(items: items)
        var selection = ManageItemsSelectionModel()
        selection.toggle(item: items[0], in: popover)

        selection.setQuery("beta")
        let action = ManageItemsModel().primaryAction(
            from: popover, query: selection.query, selectedIDs: selection.selectedIDs
        )

        XCTAssertTrue(selection.selectedIDs.isEmpty)
        XCTAssertEqual(action.title, "Update visible (1)")
        XCTAssertEqual(action.ids, ["beta"])
    }

    func testEveryQueryChangeClearsSelectionIncludingClearingSearch() {
        let tool = item("tool", .outdated)
        let popover = model(items: [tool])
        var selection = ManageItemsSelectionModel()
        selection.toggle(item: tool, in: popover)
        selection.setQuery("tool")
        selection.toggle(item: tool, in: popover)

        selection.setQuery("")

        XCTAssertTrue(selection.selectedIDs.isEmpty)
    }

    func testRefreshPrunesSelectedItemThatNoLongerMatchesSearch() {
        let original = item("tool", .outdated, name: "Alpha")
        var selection = ManageItemsSelectionModel()
        selection.setQuery("alpha")
        selection.toggle(item: original, in: model(items: [original]))
        let renamed = item("tool", .outdated, name: "Beta")
        let refreshed = model(items: [renamed])
        let visibleIDs = Set(
            ManageItemsModel().sections(from: refreshed, query: selection.query)
                .flatMap { $0.items.map(\.id) }
        )

        selection.reconcile(with: refreshed, visibleIDs: visibleIDs)

        XCTAssertTrue(selection.selectedIDs.isEmpty)
        XCTAssertEqual(
            ManageItemsModel().primaryAction(
                from: refreshed, query: selection.query, selectedIDs: ["tool"]
            ).ids,
            []
        )
    }

    func testSelectionWinsOverSearchlessUpdateAll() {
        let items = [item("alpha", .outdated), item("beta", .outdated)]
        let popover = model(items: items)
        var selection = ManageItemsSelectionModel()
        selection.toggle(item: items[1], in: popover)

        let action = ManageItemsModel().primaryAction(
            from: popover, query: "", selectedIDs: selection.selectedIDs
        )

        XCTAssertEqual(action.title, "Update selected (1)")
        XCTAssertEqual(action.ids, ["beta"])
    }

    func testSelectionPersistsOnlyForSameEligibleIdentityAndVersions() {
        let original = item("tool", .outdated, current: "1", latest: "2")
        var selection = ManageItemsSelectionModel()
        selection.toggle(item: original, in: model(items: [original]))

        let same = item("tool", .outdated, current: "1", latest: "2")
        selection.reconcile(with: model(items: [same]))
        XCTAssertEqual(selection.selectedIDs, ["tool"])

        let changed = item("tool", .outdated, current: "1", latest: "3")
        selection.reconcile(with: model(items: [changed]))
        XCTAssertTrue(selection.selectedIDs.isEmpty)

        selection.toggle(item: changed, in: model(items: [changed]))
        selection.reconcile(with: model(items: [item("tool", .ok, current: "1", latest: "3")]))
        XCTAssertTrue(selection.selectedIDs.isEmpty)
    }

    func testReadyPlacementStaysStableWhilePlannedBatchIsActive() {
        let failed = item("tool", .error)
        var progress = MenuBarItemProgress()
        progress.apply(.planned([planItem(id: "tool")]))
        var popover = MenuBarPopoverModel()
        popover.update(
            state: state([failed]), approvals: [:], progress: progress,
            activeActionTitle: "Updating items", isUpdateAction: true
        )

        let sections = ManageItemsModel().sections(from: popover, query: "")

        XCTAssertEqual(ids(in: .ready, sections), ["tool"])
        XCTAssertEqual(ids(in: .attention, sections), [])
    }

    func testOldSuccessfulProgressDoesNotLabelChangedVersionSucceeded() {
        let changed = item("tool", .outdated, current: "2", latest: "3")
        var progress = MenuBarItemProgress()
        progress.apply(.planned([planItem(id: "tool", current: "1", latest: "2")]))
        progress.apply(
            .itemFinished(
                UpdateResult(
                    id: "tool", name: "Tool", outcome: .updated, current: "2", latest: "2",
                    error: nil, commandFingerprint: "fingerprint"
                )
            )
        )
        var popover = MenuBarPopoverModel()
        popover.update(state: state([changed]), approvals: [:], progress: progress)

        XCTAssertEqual(ManageItemsModel().statusText(for: changed, in: popover), "2  →  3")
    }

    private func ids(in kind: ManageItemsSectionKind, _ sections: [ManageItemsSection]) -> [String]
    {
        sections.first { $0.kind == kind }?.items.map(\.id) ?? []
    }

    private func model(items: [StatusItem], approvalIDs: [String] = []) -> MenuBarPopoverModel {
        var result = MenuBarPopoverModel()
        result.update(state: state(items, approvalIDs: approvalIDs), approvals: [:])
        return result
    }

    private func state(_ items: [StatusItem], approvalIDs: [String] = []) -> MenuBarState {
        MenuBarState(
            title: "Items", badgeValue: nil,
            outdatedItems: items.filter { $0.status == .outdated },
            approvalItems: items.filter { approvalIDs.contains($0.id) },
            errorItems: items.filter { $0.status == .error },
            okItems: items.filter { $0.status == .ok }, allItems: items
        )
    }

    private func item(
        _ id: String, _ status: ItemStatus, name: String? = nil, category: String = "cli",
        current: String? = "1.0", latest: String? = "2.0", pinned: Bool = false
    ) -> StatusItem {
        StatusItem(
            id: id, name: name ?? id, category: category, current: current, latest: latest,
            status: status, pinned: pinned, lastChecked: nil,
            error: status == .error ? "failed token=secret" : nil
        )
    }

    private func approval(approved: Bool) -> CommandApprovalStatus {
        CommandApprovalStatus(
            field: "update.cmd", approved: approved, fingerprint: "fingerprint",
            command: "tool update", cwd: "/tmp"
        )
    }

    private func planItem(
        id: String, current: String? = "1", latest: String? = "2"
    ) -> UpdatePlanItem {
        UpdatePlanItem(
            id: id, name: id, decision: .willUpdate, current: current, latest: latest,
            commandFingerprint: "fingerprint"
        )
    }
}

final class ManageItemsMutationGateTests: XCTestCase {
    func testExposesPendingItemForRowLocalProgress() {
        var gate = ManageItemsMutationGate()
        gate.begin(id: "tool", enabled: false)
        XCTAssertTrue(gate.isPending(id: "tool"))
        XCTAssertFalse(gate.isPending(id: "other"))
        gate.cancel()
        XCTAssertFalse(gate.isPending(id: "tool"))
    }

    func testRejectsStaleSnapshotUntilToggledStateAppears() {
        var gate = ManageItemsMutationGate()
        gate.begin(id: "tool", enabled: true)
        XCTAssertFalse(gate.accepts([item(status: .disabled)]))
        XCTAssertTrue(gate.isPending)
        XCTAssertTrue(gate.accepts([item(status: .ok)]))
        XCTAssertFalse(gate.isPending)
    }

    func testCancelAllowsSnapshotsAfterMutationFailure() {
        var gate = ManageItemsMutationGate()
        gate.begin(id: "tool", enabled: false)
        gate.cancel()
        XCTAssertTrue(gate.accepts([item(status: .ok)]))
        XCTAssertFalse(gate.isPending)
    }

    private func item(status: ItemStatus) -> StatusItem {
        StatusItem(
            id: "tool", name: "Tool", category: "cli", current: nil, latest: nil,
            status: status, pinned: false, lastChecked: nil, error: nil
        )
    }
}
