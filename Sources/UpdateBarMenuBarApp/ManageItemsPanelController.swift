#if os(macOS)
    import AppKit
    import Foundation
    import UpdateBarCore
    import UpdateBarMenuBar

    final class ManageItemsViewController: NSViewController, NSTableViewDataSource,
        NSTableViewDelegate
    {
        private let service: any MenuBarServicing
        private let onChanged: () -> Void
        private let model = ManageItemsModel()
        private var mutationGate = ManageItemsMutationGate()
        private var rows: [ManageItemsRow] = []
        private var isRunning = false

        var onRefresh: () -> Void = {}
        var onError: (Error) -> Void = { _ in }

        private let tableView = NSTableView()
        private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
        private let statusLabel = NSTextField(labelWithString: "Ready")

        init(
            service: any MenuBarServicing,
            onChanged: @escaping () -> Void
        ) {
            self.service = service
            self.onChanged = onChanged
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func loadView() {
            let content = NSView()
            buildInterface(in: content)
            view = content
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            if case .category = rows[row] { return true }
            return false
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard rows.indices.contains(row) else { return nil }
            switch rows[row] {
            case .category(let name, let count):
                if tableColumn == nil || tableColumn?.identifier.rawValue == "name" {
                    return groupCell("\(name) (\(count))")
                }
                return nil
            case .item(let item):
                guard let identifier = tableColumn?.identifier.rawValue else { return nil }
                if identifier == "enabled" {
                    return checkboxCell(row: row, item: item)
                }
                return textCell(text(identifier, item: item))
            }
        }

        @objc private func reloadFromButton() {
            onRefresh()
        }

        @objc private func toggleItem(_ sender: NSButton) {
            guard rows.indices.contains(sender.tag),
                case .item(let item) = rows[sender.tag]
            else { return }
            let enabled = sender.state == .on
            mutationGate.begin(id: item.id, enabled: enabled)
            setRunning(true, message: "\(enabled ? "Enabling" : "Disabling") \(item.name)...")
            DispatchQueue.global(qos: .userInitiated).async { [service] in
                do {
                    try service.setEnabled(id: item.id, enabled: enabled)
                    DispatchQueue.main.async {
                        self.setRunning(
                            true,
                            message: "\(item.name) updated. Refreshing..."
                        )
                        self.onChanged()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showMutationError(error)
                        self.onError(error)
                    }
                }
            }
        }

        func setLoading() {
            _ = view
            setRunning(true, message: "Loading...")
        }

        func apply(items: [StatusItem], message: String? = nil) {
            _ = view
            guard mutationGate.accepts(items) else { return }
            rows = model.rows(from: items)
            tableView.reloadData()
            setRunning(false, message: message ?? "\(items.count) item(s).")
        }

        private func buildInterface(in content: NSView) {
            refreshButton.target = self
            refreshButton.action = #selector(reloadFromButton)
            statusLabel.lineBreakMode = .byTruncatingTail

            let controls = NSStackView(views: [refreshButton, statusLabel])
            controls.orientation = .horizontal
            controls.alignment = .centerY
            controls.spacing = 8
            statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

            for (identifier, title, width) in [
                ("enabled", "On", 34.0),
                ("name", "Name", 200.0),
                ("current", "Current", 100.0),
                ("latest", "Latest", 100.0),
                ("status", "Status", 220.0),
            ] {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
                column.title = title
                column.width = width
                tableView.addTableColumn(column)
            }
            tableView.delegate = self
            tableView.dataSource = self
            tableView.usesAlternatingRowBackgroundColors = true
            tableView.allowsColumnReordering = false
            tableView.floatsGroupRows = true

            let scrollView = NSScrollView()
            scrollView.documentView = tableView
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.borderType = .bezelBorder

            let stack = NSStackView(views: [controls, scrollView])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 10
            stack.translatesAutoresizingMaskIntoConstraints = false
            controls.translatesAutoresizingMaskIntoConstraints = false
            scrollView.translatesAutoresizingMaskIntoConstraints = false

            content.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
                controls.widthAnchor.constraint(equalTo: stack.widthAnchor),
                scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
                scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            ])
        }

        func showError(_ error: Error) {
            _ = view
            setRunning(
                mutationGate.isPending,
                message: SecretRedactor.redact(String(describing: error))
            )
        }

        private func showMutationError(_ error: Error) {
            mutationGate.cancel()
            showError(error)
        }

        private func setRunning(_ running: Bool, message: String) {
            isRunning = running
            statusLabel.stringValue = SecretRedactor.redact(message)
            refreshButton.isEnabled = !running
            tableView.reloadData()
        }

        private func checkboxCell(row: Int, item: ManageItemRow) -> NSTableCellView {
            let button = NSButton(
                checkboxWithTitle: "",
                target: self,
                action: #selector(toggleItem(_:))
            )
            button.tag = row
            button.state = item.isEnabled ? .on : .off
            button.isEnabled = !isRunning
            let cell = NSTableCellView()
            cell.addSubview(button)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private func text(_ identifier: String, item: ManageItemRow) -> String {
            switch identifier {
            case "name":
                return item.name
            case "current":
                return item.currentVersion
            case "latest":
                return item.latestVersion
            case "status":
                return item.statusLabel
            default:
                return ""
            }
        }

        private func groupCell(_ text: String) -> NSTableCellView {
            let label = NSTextField(labelWithString: text)
            label.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
            label.translatesAutoresizingMaskIntoConstraints = false
            let cell = NSTableCellView()
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private func textCell(_ text: String) -> NSTableCellView {
            let label = NSTextField(labelWithString: text)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            let cell = NSTableCellView()
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

    }
#endif
