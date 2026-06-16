import Foundation
import UpdateBarCore

public struct MenuBarState: Equatable {
    public var title: String
    public var badgeValue: String?
    public var outdatedItems: [StatusItem]
    public var approvalItems: [StatusItem]
    public var errorItems: [StatusItem]
    public var okItems: [StatusItem]
    public var allItems: [StatusItem]

    public var needsAttentionCount: Int {
        approvalItems.count + errorItems.count
    }

    public init(
        title: String,
        badgeValue: String?,
        outdatedItems: [StatusItem],
        approvalItems: [StatusItem],
        errorItems: [StatusItem],
        okItems: [StatusItem],
        allItems: [StatusItem] = []
    ) {
        self.title = title
        self.badgeValue = badgeValue
        self.outdatedItems = outdatedItems
        self.approvalItems = approvalItems
        self.errorItems = errorItems
        self.okItems = okItems
        self.allItems = allItems
    }
}

public struct MenuBarStatusFormatter: Sendable {
    public init() {}

    public func makeState(from snapshot: StatusSnapshot) -> MenuBarState {
        let outdated = snapshot.items.filter { $0.status == .outdated }
        let approvals = snapshot.items.filter { $0.status == .untrusted }
        let errors = snapshot.items.filter { $0.status == .error }
        let ok = snapshot.items.filter { $0.status == .ok }
        let updateCount = outdated.count

        return MenuBarState(
            title: title(updateCount: updateCount),
            badgeValue: updateCount > 0 ? "\(updateCount)" : nil,
            outdatedItems: outdated,
            approvalItems: approvals,
            errorItems: errors,
            okItems: ok,
            allItems: snapshot.items
        )
    }

    private func title(updateCount: Int) -> String {
        switch updateCount {
        case 0:
            "Up to date"
        case 1:
            "1 update"
        default:
            "\(updateCount) updates"
        }
    }
}
