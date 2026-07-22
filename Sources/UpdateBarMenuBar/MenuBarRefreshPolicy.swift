public enum MenuBarRefreshPresentationMode: Equatable, Sendable {
    case showLoading
    case preserveActionProgress
}

public enum MenuBarRefreshPolicy {
    public static func presentationMode(
        activeActionTitle: String?
    ) -> MenuBarRefreshPresentationMode {
        activeActionTitle == nil ? .showLoading : .preserveActionProgress
    }
}
