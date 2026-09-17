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
        private var cards: [PromptTemplateCardView] = []
        private let scrollView = NSScrollView()

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
                    "Choose a task, customize its prompt, then copy it to your coding agent."
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
            header.orientation = .vertical
            header.alignment = .leading
            header.distribution = .fill
            header.spacing = 12
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
            ])
            view = content
        }

        private func makeCategoryView(_ category: PromptTemplateCategory) -> NSView {
            let heading = NSTextField(labelWithString: category.title)
            heading.font = .systemFont(ofSize: 12, weight: .semibold)
            heading.textColor = .secondaryLabelColor

            let templates = PromptTemplateCatalog.templates.filter { $0.category == category }
            let categoryCards = templates.map { definition in
                let card = PromptTemplateCardView(
                    definition: definition,
                    onCopy: { [weak self] card in self?.copyPrompt(from: card) },
                    onToggle: { [weak self] card in self?.toggleEditor(card) }
                )
                cards.append(card)
                return card
            }
            let list = NSStackView(views: categoryCards)
            list.orientation = .vertical
            list.alignment = .leading
            list.spacing = 12
            for card in categoryCards {
                card.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            }

            let stack = NSStackView(views: [heading, list])
            stack.identifier = NSUserInterfaceItemIdentifier(
                "template-category-\(category.rawValue)"
            )
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            list.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return stack
        }

        private func toggleEditor(_ selected: PromptTemplateCardView) {
            let expanding = !selected.isExpanded
            for card in cards {
                card.setExpanded(card === selected && expanding)
            }
            view.layoutSubtreeIfNeeded()
            guard let document = scrollView.documentView else { return }
            let cardFrame = selected.convert(selected.bounds, to: document)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: cardFrame.minY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
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
            view.layoutSubtreeIfNeeded()
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
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
        private let onToggle: (PromptTemplateCardView) -> Void
        private let preview = NSTextView()
        private let copyButton = NSButton()
        private let customizeButton = NSButton()
        private let editor = NSStackView()
        private var fieldControls: [PromptTemplateFieldKey: NSTextField] = [:]
        private var copyResetGeneration = 0
        private(set) var isExpanded = false

        var prompt: String {
            preview.string
        }

        init(
            definition: PromptTemplateDefinition,
            onCopy: @escaping (PromptTemplateCardView) -> Void,
            onToggle: @escaping (PromptTemplateCardView) -> Void
        ) {
            self.definition = definition
            self.onCopy = onCopy
            self.onToggle = onToggle
            super.init(frame: .zero)
            buildView()
            refreshPrompt()
            setExpanded(false)
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
            copyButton.title = succeeded ? "Copied" : "Try again"
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

        func setExpanded(_ expanded: Bool) {
            isExpanded = expanded
            editor.isHidden = !expanded
            customizeButton.title = expanded ? "Hide preview" : "Customize & preview"
            customizeButton.image = NSImage(
                systemSymbolName: expanded ? "chevron.down" : "chevron.right",
                accessibilityDescription: nil
            )
            customizeButton.setAccessibilityLabel(
                "\(expanded ? "Hide" : "Customize") prompt for \(definition.title)"
            )
            customizeButton.setAccessibilityValue(expanded ? "Expanded" : "Collapsed")
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

            let title = NSTextField(wrappingLabelWithString: definition.title)
            title.font = .systemFont(ofSize: 14, weight: .semibold)

            let summary = NSTextField(wrappingLabelWithString: definition.summary)
            summary.font = .systemFont(ofSize: 12)
            summary.textColor = .secondaryLabelColor

            let textStack = NSStackView(views: [title, summary])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 2

            configureCopyButton()
            copyButton.target = self
            copyButton.action = #selector(copyClicked)

            let header = NSStackView(views: [icon, textStack, NSView(), copyButton])
            header.orientation = .horizontal
            header.alignment = .centerY
            header.spacing = 9

            let boundary = NSTextField(wrappingLabelWithString: definition.boundary)
            boundary.font = .systemFont(ofSize: 12)
            boundary.textColor = .secondaryLabelColor
            boundary.setAccessibilityLabel("Safety boundary: \(definition.boundary)")
            customizeButton.bezelStyle = .inline
            customizeButton.font = .systemFont(ofSize: 12)
            customizeButton.imagePosition = .imageLeading
            customizeButton.identifier = NSUserInterfaceItemIdentifier(
                "template-customize-\(definition.id.rawValue)"
            )
            customizeButton.target = self
            customizeButton.action = #selector(toggleClicked)
            customizeButton.setAccessibilityHelp("Shows input fields and the complete prompt")

            let controls = NSStackView(views: [customizeButton, NSView(), boundary])
            controls.orientation = .horizontal
            controls.alignment = .centerY
            controls.spacing = 12

            editor.orientation = .vertical
            editor.alignment = .leading
            editor.spacing = 12
            if !definition.fields.isEmpty {
                editor.addArrangedSubview(makeFieldsView())
            }
            editor.addArrangedSubview(makePreviewView())
            for editorView in editor.arrangedSubviews {
                editorView.widthAnchor.constraint(equalTo: editor.widthAnchor).isActive = true
            }
            let bodyViews: [NSView] = [header, controls, editor]

            let body = NSStackView(views: bodyViews)
            body.orientation = .vertical
            body.alignment = .leading
            body.spacing = 12
            body.translatesAutoresizingMaskIntoConstraints = false
            addSubview(body)

            for bodyView in bodyViews.dropFirst() {
                bodyView.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
            }

            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 24),
                icon.heightAnchor.constraint(equalToConstant: 24),
                copyButton.widthAnchor.constraint(equalToConstant: 116),
                copyButton.heightAnchor.constraint(equalToConstant: 30),
                header.widthAnchor.constraint(equalTo: body.widthAnchor),
                body.topAnchor.constraint(equalTo: topAnchor, constant: 16),
                body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                body.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            ])
        }

        private func makeFieldsView() -> NSView {
            let columns = definition.fields.map { field in
                let label = NSTextField(labelWithString: field.label)
                label.font = .systemFont(ofSize: 12, weight: .medium)
                label.textColor = .secondaryLabelColor

                let control = NSTextField()
                control.identifier = NSUserInterfaceItemIdentifier(
                    "template-field-\(definition.id.rawValue)-\(field.key.rawValue)"
                )
                control.placeholderString = field.placeholder
                control.font = .systemFont(ofSize: 13)
                control.maximumNumberOfLines = 1
                control.cell?.wraps = false
                control.cell?.isScrollable = true
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
            preview.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            preview.textColor = .labelColor
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakStrategy = .hangulWordPriority
            preview.defaultParagraphStyle = paragraphStyle
            preview.autoresizingMask = [.width]
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
            scrollView.heightAnchor.constraint(equalToConstant: 200).isActive = true
            return scrollView
        }

        private func configureCopyButton() {
            copyButton.title = "Copy prompt"
            copyButton.image = NSImage(
                systemSymbolName: "doc.on.doc",
                accessibilityDescription: nil
            )
            copyButton.imagePosition = .imageLeading
            copyButton.bezelStyle = .rounded
            copyButton.font = .systemFont(ofSize: 12)
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

        @objc private func toggleClicked() {
            onToggle(self)
        }
    }

    private final class FlippedStackView: NSStackView {
        override var isFlipped: Bool {
            true
        }
    }
#endif
