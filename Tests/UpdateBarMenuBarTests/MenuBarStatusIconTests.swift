import AppKit
import UpdateBarCore
import UpdateBarMenuBar
import XCTest

@MainActor
final class MenuBarStatusIconTests: XCTestCase {
    func testStateMapsCurrentUpdatesAndAttention() {
        XCTAssertEqual(makeState().statusIconState, .upToDate)
        XCTAssertEqual(makeState(outdated: 3).statusIconState, .updates(count: 3))
        XCTAssertEqual(makeState(attention: 1).statusIconState, .attention)
    }

    func testUpdatesTakeVisualPriorityOverAttention() {
        XCTAssertEqual(
            makeState(outdated: 2, attention: 1).statusIconState,
            .updates(count: 2)
        )
    }

    func testBadgeTextCapsCountsAtNinePlus() {
        XCTAssertEqual(MenuBarStatusIconState.checking.badgeText, "…")
        XCTAssertEqual(MenuBarStatusIconState.upToDate.badgeText, "✓")
        XCTAssertEqual(MenuBarStatusIconState.updates(count: 1).badgeText, "1")
        XCTAssertEqual(MenuBarStatusIconState.updates(count: 9).badgeText, "9")
        XCTAssertEqual(MenuBarStatusIconState.updates(count: 10).badgeText, "9+")
        XCTAssertEqual(MenuBarStatusIconState.attention.badgeText, "!")
    }

    func testRendererCreatesFixedTemplateImageForEveryState() {
        let renderer = MenuBarStatusIconRenderer()
        let states: [MenuBarStatusIconState] = [
            .checking, .upToDate, .updates(count: 1), .updates(count: 10), .attention,
        ]

        for state in states {
            let image = renderer.image(for: state)
            XCTAssertEqual(image.size, MenuBarStatusIconRenderer.imageSize)
            XCTAssertTrue(image.isTemplate)
            XCTAssertFalse(image.representations.isEmpty)
        }
    }

    func testRendererOverlaysBadgeInsideCompactCanvas() throws {
        let image = MenuBarStatusIconRenderer().image(for: .attention)

        XCTAssertEqual(image.size, NSSize(width: 20, height: 18))
        XCTAssertGreaterThan(
            try alpha(in: image, at: NSPoint(x: 8, y: 16)),
            0.8,
            "The arrow head should remain opaque"
        )
        XCTAssertLessThan(
            try alpha(in: image, at: NSPoint(x: 11.5, y: 13)),
            0.1,
            "The badge knockout should clear the brand underneath"
        )
        // AppKit's rasterizer leaves the exact rightmost cardinal sample at
        // (19, 6.75) transparent for this half-point-aligned stroke. Sample
        // the stable upper stroke coverage instead.
        XCTAssertGreaterThan(
            try alpha(in: image, at: NSPoint(x: 13.75, y: 12.5)),
            0.5,
            "The badge outline should remain opaque at the compact canvas edge"
        )
    }

    func testAttentionUsesHeavyBadgeWeight() {
        XCTAssertEqual(MenuBarStatusIconState.attention.badgeWeight, .heavy)
        XCTAssertEqual(MenuBarStatusIconState.upToDate.badgeWeight, .bold)
    }

    private func alpha(
        in image: NSImage,
        at point: NSPoint,
        scale: CGFloat = 4
    ) throws -> CGFloat {
        let pixelsWide = Int(image.size.width * scale)
        let pixelsHigh = Int(image.size.height * scale)
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelsWide,
                pixelsHigh: pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        bitmap.size = image.size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: image.size))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let color = try XCTUnwrap(
            bitmap.colorAt(
                x: Int(point.x * scale),
                y: Int(point.y * scale)
            )
        )
        return color.alphaComponent
    }

    private func makeState(outdated: Int = 0, attention: Int = 0) -> MenuBarState {
        MenuBarState(
            title: outdated > 0 ? "\(outdated) updates" : "Up to date",
            badgeValue: nil,
            outdatedItems: (0..<outdated).map { item(id: "old-\($0)", status: .outdated) },
            approvalItems: (0..<attention).map {
                item(id: "attention-\($0)", status: .untrusted)
            },
            errorItems: [],
            okItems: []
        )
    }

    private func item(id: String, status: ItemStatus) -> StatusItem {
        StatusItem(
            id: id,
            name: id,
            category: "cli",
            current: nil,
            latest: nil,
            status: status,
            pinned: false,
            lastChecked: nil,
            error: nil
        )
    }
}
