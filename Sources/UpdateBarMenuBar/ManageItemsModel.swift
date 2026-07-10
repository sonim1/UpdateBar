import Foundation
import UpdateBarCore

public enum ManageItemsRow: Equatable, Sendable {
    case category(name: String, count: Int)
    case item(ManageItemRow)
}

public struct ManageItemRow: Equatable, Sendable {
    public var id: String
    public var name: String
    public var category: String
    public var currentVersion: String
    public var latestVersion: String
    public var statusLabel: String
    public var isEnabled: Bool

    public init(
        id: String,
        name: String,
        category: String,
        currentVersion: String,
        latestVersion: String,
        statusLabel: String,
        isEnabled: Bool
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.statusLabel = statusLabel
        self.isEnabled = isEnabled
    }
}

public struct ManageItemsModel: Sendable {
    public init() {}

    /// Flattens a status snapshot into table rows: one group row per
    /// category (sorted), followed by its items sorted by display name.
    /// Disabled items stay listed so they can be re-enabled.
    public func rows(from items: [StatusItem]) -> [ManageItemsRow] {
        let grouped = Dictionary(grouping: items) { item in
            item.category.isEmpty ? "uncategorized" : item.category
        }
        var rows: [ManageItemsRow] = []
        for category in grouped.keys.sorted() {
            let members = (grouped[category] ?? []).sorted {
                $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
            }
            rows.append(.category(name: category, count: members.count))
            for item in members {
                rows.append(.item(row(from: item)))
            }
        }
        return rows
    }

    private func row(from item: StatusItem) -> ManageItemRow {
        ManageItemRow(
            id: item.id,
            name: item.name,
            category: item.category,
            currentVersion: item.current ?? "",
            latestVersion: item.latest ?? "",
            statusLabel: Self.statusLabel(for: item),
            isEnabled: item.status != .disabled
        )
    }

    private static func statusLabel(for item: StatusItem) -> String {
        switch item.status {
        case .outdated:
            return "outdated"
        case .ok:
            return "up to date"
        case .disabled:
            return "disabled"
        case .untrusted:
            return "needs approval"
        case .pinned:
            return "pinned"
        case .checking:
            return "checking"
        case .differs:
            return "differs"
        case .error:
            return item.error.map { "error: \($0)" } ?? "error"
        }
    }
}
