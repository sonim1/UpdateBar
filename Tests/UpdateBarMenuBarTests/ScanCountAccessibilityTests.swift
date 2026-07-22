#if os(macOS)
    import AppKit
    import UpdateBarMenuBar
    @testable import UpdateBarMenuBarApp
    import XCTest

    @MainActor
    final class ScanCountAccessibilityTests: XCTestCase {
        func testLoadedScanViewExposesThreeDirectLeafCountBadges() throws {
            let controller = ScanViewController(
                service: CoreMenuBarService(),
                onChanged: {}
            )
            _ = controller.view
            controller.view.layoutSubtreeIfNeeded()

            let badges = descendants(of: ScanCountBadgeView.self, in: controller.view)
            XCTAssertEqual(badges.count, 3)
            XCTAssertTrue(badges.allSatisfy { $0.superview is NSStackView })
            XCTAssertTrue(
                badges.allSatisfy {
                    $0.subviews.allSatisfy { !$0.isAccessibilityElement() }
                }
            )
            XCTAssertTrue(
                badges.allSatisfy {
                    descendants(of: NSTextField.self, in: $0).isEmpty
                }
            )
            XCTAssertTrue(
                badges.allSatisfy { ($0.accessibilityChildren() ?? []).isEmpty }
            )

            let textBadges = badges.compactMap { ($0 as NSView) as? NSTextField }
            XCTAssertEqual(textBadges.count, 3)
            XCTAssertEqual(textBadges.map(\.stringValue), ["0", "0", "0"])
            XCTAssertEqual(badges.filter { $0.isAccessibilityElement() }.count, 3)
            XCTAssertEqual(
                badges.compactMap { $0.accessibilityLabel() },
                ["Discovered", "Enabled", "Disabled"]
            )
            XCTAssertEqual(
                badges.compactMap { $0.accessibilityValue() },
                ["0", "0", "0"]
            )

            let expectedHelp = DashboardPresentationModel()
                .scanCounts(discovered: 0, enabled: 0, disabled: 0)
                .map(\.help)
            XCTAssertEqual(badges.compactMap { $0.accessibilityHelp() }, expectedHelp)
        }

        func testBadgeUpdateKeepsVisibleAndAccessibilityValuesCurrent() throws {
            let model = DashboardPresentationModel()
            let badge = ScanCountBadgeView(frame: .zero)
            let textBadge = try XCTUnwrap((badge as NSView) as? NSTextField)

            XCTAssertTrue(badge.subviews.isEmpty)
            XCTAssertTrue(badge.isAccessibilityElement())
            XCTAssertEqual(badge.accessibilityRole(), .staticText)
            XCTAssertEqual(textBadge.alignment, .center)
            XCTAssertEqual(
                textBadge.font,
                .monospacedDigitSystemFont(
                    ofSize: NSFont.systemFontSize,
                    weight: .semibold
                )
            )
            XCTAssertTrue(badge.wantsLayer)
            XCTAssertEqual(badge.layer?.cornerRadius, 6)
            XCTAssertEqual(badge.layer?.backgroundColor, NSColor.controlBackgroundColor.cgColor)
            XCTAssertTrue(
                badge.constraints.contains {
                    $0.firstAttribute == .height && $0.relation == .equal && $0.constant == 30
                }
            )

            let initial = try XCTUnwrap(
                model.scanCounts(discovered: 32, enabled: 1, disabled: 0).first
            )
            badge.apply(initial)

            XCTAssertEqual(textBadge.stringValue, "32")
            XCTAssertEqual(badge.accessibilityLabel(), "Discovered")
            XCTAssertEqual(badge.accessibilityValue(), "32")
            XCTAssertEqual(badge.accessibilityHelp(), initial.help)
            XCTAssertEqual(badge.toolTip, initial.help)

            let updated = try XCTUnwrap(
                model.scanCounts(discovered: 7, enabled: 1, disabled: 0).first
            )
            badge.apply(updated)

            XCTAssertEqual(textBadge.stringValue, "7")
            XCTAssertEqual(badge.accessibilityLabel(), "Discovered")
            XCTAssertEqual(badge.accessibilityValue(), "7")
            XCTAssertEqual(badge.accessibilityHelp(), updated.help)
            XCTAssertEqual(badge.toolTip, updated.help)
        }

        private func descendants<View: NSView>(
            of type: View.Type,
            in root: NSView
        ) -> [View] {
            var matches = root.subviews.compactMap { $0 as? View }
            for subview in root.subviews {
                matches.append(contentsOf: descendants(of: type, in: subview))
            }
            return matches
        }
    }
#endif
