#if os(macOS)
    import AppKit
    import Foundation
    import UpdateBarCore
    import UpdateBarMenuBar

    private final class ScanCandidateBox: @unchecked Sendable {
        let value: ScanCandidate

        init(_ value: ScanCandidate) {
            self.value = value
        }
    }

    private final class ScanResultBox: @unchecked Sendable {
        let report: ScanReport
        let registeredStatuses: [String: ItemStatus]

        init(report: ScanReport, registeredStatuses: [String: ItemStatus]) {
            self.report = report
            self.registeredStatuses = registeredStatuses
        }
    }

    private struct RedactedScanError: Error, CustomStringConvertible, LocalizedError, Sendable {
        let message: String

        var description: String { message }
        var errorDescription: String? { message }
    }

    final class ScanCountBadgeView: NSTextField {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

            stringValue = "0"
            isBezeled = false
            drawsBackground = false
            isEditable = false
            isSelectable = false
            font = .monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize,
                weight: .semibold
            )
            alignment = .center
            wantsLayer = true
            layer?.cornerRadius = 6
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            setAccessibilityElement(true)
            setAccessibilityRole(.staticText)
            heightAnchor.constraint(equalToConstant: 30).isActive = true
        }

        required init?(coder: NSCoder) {
            nil
        }

        func apply(_ count: DashboardScanCountPresentation) {
            stringValue = count.visibleValue
            toolTip = count.help
            setAccessibilityLabel(count.accessibilityLabel)
            setAccessibilityValue(count.visibleValue)
            setAccessibilityHelp(count.help)
        }
    }

    final class ScanViewController: NSViewController, NSTableViewDataSource,
        NSTableViewDelegate
    {
        private let service: any MenuBarServicing
        var onChanged: () -> Void
        private let listModel = ScanListModel()
        private let presentationModel = DashboardPresentationModel()
        private var mutationGate = ScanMutationGate()
        private var sessionGate = ScanSessionGenerationGate()
        private var rows: [ScanListRow] = []
        private var lastReport: ScanReport?
        private var rowWarnings: [String: String] = [:]
        private var scanControlState: DashboardScanControlState = .ready

        private var isScanning: Bool {
            scanControlState == .scanning
        }

        var onError: (Error) -> Void = { _ in }

        private let tableView = NSTableView()
        private let scanButton = NSButton(title: "Scan", target: nil, action: nil)
        private let scanProgressIndicator = NSProgressIndicator()
        private let discoveredCountBadge = ScanCountBadgeView(frame: .zero)
        private let enabledCountBadge = ScanCountBadgeView(frame: .zero)
        private let disabledCountBadge = ScanCountBadgeView(frame: .zero)

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
            updateControls()
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
            switch identifier {
            case "tracked":
                return checkboxCell(row: row, rowModel: rowModel)
            case "state":
                return stateCell(rowModel)
            default:
                return textCell(text(identifier, row: rowModel))
            }
        }

        func applyRegisteredItems(_ items: [StatusItem]) {
            _ = view
            guard let lastReport else { return }
            let statuses = Dictionary(
                items.map { ($0.id, $0.status) },
                uniquingKeysWith: { _, latest in latest }
            )
            let refreshedRows = listModel.rows(
                from: lastReport,
                registeredStatuses: statuses
            )
            let currentRows = Dictionary(
                rows.map { ($0.candidate.id, $0) },
                uniquingKeysWith: { current, _ in current }
            )
            rows = refreshedRows.map { row in
                if mutationGate.isPending(id: row.candidate.id) {
                    return currentRows[row.candidate.id] ?? row
                }
                return row
            }
            tableView.reloadData()
            updateControls()
        }

        func invalidateScanSession() {
            sessionGate.invalidateForWindowClose()
            scanControlState = .ready
            if isViewLoaded {
                updateControls()
            }
        }

        @objc private func runScan() {
            let token = sessionGate.beginManualScan()
            scanControlState = .scanning
            updateControls()
            tableView.reloadData()

            DispatchQueue.global(qos: .userInitiated).async { [service] in
                do {
                    let report = try service.scan(category: nil)
                    let snapshot = try service.status(refresh: false)
                    let statuses = Dictionary(
                        snapshot.items.map { ($0.id, $0.status) },
                        uniquingKeysWith: { _, latest in latest }
                    )
                    let result = ScanResultBox(
                        report: report,
                        registeredStatuses: statuses
                    )
                    DispatchQueue.main.async {
                        self.finishScan(result, token: token)
                    }
                } catch {
                    let message = SecretRedactor.redact(String(describing: error))
                    DispatchQueue.main.async {
                        self.finishScanFailure(message, token: token)
                    }
                }
            }
        }

        @objc private func toggleCandidate(_ sender: NSButton) {
            guard rows.indices.contains(sender.tag) else { return }
            let row = rows[sender.tag]
            guard row.canToggle else {
                reloadRow(id: row.candidate.id)
                return
            }

            let target: ScanTrackingState
            switch (row.trackingState, sender.state) {
            case (.untracked, .on), (.disabled, .on):
                target = .enabled
            case (.enabled, .off):
                target = .disabled
            default:
                reloadRow(id: row.candidate.id)
                return
            }

            guard
                let mutation = mutationGate.begin(
                    id: row.candidate.id,
                    previous: row.trackingState,
                    target: target
                )
            else {
                reloadRow(id: row.candidate.id)
                return
            }

            rows[sender.tag].trackingState = target
            rowWarnings[mutation.id] = nil
            reloadRow(id: mutation.id)
            updateControls()
            perform(mutation, candidate: ScanCandidateBox(row.candidate))
        }

        private func perform(_ mutation: ScanRowMutation, candidate: ScanCandidateBox) {
            DispatchQueue.global(qos: .userInitiated).async { [service] in
                do {
                    guard let intent = mutation.serviceIntent else { return }
                    switch intent {
                    case .register:
                        _ = try service.registerScannedCandidates(
                            [candidate.value],
                            selectedIDs: [mutation.id],
                            replace: false
                        )
                    case .setEnabled(let enabled):
                        try service.setEnabled(id: mutation.id, enabled: enabled)
                    }
                    DispatchQueue.main.async {
                        self.finishMutation(id: mutation.id)
                    }
                } catch {
                    let message = SecretRedactor.redact(String(describing: error))
                    DispatchQueue.main.async {
                        self.finishMutationFailure(id: mutation.id, message: message)
                    }
                }
            }
        }

        private func finishScan(_ result: ScanResultBox, token: Int) {
            guard sessionGate.acceptsCurrentScan(token) else { return }
            scanControlState = result.report.errors.isEmpty ? .ready : .failed
            lastReport = result.report
            rowWarnings.removeAll()
            rows = listModel.rows(
                from: result.report,
                registeredStatuses: result.registeredStatuses
            )
            tableView.reloadData()
            updateControls()
            if !result.report.errors.isEmpty {
                onError(
                    RedactedScanError(
                        message: partialScanFailureMessage(result.report)
                    )
                )
            }
        }

        private func finishScanFailure(_ message: String, token: Int) {
            guard sessionGate.acceptsCurrentScan(token) else { return }
            scanControlState = .failed
            updateControls()
            tableView.reloadData()
            onError(RedactedScanError(message: message))
        }

        private func partialScanFailureMessage(_ report: ScanReport) -> String {
            let candidateSummary: String
            switch report.candidates.count {
            case 0:
                candidateSummary = "no candidates"
            case 1:
                candidateSummary = "1 candidate"
            default:
                candidateSummary = "\(report.candidates.count) candidates"
            }
            let failureSummary =
                report.errors.count == 1
                ? "1 detector failed"
                : "\(report.errors.count) detectors failed"
            let details = report.errors.map {
                "\($0.detector.rawValue): \($0.message)"
            }.joined(separator: "; ")
            return SecretRedactor.redact(
                "Scan found \(candidateSummary), but \(failureSummary). \(details)"
            )
        }

        private func finishMutation(id: String) {
            guard mutationGate.finish(id: id) != nil else { return }
            rowWarnings[id] = nil
            reloadRow(id: id)
            updateControls()
            onChanged()
        }

        private func finishMutationFailure(id: String, message: String) {
            guard let mutation = mutationGate.finish(id: id) else { return }
            let candidateName =
                rows.first(where: { $0.candidate.id == id })?.candidate.name ?? id
            if let rowIndex = rows.firstIndex(where: { $0.candidate.id == id }) {
                rows[rowIndex].trackingState = mutation.previous
            }
            rowWarnings[id] = message
            reloadRow(id: id)
            updateControls()
            let announcement = presentationModel.scanMutationFailureAnnouncement(
                candidateName: candidateName,
                restoredState: mutation.previous,
                message: message
            )
            NSAccessibility.post(
                element: tableView,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: announcement,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ]
            )
            onError(RedactedScanError(message: message))
        }

        private func buildInterface(in content: NSView) {
            scanButton.target = self
            scanButton.action = #selector(runScan)

            scanProgressIndicator.style = .spinning
            scanProgressIndicator.controlSize = .small
            scanProgressIndicator.isDisplayedWhenStopped = false
            scanProgressIndicator.toolTip = "Scanning for installed tools"
            scanProgressIndicator.setAccessibilityLabel("Scanning for installed tools")

            let infoIcon = NSImageView()
            infoIcon.image = NSImage(
                systemSymbolName: "info.circle",
                accessibilityDescription: DashboardPresentationModel.scanTrackingHelp
            )
            infoIcon.toolTip = DashboardPresentationModel.scanTrackingHelp
            infoIcon.setAccessibilityLabel(DashboardPresentationModel.scanTrackingHelp)

            let sectionTitle = NSTextField(labelWithString: "Scan & Add")
            sectionTitle.font = .systemFont(ofSize: 20, weight: .semibold)
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let controls = NSStackView(views: [
                sectionTitle,
                spacer,
                scanProgressIndicator,
                scanButton,
                infoIcon,
            ])
            controls.orientation = .horizontal
            controls.alignment = .centerY
            controls.spacing = 8
            infoIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
            infoIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true

            let counts = NSStackView(views: [
                discoveredCountBadge,
                enabledCountBadge,
                disabledCountBadge,
            ])
            counts.orientation = .horizontal
            counts.alignment = .centerY
            counts.distribution = .fillEqually
            counts.spacing = 8

            for (identifier, title, width) in [
                ("tracked", "On", 42.0),
                ("name", "Name", 180.0),
                ("version", "Version", 90.0),
                ("category", "Category", 110.0),
                ("source", "Source", 90.0),
                ("state", "State", 180.0),
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

            let stack = NSStackView(views: [controls, counts, scrollView])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 10
            stack.translatesAutoresizingMaskIntoConstraints = false
            controls.translatesAutoresizingMaskIntoConstraints = false
            counts.translatesAutoresizingMaskIntoConstraints = false
            scrollView.translatesAutoresizingMaskIntoConstraints = false

            content.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
                controls.widthAnchor.constraint(equalTo: stack.widthAnchor),
                counts.widthAnchor.constraint(equalTo: stack.widthAnchor),
                scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
                scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            ])
        }

        private func updateControls() {
            let discovered = rows.count
            let enabled = rows.filter { $0.trackingState == .enabled }.count
            let disabled = rows.filter { $0.trackingState == .disabled }.count
            let counts = presentationModel.scanCounts(
                discovered: discovered,
                enabled: enabled,
                disabled: disabled
            )
            updateCountBadge(discoveredCountBadge, count: counts[0])
            updateCountBadge(enabledCountBadge, count: counts[1])
            updateCountBadge(disabledCountBadge, count: counts[2])
            let scanControl = presentationModel.scanControl(state: scanControlState)
            scanButton.toolTip = scanControl.toolTip
            scanButton.setAccessibilityLabel(scanControl.accessibilityLabel)
            scanButton.image = scanControl.iconName.flatMap {
                NSImage(
                    systemSymbolName: $0,
                    accessibilityDescription: scanControl.accessibilityLabel
                )
            }
            scanButton.imagePosition = scanControl.iconName == nil ? .noImage : .imageLeading
            scanButton.contentTintColor = scanControlState == .failed ? .systemRed : nil
            scanButton.isEnabled = !isScanning && !mutationGate.hasPendingMutations
            if isScanning {
                scanProgressIndicator.startAnimation(nil)
            } else {
                scanProgressIndicator.stopAnimation(nil)
            }
        }

        private func updateCountBadge(
            _ badge: ScanCountBadgeView,
            count: DashboardScanCountPresentation
        ) {
            badge.apply(count)
        }

        private func checkboxCell(row: Int, rowModel: ScanListRow) -> NSTableCellView {
            let button = NSButton(
                checkboxWithTitle: "",
                target: self,
                action: #selector(toggleCandidate(_:))
            )
            button.tag = row
            button.state = rowModel.isChecked ? .on : .off
            button.isEnabled =
                rowModel.canToggle
                && !mutationGate.isPending(id: rowModel.candidate.id)
                && !isScanning
            let name = SecretRedactor.redact(rowModel.candidate.name)
            button.toolTip =
                "Enable or disable \(name). \(DashboardPresentationModel.scanTrackingHelp)"
            button.setAccessibilityLabel(
                presentationModel.scanRowActionLabel(
                    candidateName: rowModel.candidate.name,
                    isChecked: rowModel.isChecked
                )
            )
            button.setAccessibilityHelp(DashboardPresentationModel.scanTrackingHelp)

            let cell = NSTableCellView()
            cell.addSubview(button)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private func stateCell(_ row: ScanListRow) -> NSTableCellView {
            let label = NSTextField(labelWithString: stateText(row))
            label.lineBreakMode = .byTruncatingTail
            let views: [NSView]
            if mutationGate.isPending(id: row.candidate.id) {
                let progress = NSProgressIndicator()
                progress.style = .spinning
                progress.controlSize = .small
                progress.startAnimation(nil)
                let name = SecretRedactor.redact(row.candidate.name)
                progress.toolTip = "Updating \(name)"
                progress.setAccessibilityLabel("Updating \(name)")
                views = [progress, label]
            } else {
                views = [label]
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

        private func stateText(_ row: ScanListRow) -> String {
            let state: String
            switch row.trackingState {
            case .untracked, .enabled, .disabled:
                state = row.stateLabel.capitalized
            case .unavailable(let capability):
                state = "Unavailable · \(SecretRedactor.redact(capability))"
            }
            if mutationGate.isPending(id: row.candidate.id) {
                return "\(state) · Updating..."
            }
            if let warning = rowWarnings[row.candidate.id] {
                return "\(state) · \(warning)"
            }
            return state
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

        private func reloadRow(id: String) {
            guard let row = rows.firstIndex(where: { $0.candidate.id == id }) else { return }
            tableView.reloadData(
                forRowIndexes: IndexSet(integer: row),
                columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
            )
        }
    }
#endif
