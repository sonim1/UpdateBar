#if os(macOS)
    import AppKit
    import UpdateBarMenuBar

    final class DashboardSidebarViewController: NSViewController, NSTableViewDataSource,
        NSTableViewDelegate
    {
        private let sections = DashboardSection.allCases
        private let tableView = NSTableView()
        private var selectedSection: DashboardSection
        private var isApplyingSelection = false

        var onSelectionChanged: (DashboardSection) -> Void = { _ in }

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

            let content = NSView()
            content.addSubview(scrollView)
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: content.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
                scrollView.widthAnchor.constraint(lessThanOrEqualToConstant: 190),
            ])
            view = content
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
    }
#endif
