#if os(macOS)
    import AppKit

    public enum MenuBarSystemImageRenderer {
        public static func apply(
            systemSymbolName: String?,
            applicationIcon: NSImage?,
            accessibilityDescription: String,
            to menuItem: NSMenuItem
        ) {
            if let systemSymbolName,
                let image = NSImage(
                    systemSymbolName: systemSymbolName,
                    accessibilityDescription: accessibilityDescription
                )
            {
                image.isTemplate = true
                menuItem.image = image
            }

            if let applicationIcon {
                applicationIcon.size = NSSize(width: 16, height: 16)
                menuItem.image = applicationIcon
            }
        }
    }
#endif
