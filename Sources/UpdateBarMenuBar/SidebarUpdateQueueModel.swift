import UpdateBarCore

public struct SidebarUpdateQueueItem: Equatable, Sendable {
    public let id: String
    public let title: String
    public let versionChange: String

    public init(id: String, title: String, versionChange: String) {
        self.id = id
        self.title = title
        self.versionChange = versionChange
    }
}

public struct SidebarUpdateQueue: Equatable, Sendable {
    public let count: Int
    public let items: [SidebarUpdateQueueItem]
    public let overflowCount: Int

    public var isVisible: Bool {
        count > 0
    }

    public init(
        count: Int,
        items: [SidebarUpdateQueueItem],
        overflowCount: Int
    ) {
        self.count = count
        self.items = items
        self.overflowCount = overflowCount
    }
}

public enum SidebarUpdateQueueModel {
    public static func make(
        outdatedItems: [StatusItem],
        limit: Int
    ) -> SidebarUpdateQueue {
        let safeLimit = max(0, limit)
        let items = outdatedItems.prefix(safeLimit).map { item in
            let current = item.current.map(SecretRedactor.redact) ?? "?"
            let latest = item.latest.map(SecretRedactor.redact) ?? "?"
            return SidebarUpdateQueueItem(
                id: SecretRedactor.redact(item.id),
                title: SecretRedactor.redact(item.name),
                versionChange: "\(current) → \(latest)"
            )
        }
        return SidebarUpdateQueue(
            count: outdatedItems.count,
            items: Array(items),
            overflowCount: max(0, outdatedItems.count - safeLimit)
        )
    }
}
