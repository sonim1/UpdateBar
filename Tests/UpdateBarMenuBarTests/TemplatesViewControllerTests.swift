#if os(macOS)
    import AppKit
    @testable import UpdateBarMenuBarApp
    import XCTest

    @MainActor
    final class TemplatesViewControllerTests: XCTestCase {
        func testRendersSixAccessibleCopyButtonsAndThreeCategories() {
            let controller = TemplatesViewController(writeToPasteboard: { _ in true })

            _ = controller.view

            let copyButtons = descendants(of: NSButton.self, in: controller.view).filter {
                $0.identifier?.rawValue.hasPrefix("template-copy-") == true
            }
            XCTAssertEqual(copyButtons.count, 6)
            XCTAssertEqual(
                Set(copyButtons.compactMap { $0.accessibilityLabel() }),
                Set([
                    "Copy prompt for Inspect the CLI",
                    "Copy prompt for Check updates",
                    "Copy prompt for Add an item",
                    "Copy prompt for Review & approve",
                    "Copy prompt for Update approved items",
                    "Copy prompt for Diagnose issues",
                ])
            )
            XCTAssertTrue(copyButtons.allSatisfy { $0.toolTip == "Copy prompt" })

            let categories = descendants(of: NSView.self, in: controller.view).filter {
                $0.identifier?.rawValue.hasPrefix("template-category-") == true
            }
            XCTAssertEqual(categories.count, 3)
            XCTAssertTrue(categories.allSatisfy { !$0.isHidden })
        }

        func testFieldInputUpdatesPreviewAndCopyWritesExactVisiblePrompt() throws {
            var copied: String?
            let controller = TemplatesViewController(writeToPasteboard: {
                copied = $0
                return true
            })
            _ = controller.view
            let itemField = try textField(
                "template-field-addItem-itemName",
                in: controller.view
            )
            let sourceField = try textField(
                "template-field-addItem-source",
                in: controller.view
            )
            let preview = try textView("template-preview-addItem", in: controller.view)
            let copyButton = try button("template-copy-addItem", in: controller.view)

            itemField.stringValue = "ripgrep"
            sendAction(from: itemField)
            sourceField.stringValue = "BurntSushi/ripgrep"
            sendAction(from: sourceField)
            copyButton.performClick(nil)

            XCTAssertTrue(preview.string.contains("ripgrep"))
            XCTAssertTrue(preview.string.contains("BurntSushi/ripgrep"))
            XCTAssertFalse(preview.string.contains("[ITEM_NAME]"))
            XCTAssertEqual(copied, preview.string)
            XCTAssertEqual(copyButton.accessibilityLabel(), "Copied prompt for Add an item")
        }

        func testWhitespaceInputKeepsPromptPlaceholder() throws {
            let controller = TemplatesViewController(writeToPasteboard: { _ in true })
            _ = controller.view
            let field = try textField(
                "template-field-checkUpdates-itemName",
                in: controller.view
            )
            let preview = try textView("template-preview-checkUpdates", in: controller.view)

            field.stringValue = "   "
            sendAction(from: field)

            XCTAssertTrue(preview.string.contains("[ITEM_ID_OR_ALL]"))
        }

        func testCategoryFilteringPreservesEnteredValues() throws {
            let controller = TemplatesViewController(writeToPasteboard: { _ in true })
            _ = controller.view
            let field = try textField(
                "template-field-addItem-itemName",
                in: controller.view
            )
            let filter = try XCTUnwrap(
                descendants(of: NSSegmentedControl.self, in: controller.view).first {
                    $0.identifier?.rawValue == "template-filter"
                }
            )

            field.stringValue = "ripgrep"
            sendAction(from: field)
            filter.selectedSegment = 1
            sendAction(from: filter)

            XCTAssertFalse(try category("discover", in: controller.view).isHidden)
            XCTAssertTrue(try category("configure", in: controller.view).isHidden)
            XCTAssertTrue(try category("operate", in: controller.view).isHidden)

            filter.selectedSegment = 0
            sendAction(from: filter)

            XCTAssertEqual(field.stringValue, "ripgrep")
            XCTAssertTrue(
                try textView("template-preview-addItem", in: controller.view)
                    .string.contains("ripgrep")
            )
        }

        func testCopyFailureExposesAccessibleErrorState() throws {
            let controller = TemplatesViewController(writeToPasteboard: { _ in false })
            _ = controller.view
            let copyButton = try button("template-copy-diagnose", in: controller.view)

            copyButton.performClick(nil)

            XCTAssertEqual(
                copyButton.accessibilityLabel(),
                "Could not copy prompt for Diagnose issues"
            )
        }

        private func sendAction(from control: NSControl) {
            guard let action = control.action else {
                XCTFail("Control has no action")
                return
            }
            _ = NSApp.sendAction(action, to: control.target, from: control)
        }

        private func button(_ identifier: String, in root: NSView) throws -> NSButton {
            try XCTUnwrap(
                descendants(of: NSButton.self, in: root).first {
                    $0.identifier?.rawValue == identifier
                }
            )
        }

        private func textField(_ identifier: String, in root: NSView) throws -> NSTextField {
            try XCTUnwrap(
                descendants(of: NSTextField.self, in: root).first {
                    $0.identifier?.rawValue == identifier
                }
            )
        }

        private func textView(_ identifier: String, in root: NSView) throws -> NSTextView {
            try XCTUnwrap(
                descendants(of: NSTextView.self, in: root).first {
                    $0.identifier?.rawValue == identifier
                }
            )
        }

        private func category(_ name: String, in root: NSView) throws -> NSView {
            try XCTUnwrap(
                descendants(of: NSView.self, in: root).first {
                    $0.identifier?.rawValue == "template-category-\(name)"
                }
            )
        }

        private func descendants<View: NSView>(of type: View.Type, in root: NSView) -> [View] {
            var matches = root.subviews.compactMap { $0 as? View }
            for subview in root.subviews {
                matches.append(contentsOf: descendants(of: type, in: subview))
            }
            return matches
        }
    }
#endif
