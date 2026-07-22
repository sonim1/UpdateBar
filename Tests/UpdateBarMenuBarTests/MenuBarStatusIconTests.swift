import AppKit
import UpdateBarCore
import UpdateBarMenuBar
import XCTest

@MainActor
final class MenuBarStatusIconTests: XCTestCase {
    func testStateMapsCurrentUpdatesAndAttention() {
        XCTAssertEqual(makeState().statusIconState, .upToDate)
        XCTAssertEqual(makeState(outdated: 3).statusIconState, .updates(count: 3))
        XCTAssertEqual(makeState(attention: 1).statusIconState, .attention)
    }

    func testUpdatesTakeVisualPriorityOverAttention() {
        XCTAssertEqual(
            makeState(outdated: 2, attention: 1).statusIconState,
            .updates(count: 2)
        )
    }

    func testBadgeTextCapsCountsAtNinePlus() {
        XCTAssertEqual(MenuBarStatusIconState.checking.badgeText, "…")
        XCTAssertEqual(MenuBarStatusIconState.upToDate.badgeText, "✓")
        XCTAssertEqual(MenuBarStatusIconState.updates(count: 1).badgeText, "1")
        XCTAssertEqual(MenuBarStatusIconState.updates(count: 9).badgeText, "9")
        XCTAssertEqual(MenuBarStatusIconState.updates(count: 10).badgeText, "9+")
        XCTAssertEqual(MenuBarStatusIconState.attention.badgeText, "!")
    }

    private func makeState(outdated: Int = 0, attention: Int = 0) -> MenuBarState {
        MenuBarState(
            title: outdated > 0 ? "\(outdated) updates" : "Up to date",
            badgeValue: nil,
            outdatedItems: (0..<outdated).map { item(id: "old-\($0)", status: .outdated) },
            approvalItems: (0..<attention).map {
                item(id: "attention-\($0)", status: .untrusted)
            },
            errorItems: [],
            okItems: []
        )
    }

    private func item(id: String, status: ItemStatus) -> StatusItem {
        StatusItem(
            id: id,
            name: id,
            category: "cli",
            current: nil,
            latest: nil,
            status: status,
            pinned: false,
            lastChecked: nil,
            error: nil
        )
    }
}
