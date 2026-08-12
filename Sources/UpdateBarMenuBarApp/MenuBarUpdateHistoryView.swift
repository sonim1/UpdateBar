#if os(macOS)
    import AppKit
    import UpdateBarMenuBar

    final class MenuBarUpdateHistoryView: NSView {
        private let history: MenuBarUpdateHistory

        init(history: MenuBarUpdateHistory) {
            self.history = history
            super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 72))
            setAccessibilityElement(true)
            setAccessibilityRole(.group)
            setAccessibilityLabel("Libraries updated in the last 30 days")
            setAccessibilityValue(Self.accessibilitySummary(for: history))
        }

        required init?(coder: NSCoder) { nil }

        static func accessibilitySummary(for history: MenuBarUpdateHistory) -> String {
            let totalNoun = history.totalUpdates == 1 ? "update" : "updates"
            let dailyCounts = history.buckets.map(\.count).map(String.init).joined(separator: ", ")
            return "\(history.totalUpdates) \(totalNoun). Daily counts: \(dailyCounts)."
        }

        static func barHeights(for counts: [Int]) -> [CGFloat] {
            let maximum = max(1, counts.max() ?? 0)
            return counts.map { max(2, CGFloat($0) / CGFloat(maximum) * 26) }
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            let title = "Libraries updated · Last 30 days"
            title.draw(
                at: NSPoint(x: 12, y: 50),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )
            let total = "\(history.totalUpdates)"
            total.draw(
                at: NSPoint(x: 232, y: 50),
                withAttributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.labelColor,
                ]
            )
            let counts = history.buckets.map(\.count)
            let heights = Self.barHeights(for: counts)
            let barWidth: CGFloat = 6
            let gap: CGFloat = 2
            for (index, count) in counts.enumerated() {
                let height = heights[index]
                let rect = NSRect(
                    x: 12 + CGFloat(index) * (barWidth + gap),
                    y: 12,
                    width: barWidth,
                    height: height
                )
                NSColor.controlAccentColor.withAlphaComponent(count == 0 ? 0.18 : 0.78).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            }
        }
    }
#endif
