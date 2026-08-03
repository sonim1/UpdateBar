import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class SidebarUpdateQueueModelTests: XCTestCase {
    func testBuildsVisibleQueueItemWithVersionChange() {
        let queue = SidebarUpdateQueueModel.make(
            outdatedItems: [item("node", current: "20", latest: "22")],
            limit: 3
        )

        XCTAssertTrue(queue.isVisible)
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.items.first?.title, "node")
        XCTAssertEqual(queue.items.first?.versionChange, "20 → 22")
        XCTAssertEqual(queue.items.first?.id, "node")
        XCTAssertEqual(queue.overflowCount, 0)
    }

    func testCapsRowsAndReportsOverflow() {
        let queue = SidebarUpdateQueueModel.make(
            outdatedItems: (0..<4).map { index in
                item("tool-\(index)", current: "1", latest: "2")
            },
            limit: 3
        )

        XCTAssertEqual(queue.items.map(\.id), ["tool-0", "tool-1", "tool-2"])
        XCTAssertEqual(queue.overflowCount, 1)
        XCTAssertEqual(queue.count, 4)
    }

    func testEmptyQueueIsHidden() {
        let queue = SidebarUpdateQueueModel.make(outdatedItems: [], limit: 3)

        XCTAssertFalse(queue.isVisible)
        XCTAssertEqual(queue.count, 0)
        XCTAssertTrue(queue.items.isEmpty)
    }

    func testRedactsItemAndVersionValues() {
        let queue = SidebarUpdateQueueModel.make(
            outdatedItems: [
                item(
                    "NPM_TOKEN=npm_secret",
                    current: "AWS_SECRET_ACCESS_KEY=aws-old",
                    latest: "NPM_TOKEN=npm-new"
                )
            ],
            limit: 3
        )

        let row = try! XCTUnwrap(queue.items.first)
        XCTAssertFalse(row.title.contains("npm_secret"))
        XCTAssertFalse(row.versionChange.contains("aws-old"))
    }

    private func item(_ name: String, current: String, latest: String) -> StatusItem {
        StatusItem(
            id: name,
            name: name,
            category: "runtime",
            current: current,
            latest: latest,
            status: .outdated,
            pinned: false,
            lastChecked: nil,
            error: nil
        )
    }
}
