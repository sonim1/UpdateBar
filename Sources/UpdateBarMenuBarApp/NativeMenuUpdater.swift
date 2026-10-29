#if os(macOS)
    import AppKit

    @MainActor
    enum NativeMenuUpdater {
        static func apply(_ source: NSMenu, to menu: NSMenu) {
            menu.autoenablesItems = false
            let desiredItems = source.items
            let identifiers = Set(desiredItems.compactMap(\.identifier))
            for item in menu.items where !identifiers.contains(item.identifier ?? .init("")) {
                menu.removeItem(item)
            }
            for (index, desired) in desiredItems.enumerated() {
                let item: NSMenuItem
                if let existing = menu.items.first(where: { $0.identifier == desired.identifier }) {
                    update(existing, from: desired)
                    item = existing
                } else {
                    source.removeItem(desired)
                    item = desired
                }
                if menu.index(of: item) != index {
                    if item.menu === menu { menu.removeItem(item) }
                    menu.insertItem(item, at: index)
                }
            }
        }

        private static func update(_ item: NSMenuItem, from desired: NSMenuItem) {
            item.title = desired.title
            item.image = desired.image
            item.toolTip = desired.toolTip
            item.state = desired.state
            item.action = desired.action
            item.target = desired.target
            item.representedObject = desired.representedObject
            item.isEnabled = desired.isEnabled
            if let source = desired.submenu, let submenu = item.submenu {
                apply(source, to: submenu)
            } else {
                let submenu = desired.submenu
                desired.submenu = nil
                item.submenu = submenu
            }
            if let history = desired.view as? MenuBarUpdateHistoryView,
                let view = item.view as? MenuBarUpdateHistoryView
            {
                view.apply(history.history)
            } else if item.view !== desired.view {
                item.view = desired.view
            }
        }
    }
#endif
