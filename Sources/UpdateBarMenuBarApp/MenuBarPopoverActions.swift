#if os(macOS)
    import UpdateBarCore
    import UpdateBarMenuBar

    @MainActor
    struct MenuBarPopoverActions {
        var check: () -> Void
        var update: ([String]) -> Void
        var retry: ([String]) -> Void
        var setApproval: (String, CommandApprovalStatus, Bool) -> Void
        var stop: () -> Void
        var dashboard: (DashboardSection) -> Void
        var more: () -> Void
    }
#endif
