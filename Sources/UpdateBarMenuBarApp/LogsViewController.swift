#if os(macOS)
    import AppKit
    import UpdateBarCore
    import UpdateBarMenuBar

    final class LogsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
        NSTextFieldDelegate, NSSearchFieldDelegate
    {
        private let tableView = NSTableView()
        private let emptyLabel = NSTextField(labelWithString: "No update history yet")
        private let searchField = NSSearchField()
        private let toolFilter = NSPopUpButton()
        private let outcomeFilter = NSPopUpButton()
        private let timeFilter = NSPopUpButton()
        private let failureDetailStack = NSStackView()
        private let failureDetailScrollView = NSScrollView()
        private let failureDetailTextView = NSTextView(frame: .zero)
        private let copyFailureButton = NSButton(
            title: "Copy failure detail", target: nil, action: nil)
        private let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }()
        private var events: [HistoryEvent] = []
        private var rows: [HistoryLogRow] = []
        private var filters = HistoryLogFilters()

        override func loadView() {
            let title = NSTextField(labelWithString: "Logs")
            title.font = .systemFont(ofSize: 22, weight: .semibold)

            for (identifier, title, width) in [
                ("date", "Date", 150.0),
                ("event", "Event", 180.0),
                ("detail", "Details", 240.0),
            ] {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
                column.title = title
                column.width = width
                column.resizingMask = .autoresizingMask
                tableView.addTableColumn(column)
            }
            tableView.delegate = self
            tableView.dataSource = self
            tableView.usesAlternatingRowBackgroundColors = true
            tableView.allowsEmptySelection = true
            tableView.setAccessibilityLabel("Update history")

            let scrollView = NSScrollView()
            scrollView.documentView = tableView
            scrollView.hasVerticalScroller = true
            scrollView.setAccessibilityIdentifier("logs-table")
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

            emptyLabel.font = .systemFont(ofSize: 14)
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.alignment = .center
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false

            searchField.placeholderString = "Search logs"
            searchField.delegate = self
            searchField.setAccessibilityLabel("Search logs")
            searchField.setAccessibilityIdentifier("logs-search")

            for filter in [toolFilter, outcomeFilter, timeFilter] {
                filter.target = self
            }
            toolFilter.action = #selector(changeToolFilter(_:))
            outcomeFilter.action = #selector(changeOutcomeFilter(_:))
            timeFilter.action = #selector(changeTimeFilter(_:))
            toolFilter.setAccessibilityLabel("Filter logs by tool")
            outcomeFilter.setAccessibilityLabel("Filter logs by outcome")
            timeFilter.setAccessibilityLabel("Filter logs by time")

            let filterControls = NSStackView(views: [
                searchField,
                toolFilter,
                outcomeFilter,
                timeFilter,
            ])
            filterControls.orientation = .horizontal
            filterControls.alignment = .centerY
            filterControls.spacing = 8
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

            failureDetailTextView.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            failureDetailTextView.textColor = .secondaryLabelColor
            failureDetailTextView.drawsBackground = false
            failureDetailTextView.isEditable = false
            failureDetailTextView.isSelectable = true
            failureDetailTextView.isHorizontallyResizable = false
            failureDetailTextView.isVerticallyResizable = true
            failureDetailTextView.autoresizingMask = [.width]
            failureDetailTextView.textContainer?.containerSize = NSSize(
                width: 0,
                height: CGFloat.greatestFiniteMagnitude
            )
            failureDetailTextView.textContainer?.widthTracksTextView = true
            failureDetailTextView.setAccessibilityLabel("Selected failure detail")
            failureDetailScrollView.documentView = failureDetailTextView
            failureDetailScrollView.hasVerticalScroller = true
            failureDetailScrollView.autohidesScrollers = true
            failureDetailScrollView.borderType = .bezelBorder
            failureDetailScrollView.setAccessibilityIdentifier("logs-failure-detail")
            failureDetailScrollView.heightAnchor.constraint(equalToConstant: 120).isActive = true
            copyFailureButton.target = self
            copyFailureButton.action = #selector(copyFailureDetail)
            failureDetailStack.addArrangedSubview(failureDetailScrollView)
            failureDetailStack.addArrangedSubview(copyFailureButton)
            failureDetailStack.orientation = .vertical
            failureDetailStack.alignment = .leading
            failureDetailStack.spacing = 6
            failureDetailStack.isHidden = true

            let content = NSView()
            content.addSubview(title)
            content.addSubview(filterControls)
            content.addSubview(scrollView)
            content.addSubview(emptyLabel)
            content.addSubview(failureDetailStack)
            title.translatesAutoresizingMaskIntoConstraints = false
            filterControls.translatesAutoresizingMaskIntoConstraints = false
            failureDetailStack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                title.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
                title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                filterControls.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
                filterControls.leadingAnchor.constraint(
                    equalTo: content.leadingAnchor, constant: 20),
                filterControls.trailingAnchor.constraint(
                    equalTo: content.trailingAnchor,
                    constant: -20
                ),
                scrollView.topAnchor.constraint(equalTo: filterControls.bottomAnchor, constant: 12),
                scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                scrollView.trailingAnchor.constraint(
                    equalTo: content.trailingAnchor,
                    constant: -20
                ),
                failureDetailStack.topAnchor.constraint(
                    equalTo: scrollView.bottomAnchor, constant: 10),
                failureDetailStack.leadingAnchor.constraint(
                    equalTo: content.leadingAnchor, constant: 20),
                failureDetailStack.trailingAnchor.constraint(
                    equalTo: content.trailingAnchor,
                    constant: -20
                ),
                failureDetailStack.bottomAnchor.constraint(
                    equalTo: content.bottomAnchor,
                    constant: -20
                ),
                emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
                emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            ])
            view = content
            refreshFilterMenus()
            refreshVisibleRows()
        }

        func apply(events: [HistoryEvent]) {
            self.events = events
            guard isViewLoaded else { return }
            refreshFilterMenus()
            refreshVisibleRows()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard rows.indices.contains(row),
                let identifier = tableColumn?.identifier.rawValue
            else {
                return nil
            }
            let value: String
            switch identifier {
            case "date":
                value = dateFormatter.string(from: rows[row].date)
            case "event":
                value = rows[row].title
            default:
                value = rows[row].detail
            }
            let label = NSTextField(labelWithString: value)
            label.lineBreakMode = .byTruncatingTail
            label.toolTip = identifier == "detail" ? rows[row].failureDetail ?? value : value
            if identifier == "detail", rows[row].failureDetail != nil {
                label.isSelectable = true
            }
            return label
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            updateFailureDetail()
        }

        func controlTextDidChange(_ object: Notification) {
            guard (object.object as? NSSearchField) === searchField else { return }
            filters.query = searchField.stringValue
            refreshVisibleRows()
        }

        @objc private func changeToolFilter(_ sender: NSPopUpButton) {
            filters.tool =
                sender.titleOfSelectedItem == "All tools"
                ? nil : sender.titleOfSelectedItem
            refreshVisibleRows()
        }

        @objc private func changeOutcomeFilter(_ sender: NSPopUpButton) {
            filters.outcome =
                sender.titleOfSelectedItem == "All outcomes"
                ? nil : sender.titleOfSelectedItem
            refreshVisibleRows()
        }

        @objc private func changeTimeFilter(_ sender: NSPopUpButton) {
            filters.timeRange =
                HistoryLogTimeRange.allCases.first {
                    $0.title == sender.titleOfSelectedItem
                } ?? .all
            refreshVisibleRows()
        }

        @objc private func copyFailureDetail() {
            guard let failureDetail = selectedFailureDetail else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(failureDetail, forType: .string)
        }

        private func refreshVisibleRows() {
            tableView.deselectAll(nil)
            rows = HistoryLogPresentation.rows(
                from: events,
                filters: filters,
                now: Date()
            )
            tableView.reloadData()
            emptyLabel.stringValue =
                events.isEmpty
                ? "No update history yet" : "No log entries match these filters"
            emptyLabel.isHidden = !rows.isEmpty
            updateFailureDetail()
        }

        private func refreshFilterMenus() {
            let availableTools = Array(
                Set(HistoryLogPresentation.rows(from: events).compactMap(\.tool))
            ).sorted()
            let availableOutcomes = Array(
                Set(HistoryLogPresentation.rows(from: events).compactMap(\.outcome))
            ).sorted()
            refreshMenu(
                toolFilter,
                allTitle: "All tools",
                values: availableTools,
                selection: &filters.tool
            )
            refreshMenu(
                outcomeFilter,
                allTitle: "All outcomes",
                values: availableOutcomes,
                selection: &filters.outcome
            )
            timeFilter.removeAllItems()
            timeFilter.addItems(withTitles: HistoryLogTimeRange.allCases.map(\.title))
            timeFilter.selectItem(withTitle: filters.timeRange.title)
        }

        private func refreshMenu(
            _ menu: NSPopUpButton,
            allTitle: String,
            values: [String],
            selection: inout String?
        ) {
            if let currentSelection = selection, !values.contains(currentSelection) {
                selection = nil
            }
            menu.removeAllItems()
            menu.addItem(withTitle: allTitle)
            menu.addItems(withTitles: values)
            menu.selectItem(withTitle: selection ?? allTitle)
        }

        private var selectedFailureDetail: String? {
            guard rows.indices.contains(tableView.selectedRow) else { return nil }
            return rows[tableView.selectedRow].failureDetail
        }

        private func updateFailureDetail() {
            guard let failureDetail = selectedFailureDetail else {
                failureDetailStack.isHidden = true
                failureDetailScrollView.isHidden = true
                copyFailureButton.isHidden = true
                return
            }
            failureDetailTextView.string = failureDetail
            failureDetailStack.isHidden = false
            failureDetailScrollView.isHidden = false
            copyFailureButton.isHidden = false
        }
    }
#endif
