#if os(macOS)
    import AppKit
    import Foundation
    import UpdateBarCore
    import UpdateBarMenuBar

    private final class ScanCandidateList: @unchecked Sendable {
        let values: [ScanCandidate]

        init(_ values: [ScanCandidate]) {
            self.values = values
        }
    }

    final class ScanPanelController: NSWindowController, NSTableViewDataSource,
        NSTableViewDelegate
    {
        private let service: any MenuBarServicing
        private let onRegistered: () -> Void
        private var rows: [ScanListRow] = []
        private let listModel = ScanListModel()
        private var hasScanned = false
        private var isRunning = false

        private let tableView = NSTableView()
        private let scanButton = NSButton(title: "Scan", target: nil, action: nil)
        private let addButton = NSButton(title: "Add Selected", target: nil, action: nil)
        private let statusLabel = NSTextField(labelWithString: "Ready")

        init(
            service: any MenuBarServicing,
            onRegistered: @escaping () -> Void
        ) {
            self.service = service
            self.onRegistered = onRegistered
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "Scan & Add"
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 640, height: 320)
            super.init(window: panel)
            buildInterface()
        }

        required init?(coder: NSCoder) {
            nil
        }

        func showScanWindow() {
            showWindow(nil)
            window?.center()
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if !hasScanned {
                statusLabel.stringValue = "Press Scan to discover installed tools."
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard rows.indices.contains(row), let identifier = tableColumn?.identifier.rawValue
            else {
                return nil
            }
            let rowModel = rows[row]
            if identifier == "selected" {
                return checkboxCell(row: row, rowModel: rowModel)
            }
            return textCell(text(identifier, row: rowModel))
        }

        @objc private func runScan() {
            setRunning(true, message: "Scanning...")
            DispatchQueue.global(qos: .userInitiated).async { [service] in
                do {
                    let report = try service.scan(category: nil)
                    let registeredIDs = Set(try service.status(refresh: false).items.map(\.id))
                    DispatchQueue.main.async {
                        self.apply(report, registeredIDs: registeredIDs)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.finishWithError(error)
                    }
                }
            }
        }

        @objc private func addSelected() {
            let selectedIDs = rows.compactMap { row in
                row.isSelected && row.isImportable ? row.candidate.id : nil
            }
            guard !selectedIDs.isEmpty else { return }
            let candidates = ScanCandidateList(rows.map(\.candidate))
            setRunning(true, message: "Adding selected...")
            DispatchQueue.global(qos: .userInitiated).async { [service] in
                do {
                    let summary = try service.registerScannedCandidates(
                        candidates.values,
                        selectedIDs: selectedIDs,
                        replace: false
                    )
                    DispatchQueue.main.async {
                        self.finishAdding(summary)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.finishWithError(error)
                    }
                }
            }
        }

        @objc private func toggleCandidate(_ sender: NSButton) {
            guard rows.indices.contains(sender.tag), rows[sender.tag].isImportable else {
                return
            }
            rows[sender.tag].isSelected = sender.state == .on
            updateAddButton()
        }

        private func buildInterface() {
            scanButton.target = self
            scanButton.action = #selector(runScan)
            addButton.target = self
            addButton.action = #selector(addSelected)
            addButton.isEnabled = false
            statusLabel.lineBreakMode = .byTruncatingTail

            let controls = NSStackView(views: [scanButton, addButton, statusLabel])
            controls.orientation = .horizontal
            controls.alignment = .centerY
            controls.spacing = 8
            statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

            for (identifier, title, width) in [
                ("selected", "", 34.0),
                ("name", "Name", 180.0),
                ("version", "Version", 90.0),
                ("category", "Category", 120.0),
                ("source", "Source", 90.0),
                ("state", "State", 110.0),
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

            let content = NSView()
            content.addSubview(stack)
            window?.contentView = content
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
                controls.widthAnchor.constraint(equalTo: stack.widthAnchor),
                scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
                scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            ])
        }

        private func apply(_ report: ScanReport, registeredIDs: Set<String>) {
            hasScanned = true
            rows = listModel.rows(from: report, registeredIDs: registeredIDs)
            tableView.reloadData()
            let importableCount = rows.filter(\.isImportable).count
            if report.errors.isEmpty {
                setRunning(
                    false,
                    message: "Found \(rows.count) candidate(s), \(importableCount) importable."
                )
            } else {
                setRunning(
                    false,
                    message:
                        "Found \(rows.count) candidate(s), \(report.errors.count) scan error(s)."
                )
            }
        }

        private func finishAdding(_ summary: InitSummary) {
            rows = rows.map { row in
                var row = row
                row.isSelected = false
                return row
            }
            tableView.reloadData()
            setRunning(
                false,
                message:
                    "Added \(summary.added.count), replaced \(summary.replaced.count), skipped \(summary.skipped.count)."
            )
            onRegistered()
        }

        private func finishWithError(_ error: Error) {
            setRunning(false, message: SecretRedactor.redact(String(describing: error)))
            present(error)
        }

        private func setRunning(_ running: Bool, message: String) {
            isRunning = running
            statusLabel.stringValue = SecretRedactor.redact(message)
            scanButton.isEnabled = !running
            updateAddButton()
            tableView.reloadData()
        }

        private func updateAddButton() {
            addButton.isEnabled = !isRunning && rows.contains {
                $0.isSelected && $0.isImportable
            }
        }

        private func checkboxCell(row: Int, rowModel: ScanListRow) -> NSTableCellView {
            let button = NSButton(
                checkboxWithTitle: "",
                target: self,
                action: #selector(toggleCandidate(_:))
            )
            button.tag = row
            button.state = rowModel.isSelected ? .on : .off
            button.isEnabled = rowModel.isImportable && !isRunning
            let cell = NSTableCellView()
            cell.addSubview(button)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private func text(_ identifier: String, row: ScanListRow) -> String {
            let candidate = row.candidate
            switch identifier {
            case "name":
                return SecretRedactor.redact(candidate.name)
            case "version":
                return candidate.installedVersion.map(SecretRedactor.redact) ?? ""
            case "category":
                return SecretRedactor.redact(candidate.category)
            case "source":
                return candidate.detector.rawValue
            case "state":
                return row.stateLabel
            default:
                return ""
            }
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

        private func present(_ error: Error) {
            guard let window else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "UpdateBar"
            alert.informativeText = SecretRedactor.redact(String(describing: error))
            alert.beginSheetModal(for: window)
        }
    }
#endif
