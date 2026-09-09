#if os(macOS)
    import AppKit
    import SwiftUI
    import UpdateBarCore
    import UpdateBarMenuBar

    private enum PopoverLayout {
        static let compact: CGFloat = 8
        static let regular: CGFloat = 12
        static let inset: CGFloat = 16
        static let rowHeight: CGFloat = 64
        static let cornerRadius: CGFloat = 8
    }

    struct MenuBarPopoverView: View {
        @ObservedObject var store: MenuBarPopoverStore
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var model: MenuBarPopoverModel { store.model }

        var body: some View {
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: PopoverLayout.inset) {
                        notices
                        if let item = model.detailItem {
                            details(for: item)
                        } else {
                            overview
                        }
                    }
                    .padding(PopoverLayout.inset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(model.detailItemID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                footer
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onExitCommand(perform: store.escape)
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: PopoverLayout.regular) {
                HStack(spacing: PopoverLayout.regular) {
                    VStack(alignment: .leading, spacing: PopoverLayout.compact) {
                        Text("UpdateBar")
                            .font(.headline)
                        Text(lastCheckedTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(lastCheckedHelp)
                            .accessibilityIdentifier("popover-last-checked")
                    }
                    Spacer(minLength: PopoverLayout.compact)
                    Button(action: store.check) {
                        Label("Check", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Check approved items for updates")
                    .accessibilityIdentifier("popover-check")
                }
                if model.isBusy {
                    HStack(spacing: PopoverLayout.compact) {
                        activityIndicator
                        Text(model.activeActionTitle ?? "Refreshing status…")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if model.isUpdating && model.progress.totalCount > 0 {
                            Text(
                                "\(model.progress.completedCount) of \(model.progress.totalCount) completed"
                            )
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                        }
                    }
                    .font(.caption)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("popover-activity")
                }
            }
            .padding(PopoverLayout.inset)
        }

        @ViewBuilder
        private var notices: some View {
            if let error = model.errorMessage {
                statusNote(
                    title: "Couldn’t complete the action", message: error,
                    symbol: "exclamationmark.triangle", color: .red
                )
                Button("View logs") { store.dashboard(.logs) }
                    .buttonStyle(.borderless)
            }
            if model.activeActionTitle == nil, !model.isRefreshing, let notice = model.notice {
                statusNote(title: notice, symbol: "info.circle", color: .secondary)
            }
        }

        @ViewBuilder
        private var overview: some View {
            if !model.progress.isEmpty {
                results
            }

            if model.isFirstRun {
                if !model.isBusy && model.errorMessage == nil {
                    emptyState(
                        title: "Your tools, kept current",
                        message:
                            "Find installed tools, then review the commands you want to allow.",
                        symbol: "shippingbox"
                    )
                    Button("Scan & Add") { store.dashboard(.scan) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("popover-scan-add")
                }
            } else {
                updateItems
                attentionItems
                readyItems
                if model.eligibleItems.isEmpty && model.approvalItems.isEmpty
                    && model.readyToCheckItems.isEmpty && model.errorItems.isEmpty
                    && !model.isUpdating && model.errorMessage == nil
                {
                    emptyState(
                        title: model.isAllCurrent ? "You’re up to date" : "No updates available",
                        message: emptyStateMessage,
                        symbol: model.isAllCurrent ? "checkmark.circle" : "tray"
                    )
                }
            }
        }

        @ViewBuilder
        private var activityIndicator: some View {
            if reduceMotion {
                Image(systemName: "hourglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
        }

        @ViewBuilder
        private var updateItems: some View {
            let items = model.eligibleItems.filter {
                !model.isUpdating || !model.progress.plannedIDs.contains($0.id)
            }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: PopoverLayout.compact) {
                    sectionTitle("Updates", count: items.count)
                    ForEach(items, id: \.id) { item in
                        HStack(spacing: PopoverLayout.regular) {
                            Toggle(
                                "Select \(item.name)",
                                isOn: Binding(
                                    get: { store.model.selectedIDs.contains(item.id) },
                                    set: { store.model.setSelected($0, id: item.id) }
                                )
                            )
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .disabled(model.isBusy)
                            .accessibilityLabel("Select \(item.name) for update")
                            .accessibilityIdentifier("popover-select-\(item.id)")
                            itemDetailsButton(item)
                        }
                        .frame(minHeight: PopoverLayout.rowHeight)
                    }
                }
            }
        }

        private func itemDetailsButton(_ item: StatusItem) -> some View {
            Button {
                store.model.showDetails(id: item.id)
            } label: {
                HStack(spacing: PopoverLayout.compact) {
                    VStack(alignment: .leading, spacing: PopoverLayout.compact) {
                        Text(item.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.primary)
                        Text("\(item.current ?? "Unknown") → \(item.latest ?? "Unknown")")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                .frame(
                    maxWidth: .infinity, minHeight: PopoverLayout.rowHeight, alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details for \(item.name)")
            .accessibilityValue("\(item.current ?? "Unknown") to \(item.latest ?? "Unknown")")
            .accessibilityIdentifier("popover-details-\(item.id)")
        }

        @ViewBuilder
        private var attentionItems: some View {
            let approvalIDs = Set(model.approvalItems.map(\.id))
            let errorIDs = Set(model.errorItems.map(\.id))
            let items = model.state.allItems.filter {
                approvalIDs.contains($0.id) || errorIDs.contains($0.id)
            }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: PopoverLayout.regular) {
                    sectionTitle("Needs attention", count: items.count)
                    Text(attentionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(items, id: \.id) { item in
                        VStack(alignment: .leading, spacing: PopoverLayout.compact) {
                            itemDetailsButton(item)
                            Label(
                                approvalIDs.contains(item.id)
                                    ? "Approval required" : "Action failed",
                                systemImage: approvalIDs.contains(item.id)
                                    ? "lock" : "exclamationmark.triangle"
                            )
                            .font(.caption)
                            .foregroundStyle(approvalIDs.contains(item.id) ? Color.orange : .red)
                        }
                    }
                }
                .padding(PopoverLayout.regular)
                .background(
                    .quaternary,
                    in: RoundedRectangle(cornerRadius: PopoverLayout.cornerRadius)
                )
            }
        }

        @ViewBuilder
        private var readyItems: some View {
            if !model.readyToCheckItems.isEmpty {
                VStack(alignment: .leading, spacing: PopoverLayout.regular) {
                    sectionTitle("Ready to check", count: model.readyToCheckItems.count)
                    ForEach(model.readyToCheckItems, id: \.id) { item in
                        itemDetailsButton(item)
                    }
                    checkApprovedCommands
                }
            }
        }

        private var checkApprovedCommands: some View {
            VStack(alignment: .leading, spacing: PopoverLayout.compact) {
                Text("Commands are approved. Check to find available updates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Check for Updates", action: store.check)
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("popover-ready-check")
            }
        }

        private var results: some View {
            VStack(alignment: .leading, spacing: PopoverLayout.regular) {
                Text(model.isUpdating ? "Update progress" : "Last update")
                    .font(.headline)
                ForEach(model.progress.plannedIDs, id: \.self) { id in
                    resultRow(id: id)
                }
                if !model.progress.failedIDs.isEmpty && !model.isUpdating {
                    Text(
                        "Status is rechecked first. Only failed items still eligible will be retried."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Button("Recheck & retry", action: store.retryFailed)
                        .buttonStyle(.bordered)
                        .disabled(model.isBusy || model.retryIDs.isEmpty)
                        .accessibilityIdentifier("popover-retry")
                }
            }
        }

        private func resultRow(id: String) -> some View {
            let phase = model.phase(for: id)
            let result = model.progress.resultsByID[id]
            let name = model.item(for: id)?.name ?? result?.name ?? id
            return VStack(alignment: .leading, spacing: PopoverLayout.compact) {
                HStack(spacing: PopoverLayout.compact) {
                    Image(systemName: symbol(for: phase))
                        .foregroundStyle(color(for: phase))
                        .accessibilityHidden(true)
                    if model.item(for: id) != nil {
                        Button(name) { store.model.showDetails(id: id) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.primary)
                            .accessibilityLabel("Details for \(name)")
                    } else {
                        Text(name)
                    }
                    Spacer(minLength: PopoverLayout.compact)
                    Text(phase.title)
                        .font(.caption)
                        .foregroundStyle(color(for: phase))
                }
                if let error = result?.error {
                    Text(SecretRedactor.redact(error))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .contain)
        }

        private func details(for item: StatusItem) -> some View {
            VStack(alignment: .leading, spacing: PopoverLayout.inset) {
                Button {
                    store.model.showList()
                } label: {
                    Label("Back to updates", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("popover-back")
                Text(item.name)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: PopoverLayout.inset) {
                    version("Installed", value: item.current)
                    version("Available", value: item.latest)
                }
                if let error = item.error {
                    statusNote(
                        title: "Action failed", message: error,
                        symbol: "exclamationmark.triangle", color: .red
                    )
                }
                if let result = model.progress.resultsByID[item.id] {
                    statusNote(
                        title: "Last update: \(model.phase(for: item.id).title.lowercased())",
                        message: result.error,
                        symbol: symbol(for: model.phase(for: item.id)),
                        color: color(for: model.phase(for: item.id))
                    )
                }
                if model.readyToCheckItems.contains(where: { $0.id == item.id }) {
                    VStack(alignment: .leading, spacing: PopoverLayout.compact) {
                        Text("Ready to check")
                            .font(.headline)
                        checkApprovedCommands
                    }
                }
                Text("Commands")
                    .font(.headline)
                Text("Approving a command doesn’t start an update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let commands = model.approvals[item.id] ?? []
                if commands.isEmpty {
                    Text("No command details are available.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(commands, id: \.field) { command in
                    commandReview(command, item: item)
                }
                Button("Review in Dashboard") { store.dashboard(.items) }
                    .buttonStyle(.borderless)
            }
        }

        private func commandReview(_ command: CommandApprovalStatus, item: StatusItem) -> some View
        {
            let commandText = SecretRedactor.redact(command.command)
            let cwdText = command.cwd.map(SecretRedactor.redact)
            let hasHiddenValues = commandText != command.command || cwdText != command.cwd
            let fieldTitle = title(for: command.field)
            return VStack(alignment: .leading, spacing: PopoverLayout.regular) {
                HStack(alignment: .firstTextBaseline, spacing: PopoverLayout.compact) {
                    Text("\(fieldTitle) command")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Label(
                        command.approved ? "Approved" : "Not approved",
                        systemImage: command.approved ? "checkmark.circle" : "lock"
                    )
                    .font(.caption)
                    .foregroundStyle(command.approved ? Color.secondary : .orange)
                }
                commandTextView(commandText)
                    .accessibilityLabel("\(fieldTitle) command: \(commandText)")
                VStack(alignment: .leading, spacing: PopoverLayout.compact) {
                    Text("Working directory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    commandTextView(cwdText ?? "Default (not specified)")
                }
                if hasHiddenValues {
                    Text("Sensitive values are hidden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !command.approved {
                    Toggle(
                        "I reviewed this command and working directory.",
                        isOn: Binding(
                            get: { store.model.isAcknowledged(id: item.id, field: command.field) },
                            set: {
                                store.model.setAcknowledged($0, id: item.id, field: command.field)
                            }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .disabled(model.isBusy)
                    .accessibilityLabel(
                        "I reviewed the \(fieldTitle.lowercased()) command and working directory for \(item.name)"
                    )
                    .accessibilityIdentifier("popover-ack-\(item.id)-\(command.field)")
                }
                Button(command.approved ? "Revoke \(fieldTitle) Approval" : "Approve \(fieldTitle)")
                {
                    store.setApproval(id: item.id, field: command.field)
                }
                .buttonStyle(.bordered)
                .disabled(model.reviewedApproval(id: item.id, field: command.field) == nil)
                .accessibilityLabel(
                    "\(command.approved ? "Revoke approval for" : "Approve") the \(fieldTitle.lowercased()) command for \(item.name)"
                )
                .accessibilityIdentifier("popover-approval-\(item.id)-\(command.field)")
            }
            .padding(PopoverLayout.regular)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: PopoverLayout.cornerRadius))
        }

        private func commandTextView(_ value: String) -> some View {
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PopoverLayout.compact)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: PopoverLayout.cornerRadius)
                )
        }

        private func version(_ title: String, value: String?) -> some View {
            VStack(alignment: .leading, spacing: PopoverLayout.compact) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value ?? "Unknown")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var footer: some View {
            VStack(spacing: PopoverLayout.regular) {
                HStack(spacing: PopoverLayout.regular) {
                    Text("\(model.selectedIDs.count) selected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if model.isUpdating && store.supportsStopping {
                        Button(model.stopRequested ? "Stopping…" : "Stop After Active Commands") {
                            store.stop()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.stopRequested)
                        .help("Lets every active command finish and starts no new updates.")
                        .accessibilityIdentifier("popover-stop")
                    } else {
                        Button("Update Selected", action: store.updateSelected)
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy || model.selectedIDs.isEmpty)
                            .help("Update only the selected approved items")
                            .accessibilityLabel("Update \(model.selectedIDs.count) selected items")
                            .accessibilityIdentifier("popover-update-selected")
                    }
                }
                if model.activeActionTitle != nil {
                    Text(
                        store.supportsStopping && model.stopRequested
                            ? model.stopMessage : "You can close this popover. Work will continue."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button {
                        store.dashboard(.overview)
                    } label: {
                        Label("Dashboard", systemImage: "rectangle.grid.2x2")
                    }
                    .accessibilityIdentifier("popover-dashboard")
                    Spacer()
                    Button(action: store.more) {
                        Label("More", systemImage: "ellipsis")
                    }
                    .accessibilityIdentifier("popover-more")
                }
                .buttonStyle(.borderless)
                .font(.callout)
            }
            .padding(PopoverLayout.inset)
        }

        private func sectionTitle(_ title: String, count: Int) -> some View {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }

        private func statusNote(
            title: String, message: String? = nil, symbol: String, color: Color
        ) -> some View {
            HStack(alignment: .top, spacing: PopoverLayout.compact) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PopoverLayout.compact) {
                    Text(SecretRedactor.redact(title))
                        .font(.callout.weight(.medium))
                    if let message {
                        Text(SecretRedactor.redact(message))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func emptyState(title: String, message: String, symbol: String) -> some View {
            VStack(alignment: .leading, spacing: PopoverLayout.regular) {
                Image(systemName: symbol)
                    .font(.title)
                    .foregroundStyle(model.isAllCurrent ? Color.green : .secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, PopoverLayout.inset)
        }

        private var lastCheckedTitle: String {
            guard let date = model.lastChecked else { return "Not checked yet" }
            let now = Date()
            if now.timeIntervalSince(date) < 1 { return "Just checked" }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Checked \(formatter.localizedString(for: date, relativeTo: now))"
        }

        private var lastCheckedHelp: String {
            model.lastChecked?.formatted(date: .complete, time: .shortened)
                ?? "No completed check has been recorded."
        }

        private var emptyStateMessage: String {
            if model.isAllCurrent {
                return model.state.allItems.count == 1
                    ? "Your tracked item is current."
                    : "All \(model.state.allItems.count) items are current."
            }
            if model.state.allItems.contains(where: { $0.status == .checking }) {
                return "Some items haven’t been checked yet. Check to find available updates."
            }
            if model.state.allItems.contains(where: { $0.status == .differs }) {
                return "Some versions differ. Review them in Dashboard."
            }
            return "Pinned and disabled items are excluded. You can review them in Dashboard."
        }

        private var attentionSummary: String {
            var parts: [String] = []
            if !model.approvalItems.isEmpty {
                let verb = model.approvalItems.count == 1 ? "needs" : "need"
                parts.append("\(model.approvalItems.count) \(verb) command approval")
            }
            if !model.errorItems.isEmpty {
                parts.append(
                    "\(model.errorItems.count) \(model.errorItems.count == 1 ? "error" : "errors")"
                )
            }
            return parts.joined(separator: " · ")
        }

        private func title(for field: String) -> String {
            switch field {
            case "check.cmd": "Check"
            case "latest.cmd": "Latest"
            case "update.cmd": "Update"
            default: SecretRedactor.redact(field)
            }
        }

        private func symbol(for phase: MenuBarPopoverItemPhase) -> String {
            switch phase {
            case .idle, .queued: "clock"
            case .running: "arrow.triangle.2.circlepath"
            case .succeeded: "checkmark.circle.fill"
            case .failed: "exclamationmark.circle.fill"
            case .skipped: "arrow.right.circle"
            case .cancelled, .notStarted: "minus.circle"
            }
        }

        private func color(for phase: MenuBarPopoverItemPhase) -> Color {
            switch phase {
            case .succeeded: .green
            case .failed: .red
            case .running: .accentColor
            case .idle, .queued, .skipped, .cancelled, .notStarted: .secondary
            }
        }
    }
#endif
