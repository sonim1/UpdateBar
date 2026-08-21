#if os(macOS)
    import AppKit
    import UpdateBarMenuBar

    private final class SidebarSummaryButton: NSButton {
        override func hitTest(_ point: NSPoint) -> NSView? {
            let localPoint = convert(point, from: superview)
            return bounds.contains(localPoint) ? self : nil
        }
    }

    final class DashboardSidebarViewController: NSViewController, NSTableViewDataSource,
        NSTableViewDelegate
    {
        private let sections = DashboardSection.allCases
        private let tableView = NSTableView()
        private let queueContainer = NSStackView()
        private var selectedSection: DashboardSection
        private var updateQueue = SidebarUpdateQueue(count: 0, items: [], overflowCount: 0)
        private var isApplyingSelection = false

        var onSelectionChanged: (DashboardSection) -> Void = { _ in }
        var onOpenItems: () -> Void = {}

        init(selectedSection: DashboardSection = .overview) {
            self.selectedSection = selectedSection
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func loadView() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
            column.resizingMask = .autoresizingMask
            tableView.addTableColumn(column)
            tableView.headerView = nil
            tableView.delegate = self
            tableView.dataSource = self
            tableView.rowHeight = 32
            tableView.allowsEmptySelection = false
            tableView.allowsMultipleSelection = false
            tableView.style = .sourceList
            tableView.setAccessibilityLabel("Dashboard sections")

            let scrollView = NSScrollView()
            scrollView.documentView = tableView
            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.translatesAutoresizingMaskIntoConstraints = false

            queueContainer.orientation = .vertical
            queueContainer.alignment = .leading
            queueContainer.spacing = 6
            queueContainer.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            queueContainer.translatesAutoresizingMaskIntoConstraints = false

            let content = NSView()
            content.addSubview(scrollView)
            content.addSubview(queueContainer)
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: content.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: queueContainer.topAnchor),
                scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
                scrollView.widthAnchor.constraint(lessThanOrEqualToConstant: 190),
                queueContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                queueContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                queueContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
            view = content
            renderUpdateQueue()
            select(selectedSection)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            sections.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard sections.indices.contains(row) else { return nil }
            let section = sections[row]
            let imageView = NSImageView()
            imageView.image = NSImage(
                systemSymbolName: section.systemImageName,
                accessibilityDescription: nil
            )
            imageView.contentTintColor = .labelColor
            imageView.setAccessibilityElement(false)

            let label = NSTextField(labelWithString: section.title)
            label.lineBreakMode = .byTruncatingTail
            let stack = NSStackView(views: [imageView, label])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false

            let cell = NSTableCellView()
            cell.addSubview(stack)
            cell.setAccessibilityLabel(section.title)
            cell.setAccessibilitySelected(section == selectedSection)
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                stack.trailingAnchor.constraint(
                    lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
                stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard tableView.selectedRow >= 0, sections.indices.contains(tableView.selectedRow)
            else { return }
            selectedSection = sections[tableView.selectedRow]
            guard !isApplyingSelection else { return }
            onSelectionChanged(selectedSection)
        }

        func select(_ section: DashboardSection) {
            selectedSection = section
            _ = view
            isApplyingSelection = true
            tableView.selectRowIndexes(
                IndexSet(integer: section.rawValue),
                byExtendingSelection: false
            )
            isApplyingSelection = false
        }

        func apply(updateQueue: SidebarUpdateQueue) {
            self.updateQueue = updateQueue
            guard isViewLoaded else { return }
            renderUpdateQueue()
        }

        private func renderUpdateQueue() {
            for subview in queueContainer.arrangedSubviews {
                queueContainer.removeArrangedSubview(subview)
                subview.removeFromSuperview()
            }
            guard updateQueue.isVisible else {
                queueContainer.isHidden = true
                return
            }
            queueContainer.isHidden = false

            let button = SidebarSummaryButton(
                title: "",
                target: self,
                action: #selector(openItems)
            )
            button.identifier = NSUserInterfaceItemIdentifier("sidebar-updates-summary")
            button.bezelStyle = .rounded
            let imageView = NSImageView(image: NSImage(
                systemSymbolName: "arrow.down.circle.fill",
                accessibilityDescription: nil
            ) ?? NSImage())
            imageView.contentTintColor = .controlAccentColor
            imageView.setAccessibilityElement(false)

            let title = NSTextField(labelWithString: "Updates available")
            title.identifier = NSUserInterfaceItemIdentifier("sidebar-updates-title")
            title.font = .systemFont(ofSize: 11, weight: .semibold)
            title.textColor = .labelColor
            title.lineBreakMode = .byTruncatingTail
            title.setAccessibilityElement(false)

            let detail = NSTextField(labelWithString: "\(updateQueue.count) items · Open Items")
            detail.identifier = NSUserInterfaceItemIdentifier("sidebar-updates-detail")
            detail.font = .systemFont(ofSize: 10)
            detail.textColor = .secondaryLabelColor
            detail.lineBreakMode = .byTruncatingTail
            detail.setAccessibilityElement(false)

            let textStack = NSStackView(views: [title, detail])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 1
            let content = NSStackView(views: [imageView, textStack])
            content.orientation = .horizontal
            content.alignment = .centerY
            content.spacing = 8
            content.translatesAutoresizingMaskIntoConstraints = false
            content.setAccessibilityElement(false)
            button.addSubview(content)
            button.setAccessibilityLabel("Open Items, \(updateQueue.count) updates available")
            button.setAccessibilityHelp("Shows the Items section without starting an update")
            button.translatesAutoresizingMaskIntoConstraints = false
            queueContainer.addArrangedSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalTo: queueContainer.widthAnchor, constant: -20),
                button.heightAnchor.constraint(equalToConstant: 48),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                content.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
                content.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -10),
                content.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
        }

        @objc private func openItems() {
            onOpenItems()
        }
    }
#endif
