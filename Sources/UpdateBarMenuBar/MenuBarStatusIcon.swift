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

extension MenuBarStatusIconState {
    public var badgeWeight: NSFont.Weight {
        self == .attention ? .heavy : .bold
    }
}

@MainActor
public struct MenuBarStatusIconRenderer {
    public static let imageSize = NSSize(width: 34, height: 18)

    public init() {}

    public func image(for state: MenuBarStatusIconState) -> NSImage {
        let image = NSImage(size: Self.imageSize, flipped: false) { _ in
            NSGraphicsContext.current?.shouldAntialias = true
            NSColor.black.setFill()
            NSColor.black.setStroke()
            drawBrandMark()
            drawBadge(for: state)
            return true
        }
        image.isTemplate = true
        return image
    }

    private func drawBrandMark() {
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 8, y: 17))
        arrow.line(to: NSPoint(x: 15.5, y: 9.5))
        arrow.line(to: NSPoint(x: 11.5, y: 9.5))
        arrow.line(to: NSPoint(x: 11.5, y: 4.2))
        arrow.line(to: NSPoint(x: 8, y: 6))
        arrow.line(to: NSPoint(x: 4.5, y: 4.2))
        arrow.line(to: NSPoint(x: 4.5, y: 9.5))
        arrow.line(to: NSPoint(x: 0.5, y: 9.5))
        arrow.close()
        arrow.fill()

        let bar = NSBezierPath(
            roundedRect: NSRect(x: 2, y: 0.5, width: 12, height: 2),
            xRadius: 1,
            yRadius: 1
        )
        bar.fill()
    }

    private func drawBadge(for state: MenuBarStatusIconState) {
        let circleRect = NSRect(x: 20, y: 2, width: 14, height: 14)
        let circle = NSBezierPath(ovalIn: circleRect.insetBy(dx: 0.8, dy: 0.8))
        circle.lineWidth = 1.6
        circle.stroke()

        let text = state.badgeText as NSString
        let fontSize: CGFloat = text.length > 1 ? 7 : 9.5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: state.badgeWeight),
            .foregroundColor: NSColor.black,
        ]
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(
            x: circleRect.midX - size.width / 2,
            y: circleRect.midY - size.height / 2 + 0.4
        )
        text.draw(at: origin, withAttributes: attributes)
    }
}
