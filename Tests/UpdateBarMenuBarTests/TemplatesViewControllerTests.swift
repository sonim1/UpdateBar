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
            notifyTextChanged(itemField)
            sourceField.stringValue = "BurntSushi/ripgrep"
            notifyTextChanged(sourceField)
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
            XCTAssertEqual(copyButton.title, "Try again")
        }

        func testOnlySelectedEditorExpandsAndInputsSurviveSwitching() throws {
            let controller = TemplatesViewController(writeToPasteboard: { _ in true })
            _ = controller.view
            let inspect = try button("template-customize-inspectCLI", in: controller.view)
            let add = try button("template-customize-addItem", in: controller.view)
            let inspectPreview = try textView("template-preview-inspectCLI", in: controller.view)
            let addPreview = try textView("template-preview-addItem", in: controller.view)
            XCTAssertTrue(inspectPreview.isHiddenOrHasHiddenAncestor)
            XCTAssertTrue(addPreview.isHiddenOrHasHiddenAncestor)

            add.performClick(nil)
            XCTAssertFalse(addPreview.isHiddenOrHasHiddenAncestor)
            let field = try textField("template-field-addItem-itemName", in: controller.view)
            field.stringValue = "ripgrep"
            notifyTextChanged(field)

            inspect.performClick(nil)
            XCTAssertFalse(inspectPreview.isHiddenOrHasHiddenAncestor)
            XCTAssertTrue(addPreview.isHiddenOrHasHiddenAncestor)
            add.performClick(nil)
            XCTAssertEqual(field.stringValue, "ripgrep")
            XCTAssertTrue(addPreview.string.contains("ripgrep"))
            add.performClick(nil)
            XCTAssertTrue(addPreview.isHiddenOrHasHiddenAncestor)
        }

        func testCopyActionsHaveVisibleLabelsAndFeedback() throws {
            let controller = TemplatesViewController(writeToPasteboard: { _ in true })
            _ = controller.view
            let copyButtons = descendants(of: NSButton.self, in: controller.view).filter {
                $0.identifier?.rawValue.hasPrefix("template-copy-") == true
            }
            XCTAssertTrue(copyButtons.allSatisfy { $0.title == "Copy prompt" })
            let copy = try button("template-copy-inspectCLI", in: controller.view)
            copy.performClick(nil)
            XCTAssertEqual(copy.title, "Copied")
        }

        func testTemplateScrollDocumentUsesTopOrigin() throws {
            let controller = TemplatesViewController(writeToPasteboard: { _ in true })
            _ = controller.view
            let scrollView = try XCTUnwrap(
                descendants(of: NSScrollView.self, in: controller.view).first {
                    $0.identifier?.rawValue == "template-scroll"
                }
            )

            XCTAssertEqual(scrollView.documentView?.isFlipped, true)
        }

        func testPreviewFollowsViewportWidthWithoutAWindowLayoutPass() throws {
            let controller = TemplatesViewController(writeToPasteboard: { _ in true })
            _ = controller.view
            let preview = try textView("template-preview-inspectCLI", in: controller.view)
            try button("template-customize-inspectCLI", in: controller.view).performClick(nil)
            let scroll = try XCTUnwrap(preview.enclosingScrollView)
            XCTAssertTrue(preview.autoresizingMask.contains(.width))

            for width in [CGFloat(360), 520, 280] {
                scroll.setFrameSize(NSSize(width: width, height: 180))
                scroll.tile()
                XCTAssertGreaterThan(scroll.contentView.bounds.width, 0)
                XCTAssertEqual(preview.frame.width, scroll.contentView.bounds.width, accuracy: 1)
            }
        }

        func testSelectingCategoryReturnsListToTop() throws {
            let controller = TemplatesViewController(writeToPasteboard: { _ in true })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.contentViewController = controller
            window.layoutIfNeeded()
            let scroll = try XCTUnwrap(
                descendants(of: NSScrollView.self, in: controller.view).first {
                    $0.identifier?.rawValue == "template-scroll"
                }
            )
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
            XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
            let filter = try XCTUnwrap(
                descendants(of: NSSegmentedControl.self, in: controller.view).first
            )
            filter.selectedSegment = 0
            sendAction(from: filter)
            XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
        }

        func testExpandedFieldsParticipateInKeyboardNavigation() throws {
            let controller = TemplatesViewController(writeToPasteboard: { _ in true })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.contentViewController = controller
            window.layoutIfNeeded()
            window.recalculateKeyViewLoop()
            try button("template-customize-diagnose", in: controller.view).performClick(nil)
            let symptom = try textField("template-field-diagnose-symptom", in: controller.view)
            let item = try textField("template-field-diagnose-itemName", in: controller.view)

            XCTAssertTrue(symptom.nextValidKeyView === item)
            XCTAssertTrue(window.makeFirstResponder(symptom))
            let tab = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil,
                characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48
            ))
            window.sendEvent(tab)
            XCTAssertTrue(window.firstResponder === item.currentEditor())
            XCTAssertNotNil(item.currentEditor())
        }

        func testLongInputsStayInASingleScrollableLine() throws {
            let controller = TemplatesViewController(writeToPasteboard: { _ in true })
            _ = controller.view
            let field = try textField("template-field-diagnose-symptom", in: controller.view)
            field.stringValue = String(repeating: "긴 오류 메시지 https://example.invalid/", count: 10)
            notifyTextChanged(field)

            XCTAssertEqual(field.maximumNumberOfLines, 1)
            XCTAssertEqual(field.cell?.wraps, false)
            XCTAssertEqual(field.cell?.isScrollable, true)
            XCTAssertTrue(
                try textView("template-preview-diagnose", in: controller.view)
                    .string.contains(field.stringValue)
            )
        }

        func testTemplateFieldsFillCardWidthAtDashboardSize() throws {
            let controller = TemplatesViewController(writeToPasteboard: { _ in true })
            controller.view.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
            try button("template-customize-reviewApprove", in: controller.view).performClick(nil)
            controller.view.layoutSubtreeIfNeeded()
            let itemField = try textField(
                "template-field-reviewApprove-itemName",
                in: controller.view
            )
            let commandField = try textField(
                "template-field-reviewApprove-commandField",
                in: controller.view
            )

            XCTAssertGreaterThanOrEqual(itemField.frame.width, 140)
            XCTAssertGreaterThanOrEqual(commandField.frame.width, 140)
        }

        func testTemplatesStayWithinDashboardHeightAndScrollOverflow() throws {
            let controller = TemplatesViewController(writeToPasteboard: { _ in true })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 760, height: 420))
            let initialFrame = window.frame
            window.layoutIfNeeded()

            let scrollView = try XCTUnwrap(
                descendants(of: NSScrollView.self, in: controller.view).first {
                    $0.identifier?.rawValue == "template-scroll"
                }
            )
            let documentView = try XCTUnwrap(scrollView.documentView)
            let overflow = documentView.frame.height - scrollView.contentView.bounds.height

            scrollView.contentView.scroll(
                to: NSPoint(x: 0, y: max(0, overflow))
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)

            XCTAssertEqual(window.frame, initialFrame)
            XCTAssertGreaterThan(overflow, 0)
            XCTAssertGreaterThan(scrollView.contentView.bounds.origin.y, 0)
        }

        private func sendAction(from control: NSControl) {
            guard let action = control.action else {
                XCTFail("Control has no action")
                return
            }
            _ = NSApp.sendAction(action, to: control.target, from: control)
        }

        private func notifyTextChanged(_ field: NSTextField) {
            field.delegate?.controlTextDidChange?(
                Notification(name: NSControl.textDidChangeNotification, object: field)
            )
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
