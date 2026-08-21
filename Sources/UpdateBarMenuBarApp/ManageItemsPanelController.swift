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
        private var selectionModel = ManageItemsSelectionModel()
        private var rows: [ManageItemsRow] = []
        private var rowWarnings: [String: String] = [:]
        private var pendingEnabled: Bool?
        private var isLoading = false
        private var isActionBusy = false

        var onRefresh: () -> Void = {}
        var onUpdateItems: ([String]) -> Void = { _ in }
        var onError: (Error) -> Void = { _ in }

        private let tableView = NSTableView()
        private let refreshButton: NSButton = {
            let image =
                NSImage(
                    systemSymbolName: "arrow.clockwise",
                    accessibilityDescription: DashboardPresentationModel.itemsRefreshHelp
                ) ?? NSImage()
            return NSButton(image: image, target: nil, action: nil)
        }()
        private let loadingIndicator = NSProgressIndicator()
        private let updateSelectedButton = NSButton(
            title: "Update Selected (0)",
            target: nil,
            action: nil
        )

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
                if identifier == "select" {
                    return selectionCell(row: row, item: item)
                }
                if identifier == "enabled" {
                    return checkboxCell(row: row, item: item)
                }
                if identifier == "status" {
                    return statusCell(item)
                }
                if identifier == "action" {
                    return updateCell(row: row, item: item)
                }
                return textCell(text(identifier, item: item))
            }
        }

        @objc private func reloadFromButton() {
            onRefresh()
        }

        @objc private func toggleSelection(_ sender: NSButton) {
            guard rows.indices.contains(sender.tag),
                case .item(let item) = rows[sender.tag]
            else { return }
            selectionModel.toggle(id: item.id, isEligible: item.isUpdateEligible)
            updateControls()
        }

        @objc private func updateRow(_ sender: NSButton) {
            guard rows.indices.contains(sender.tag),
                case .item(let item) = rows[sender.tag], item.isUpdateEligible
            else { return }
            onUpdateItems([item.id])
        }

        @objc private func updateSelectedItems() {
            let ids = selectionModel.selectedIDs
            guard !ids.isEmpty else { return }
            onUpdateItems(ids)
        }

        @objc private func toggleItem(_ sender: NSButton) {
            guard rows.indices.contains(sender.tag),
                case .item(let item) = rows[sender.tag]
            else { return }
            let enabled = sender.state == .on
            mutationGate.begin(id: item.id, enabled: enabled)
            pendingEnabled = enabled
            rowWarnings[item.id] = nil
            updateControls()
            DispatchQueue.global(qos: .userInitiated).async { [service] in
                do {
                    try service.setEnabled(id: item.id, enabled: enabled)
                    DispatchQueue.main.async {
                        self.onChanged()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showMutationError(id: item.id, error: error)
                        self.onError(error)
                    }
                }
            }
        }

        func setLoading() {
            _ = view
            isLoading = true
            selectionModel.clear()
            updateControls()
        }

        func setActionBusy(_ isBusy: Bool) {
            _ = view
            isActionBusy = isBusy
            updateControls()
        }

        func apply(items: [StatusItem]) {
            _ = view
            guard mutationGate.accepts(items) else { return }
            pendingEnabled = nil
            selectionModel.clear()
            rows = model.rows(from: items)
            tableView.reloadData()
            isLoading = false
            updateControls()
        }

        private func buildInterface(in content: NSView) {
            refreshButton.target = self
            refreshButton.action = #selector(reloadFromButton)
            refreshButton.isBordered = false
            refreshButton.toolTip = DashboardPresentationModel.itemsRefreshHelp
            refreshButton.setAccessibilityLabel(DashboardPresentationModel.itemsRefreshHelp)

            loadingIndicator.style = .spinning
            loadingIndicator.controlSize = .small
            loadingIndicator.isDisplayedWhenStopped = false
            loadingIndicator.toolTip = "Refreshing items"
            loadingIndicator.setAccessibilityLabel("Refreshing items")

            updateSelectedButton.target = self
            updateSelectedButton.action = #selector(updateSelectedItems)
            updateSelectedButton.bezelStyle = .rounded
            updateSelectedButton.toolTip = "Select outdated items to update"
            updateSelectedButton.setAccessibilityLabel("Update Selected (0)")

            let sectionTitle = NSTextField(labelWithString: "Items")
            sectionTitle.font = .systemFont(ofSize: 20, weight: .semibold)
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let controls = NSStackView(views: [
                sectionTitle, spacer, updateSelectedButton, loadingIndicator, refreshButton,
            ])
            controls.orientation = .horizontal
            controls.alignment = .centerY
            controls.spacing = 8

            for (identifier, title, width) in [
                ("select", "Select", 52.0),
                ("enabled", "On", 34.0),
                ("name", "Name", 170.0),
                ("current", "Current", 85.0),
                ("latest", "Latest", 85.0),
                ("status", "Status", 150.0),
                ("action", "Action", 90.0),
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
            isLoading = false
            selectionModel.clear()
            updateControls()
        }

        private func showMutationError(id: String, error: Error) {
            mutationGate.cancel()
            pendingEnabled = nil
            rowWarnings[id] = SecretRedactor.redact(String(describing: error))
            isLoading = false
            updateControls()
        }

        private func updateControls() {
            let controlsEnabled = !isLoading && !isActionBusy && !mutationGate.isPending
            refreshButton.isEnabled = controlsEnabled
            let selectedCount = selectionModel.selectedIDs.count
            let updateSelectedTitle = "Update Selected (\(selectedCount))"
            updateSelectedButton.title = updateSelectedTitle
            updateSelectedButton.setAccessibilityLabel(updateSelectedTitle)
            updateSelectedButton.isEnabled = controlsEnabled && selectedCount > 0
            if isLoading {
                loadingIndicator.startAnimation(nil)
            } else {
                loadingIndicator.stopAnimation(nil)
            }
            tableView.reloadData()
        }

        private func checkboxCell(row: Int, item: ManageItemRow) -> NSTableCellView {
            let button = NSButton(
                checkboxWithTitle: "",
                target: self,
                action: #selector(toggleItem(_:))
            )
            button.tag = row
            let isPending = mutationGate.isPending(id: item.id)
            button.state = (isPending ? pendingEnabled : item.isEnabled) == true ? .on : .off
            button.isEnabled = !isLoading && !isActionBusy && !mutationGate.isPending
            let name = SecretRedactor.redact(item.name)
            let action = button.state == .on ? "Disable" : "Enable"
            button.toolTip = "\(action) \(name)"
            button.setAccessibilityLabel("\(action) \(name)")

            let views: [NSView]
            if isPending {
                let progress = NSProgressIndicator()
                progress.style = .spinning
                progress.controlSize = .small
                progress.startAnimation(nil)
                progress.toolTip = "Updating \(name)"
                progress.setAccessibilityLabel("Updating \(name)")
                views = [button, progress]
            } else {
                views = [button]
            }

            let stack = NSStackView(views: views)
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false
            let cell = NSTableCellView()
            cell.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private func selectionCell(row: Int, item: ManageItemRow) -> NSTableCellView {
            let name = SecretRedactor.redact(item.name)
            let isSelected = selectionModel.contains(item.id)
            let button = NSButton(
                checkboxWithTitle: "",
                target: self,
                action: #selector(toggleSelection(_:))
            )
            button.tag = row
            button.state = isSelected ? .on : .off
            button.isEnabled =
                item.isUpdateEligible && !isLoading && !isActionBusy
                && !mutationGate.isPending
            button.setAccessibilityLabel("\(isSelected ? "Deselect" : "Select") \(name)")
            if let reason = item.updateDisabledReason {
                button.toolTip = reason
                button.setAccessibilityHelp(reason)
            } else {
                button.toolTip = "Select \(name) for Update Selected"
            }
            return centeredCell(containing: button)
        }

        private func updateCell(row: Int, item: ManageItemRow) -> NSTableCellView {
            let name = SecretRedactor.redact(item.name)
            let button = NSButton(title: "Update", target: self, action: #selector(updateRow(_:)))
            button.tag = row
            button.controlSize = .small
            button.bezelStyle = .rounded
            button.isEnabled =
                item.isUpdateEligible && !isLoading && !isActionBusy
                && !mutationGate.isPending
            button.setAccessibilityLabel("Update \(name)")
            if let reason = item.updateDisabledReason {
                button.toolTip = reason
                button.setAccessibilityHelp(reason)
            } else {
                button.toolTip = "Update \(name)"
            }
            return centeredCell(containing: button)
        }

        private func centeredCell(containing view: NSView) -> NSTableCellView {
            view.translatesAutoresizingMaskIntoConstraints = false
            let cell = NSTableCellView()
            cell.addSubview(view)
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                view.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private func statusCell(_ item: ManageItemRow) -> NSTableCellView {
            let label = NSTextField(labelWithString: item.statusLabel)
            label.lineBreakMode = .byTruncatingTail
            var views: [NSView] = [label]
            if let warning = rowWarnings[item.id] {
                let icon = NSImageView()
                icon.image = NSImage(
                    systemSymbolName: "exclamationmark.triangle.fill",
                    accessibilityDescription: "Update failed"
                )
                icon.contentTintColor = .systemRed
                icon.toolTip = warning
                icon.setAccessibilityLabel(
                    "Update failed for \(SecretRedactor.redact(item.name)): \(warning)"
                )
                views.append(icon)
            }

            let stack = NSStackView(views: views)
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 5
            stack.translatesAutoresizingMaskIntoConstraints = false
            let cell = NSTableCellView()
            cell.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                stack.trailingAnchor.constraint(
                    lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
                stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
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
