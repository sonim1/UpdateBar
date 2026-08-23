#if os(macOS)
    import AppKit
    import UpdateBarMenuBar

    final class TemplatesViewController: NSViewController {
        typealias PasteboardWriter = @MainActor (String) -> Bool

        private let writeToPasteboard: PasteboardWriter
        private let filterControl = NSSegmentedControl(
            labels: ["All"] + PromptTemplateCategory.allCases.map(\.title),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        private var categoryViews: [PromptTemplateCategory: NSView] = [:]

        init(writeToPasteboard: @escaping PasteboardWriter = TemplatesViewController.copy) {
            self.writeToPasteboard = writeToPasteboard
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func loadView() {
            let title = NSTextField(labelWithString: "Templates")
            title.font = .systemFont(ofSize: 22, weight: .semibold)

            let subtitle = NSTextField(
                wrappingLabelWithString:
                    "Ready-to-use prompts for working with UpdateBar through an LLM."
            )
            subtitle.font = .systemFont(ofSize: 13)
            subtitle.textColor = .secondaryLabelColor

            let titleStack = NSStackView(views: [title, subtitle])
            titleStack.orientation = .vertical
            titleStack.alignment = .leading
            titleStack.spacing = 4

            filterControl.identifier = NSUserInterfaceItemIdentifier("template-filter")
            filterControl.selectedSegment = 0
            filterControl.segmentStyle = .rounded
            filterControl.target = self
            filterControl.action = #selector(filterChanged)
            filterControl.setAccessibilityLabel("Template category")

            let header = NSStackView(views: [titleStack, filterControl])
            header.orientation = .horizontal
            header.alignment = .bottom
            header.distribution = .fill
            header.spacing = 20
            header.translatesAutoresizingMaskIntoConstraints = false

            let categories = FlippedStackView()
            categories.orientation = .vertical
            categories.alignment = .leading
            categories.spacing = 20
            categories.translatesAutoresizingMaskIntoConstraints = false

            for category in PromptTemplateCategory.allCases {
                let categoryView = makeCategoryView(category)
                categoryViews[category] = categoryView
                categories.addArrangedSubview(categoryView)
                categoryView.widthAnchor.constraint(equalTo: categories.widthAnchor).isActive = true
            }

            let scrollView = NSScrollView()
            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.identifier = NSUserInterfaceItemIdentifier("template-scroll")
            scrollView.documentView = categories
            scrollView.translatesAutoresizingMaskIntoConstraints = false

            let content = NSView()
            content.addSubview(header)
            content.addSubview(scrollView)
            NSLayoutConstraint.activate([
                header.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
                header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
                scrollView.leadingAnchor.constraint(
                    equalTo: content.leadingAnchor,
                    constant: 20
                ),
                scrollView.trailingAnchor.constraint(
                    equalTo: content.trailingAnchor,
                    constant: -20
                ),
                scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
                categories.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
                categories.trailingAnchor.constraint(
                    equalTo: scrollView.contentView.trailingAnchor
                ),
                categories.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
                categories.bottomAnchor.constraint(
                    lessThanOrEqualTo: scrollView.contentView.bottomAnchor
                ),
            ])
            view = content
        }

        private func makeCategoryView(_ category: PromptTemplateCategory) -> NSView {
            let heading = NSTextField(labelWithString: category.title)
            heading.font = .systemFont(ofSize: 12, weight: .semibold)
            heading.textColor = .secondaryLabelColor

            let templates = PromptTemplateCatalog.templates.filter { $0.category == category }
            let cards = templates.map { definition in
                PromptTemplateCardView(definition: definition) { [weak self] card in
                    self?.copyPrompt(from: card)
                }
            }
            let grid = NSGridView(views: [cards])
            grid.columnSpacing = 12
            grid.rowSpacing = 12
            for index in cards.indices {
                grid.column(at: index).xPlacement = .fill
            }
            if cards.count == 2 {
                cards[0].widthAnchor.constraint(equalTo: cards[1].widthAnchor).isActive = true
            }

            let stack = NSStackView(views: [heading, grid])
            stack.identifier = NSUserInterfaceItemIdentifier(
                "template-category-\(category.rawValue)"
            )
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return stack
        }

        private func copyPrompt(from card: PromptTemplateCardView) {
            let succeeded = writeToPasteboard(card.prompt)
            card.showCopyResult(succeeded: succeeded)
        }

        @objc private func filterChanged() {
            let selectedCategory: PromptTemplateCategory? = {
                guard filterControl.selectedSegment > 0 else { return nil }
                return PromptTemplateCategory.allCases[filterControl.selectedSegment - 1]
            }()
            for (category, categoryView) in categoryViews {
                categoryView.isHidden = selectedCategory.map { $0 != category } ?? false
            }
        }

        private static func copy(_ value: String) -> Bool {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(value, forType: .string)
        }
    }

    private final class PromptTemplateCardView: NSView, NSTextFieldDelegate {
        private let definition: PromptTemplateDefinition
        private let onCopy: (PromptTemplateCardView) -> Void
        private let preview = NSTextView()
        private let copyButton = NSButton()
        private var fieldControls: [PromptTemplateFieldKey: NSTextField] = [:]
        private var copyResetGeneration = 0

        var prompt: String {
            preview.string
        }

        init(
            definition: PromptTemplateDefinition,
            onCopy: @escaping (PromptTemplateCardView) -> Void
        ) {
            self.definition = definition
            self.onCopy = onCopy
            super.init(frame: .zero)
            buildView()
            refreshPrompt()
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateLayerColors()
        }

        func showCopyResult(succeeded: Bool) {
            copyResetGeneration &+= 1
            let generation = copyResetGeneration
            let symbol = succeeded ? "checkmark" : "exclamationmark.triangle"
            copyButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            copyButton.contentTintColor = succeeded ? .systemGreen : .systemRed
            copyButton.setAccessibilityLabel(
                succeeded
                    ? "Copied prompt for \(definition.title)"
                    : "Could not copy prompt for \(definition.title)"
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, generation == self.copyResetGeneration else { return }
                self.configureCopyButton()
            }
        }

        private func buildView() {
            wantsLayer = true
            layer?.cornerRadius = 9
            layer?.borderWidth = 1
            updateLayerColors()

            let icon = NSImageView()
            icon.image = NSImage(
                systemSymbolName: definition.systemImageName,
                accessibilityDescription: nil
            )
            icon.contentTintColor = .controlAccentColor
            icon.symbolConfiguration = NSImage.SymbolConfiguration(
                pointSize: 14,
                weight: .medium
            )
            icon.setAccessibilityElement(false)

            let title = NSTextField(labelWithString: definition.title)
            title.font = .systemFont(ofSize: 14, weight: .semibold)

            let summary = NSTextField(wrappingLabelWithString: definition.summary)
            summary.font = .systemFont(ofSize: 11)
            summary.textColor = .secondaryLabelColor

            let textStack = NSStackView(views: [title, summary])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 2

            configureCopyButton()
            copyButton.target = self
            copyButton.action = #selector(copyClicked)

            let header = NSStackView(views: [icon, textStack, copyButton])
            header.orientation = .horizontal
            header.alignment = .centerY
            header.spacing = 9

            var bodyViews: [NSView] = [header]
            if !definition.fields.isEmpty {
                bodyViews.append(makeFieldsView())
            }
            bodyViews.append(makePreviewView())

            let boundary = NSTextField(labelWithString: definition.boundary)
            boundary.font = .systemFont(ofSize: 10)
            boundary.textColor = .tertiaryLabelColor
            boundary.setAccessibilityLabel("Safety boundary: \(definition.boundary)")
            bodyViews.append(boundary)

            let body = NSStackView(views: bodyViews)
            body.orientation = .vertical
            body.alignment = .leading
            body.spacing = 10
            body.translatesAutoresizingMaskIntoConstraints = false
            addSubview(body)

            for bodyView in bodyViews.dropFirst() {
                bodyView.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
            }

            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 24),
                icon.heightAnchor.constraint(equalToConstant: 24),
                copyButton.widthAnchor.constraint(equalToConstant: 28),
                copyButton.heightAnchor.constraint(equalToConstant: 28),
                header.widthAnchor.constraint(equalTo: body.widthAnchor),
                body.topAnchor.constraint(equalTo: topAnchor, constant: 14),
                body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                body.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
                widthAnchor.constraint(greaterThanOrEqualToConstant: 250),
            ])
        }

        private func makeFieldsView() -> NSView {
            let columns = definition.fields.map { field in
                let label = NSTextField(labelWithString: field.label)
                label.font = .systemFont(ofSize: 10, weight: .medium)
                label.textColor = .secondaryLabelColor

                let control = NSTextField()
                control.identifier = NSUserInterfaceItemIdentifier(
                    "template-field-\(definition.id.rawValue)-\(field.key.rawValue)"
                )
                control.placeholderString = field.placeholder
                control.font = .systemFont(ofSize: 11)
                control.delegate = self
                control.target = self
                control.action = #selector(fieldChanged)
                control.setAccessibilityLabel("\(definition.title), \(field.label)")
                fieldControls[field.key] = control

                let stack = NSStackView(views: [label, control])
                stack.orientation = .vertical
                stack.alignment = .leading
                stack.spacing = 4
                control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                return stack
            }

            let row = NSStackView(views: columns)
            row.orientation = .horizontal
            row.alignment = .top
            row.distribution = .fillEqually
            row.spacing = 8
            return row
        }

        private func makePreviewView() -> NSView {
            preview.identifier = NSUserInterfaceItemIdentifier(
                "template-preview-\(definition.id.rawValue)"
            )
            preview.isEditable = false
            preview.isSelectable = true
            preview.drawsBackground = false
            preview.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            preview.textColor = .secondaryLabelColor
            preview.textContainerInset = NSSize(width: 8, height: 7)
            preview.setAccessibilityLabel("Prompt preview for \(definition.title)")

            let scrollView = NSScrollView()
            scrollView.documentView = preview
            scrollView.drawsBackground = true
            scrollView.backgroundColor = .textBackgroundColor.withAlphaComponent(0.45)
            scrollView.borderType = .lineBorder
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.wantsLayer = true
            scrollView.layer?.cornerRadius = 6
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
            scrollView.heightAnchor.constraint(equalToConstant: 104).isActive = true
            return scrollView
        }

        private func configureCopyButton() {
            copyButton.title = ""
            copyButton.image = NSImage(
                systemSymbolName: "doc.on.doc",
                accessibilityDescription: nil
            )
            copyButton.imagePosition = .imageOnly
            copyButton.bezelStyle = .texturedRounded
            copyButton.contentTintColor = nil
            copyButton.toolTip = "Copy prompt"
            copyButton.identifier = NSUserInterfaceItemIdentifier(
                "template-copy-\(definition.id.rawValue)"
            )
            copyButton.setAccessibilityLabel("Copy prompt for \(definition.title)")
            copyButton.setAccessibilityHelp("Copies the visible prompt to the clipboard")
        }

        private func refreshPrompt() {
            let values = fieldControls.mapValues(\.stringValue)
            preview.string = definition.prompt(values: values)
        }

        private func updateLayerColors() {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }

        @objc private func fieldChanged() {
            refreshPrompt()
        }

        func controlTextDidChange(_ notification: Notification) {
            refreshPrompt()
        }

        @objc private func copyClicked() {
            onCopy(self)
        }
    }

    private final class FlippedStackView: NSStackView {
        override var isFlipped: Bool {
            true
        }
    }
#endif
