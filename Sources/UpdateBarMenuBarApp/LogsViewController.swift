#if os(macOS)
    import AppKit
    import UpdateBarCore
    import UpdateBarMenuBar

    final class LogsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
        private let tableView = NSTableView()
        private let emptyLabel = NSTextField(labelWithString: "No update history yet")
        private let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }()
        private var rows: [HistoryLogRow] = []

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
            scrollView.translatesAutoresizingMaskIntoConstraints = false

            emptyLabel.font = .systemFont(ofSize: 14)
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.alignment = .center
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false

            let content = NSView()
            content.addSubview(title)
            content.addSubview(scrollView)
            content.addSubview(emptyLabel)
            title.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                title.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
                title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                scrollView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
                scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                scrollView.trailingAnchor.constraint(
                    equalTo: content.trailingAnchor,
                    constant: -20
                ),
                scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
                emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
                emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            ])
            view = content
            refreshVisibleRows()
        }

        func apply(events: [HistoryEvent]) {
            rows = HistoryLogPresentation.rows(from: events)
            guard isViewLoaded else { return }
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
            label.toolTip = value
            return label
        }

        private func refreshVisibleRows() {
            tableView.reloadData()
            emptyLabel.isHidden = !rows.isEmpty
        }
    }
#endif
