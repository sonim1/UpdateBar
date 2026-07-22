import AppKit

public enum MenuBarStatusIconState: Equatable, Sendable {
    case checking
    case upToDate
    case updates(count: Int)
    case attention

    public var badgeText: String {
        switch self {
        case .checking:
            "…"
        case .upToDate:
            "✓"
        case .updates(let count):
            count > 9 ? "9+" : "\(max(1, count))"
        case .attention:
            "!"
        }
    }
}

extension MenuBarState {
    public var statusIconState: MenuBarStatusIconState {
        if !outdatedItems.isEmpty {
            return .updates(count: outdatedItems.count)
        }
        if needsAttentionCount > 0 {
            return .attention
        }
        return .upToDate
    }
}
