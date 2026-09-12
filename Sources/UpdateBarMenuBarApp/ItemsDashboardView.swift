#if os(macOS)
    import SwiftUI
    import UpdateBarCore
    import UpdateBarMenuBar

    private enum ItemsLayout {
        static let compact: CGFloat = 6
        static let regular: CGFloat = 12
        static let inset: CGFloat = 20
        static let section: CGFloat = 24
        static let cardRadius: CGFloat = 10
        static let cardMinimumWidth: CGFloat = 310
    }

    struct ItemsDashboardView: View {
        @ObservedObject var store: ItemsDashboardStore

        var body: some View {
            VStack(spacing: 0) {
                toolbar
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: ItemsLayout.section) {
                        notices
                        progressSummary
                        inventory
                    }
                    .padding(ItemsLayout.inset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("items-scroll")
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .sheet(
                isPresented: Binding(
                    get: { store.detailItem != nil },
                    set: { if !$0 { store.closeDetails() } }
                )
            ) {
                if let item = store.detailItem {
                    ItemDetailView(store: store, item: item)
                }
            }
        }

        private var toolbar: some View {
            VStack(alignment: .leading, spacing: ItemsLayout.regular) {
                HStack(alignment: .center, spacing: ItemsLayout.regular) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Items")
                            .font(.system(size: 24, weight: .bold))
                        Text(toolbarSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: ItemsLayout.regular)
                    Button(action: store.check) {
                        Label("Check", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.model.isBusy || store.isMutationPending)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Check approved items for updates")
                    .accessibilityLabel("Check for updates")
                    .accessibilityIdentifier("items-check")
                    Button(action: store.update) {
                        Label(store.primaryAction.title, systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        store.model.isBusy || store.isMutationPending
                            || store.primaryAction.ids.isEmpty
                    )
                    .accessibilityLabel(store.primaryAction.title)
                    .accessibilityIdentifier("items-update")
                }
                HStack(spacing: ItemsLayout.regular) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField(
                            "Search tools…",
                            text: Binding(
                                get: { store.selection.query },
                                set: { query in store.setQuery(query) }
                            )
                        )
                        .textFieldStyle(.plain)
                    }
                    .accessibilityLabel("Search tools")
                    .padding(.horizontal, 10)
                    .frame(maxWidth: 360, minHeight: 34)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    .accessibilityIdentifier("items-search")
                    if !store.selection.selectedIDs.isEmpty {
                        Text("\(store.selection.selectedIDs.count) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Clear selection", action: store.clearSelection)
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Clear item selection")
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(ItemsLayout.inset)
        }

        @ViewBuilder
        private var notices: some View {
            if let error = store.model.errorMessage ?? store.mutationError {
                ItemsNotice(
                    title: "Couldn’t complete the action", message: error,
                    symbol: "exclamationmark.triangle", color: .red
                )
            }
            if !store.model.isBusy, let notice = store.model.notice {
                ItemsNotice(title: notice, message: nil, symbol: "info.circle", color: .blue)
            }
        }

        @ViewBuilder
        private var progressSummary: some View {
            if store.model.isUpdating || !store.model.progress.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(progressTitle)
                                .font(.headline)
                            Text(progressSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if store.supportsStopping && store.model.isUpdating {
                            Button(
                                store.model.stopRequested ? "Stopping…" : "Stop after current",
                                action: store.stop
                            )
                            .buttonStyle(.borderless)
                            .disabled(store.model.stopRequested)
                            .accessibilityLabel("Stop after current update")
                        } else if !store.model.retryIDs.isEmpty && !store.model.isBusy {
                            Button("Retry failed", action: store.retryFailed)
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Retry failed updates")
                        }
                    }
                    if store.model.progress.totalCount == 0 {
                        ProgressView()
                    } else {
                        ProgressView(
                            value: Double(store.model.progress.completedCount),
                            total: Double(store.model.progress.totalCount)
                        )
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: ItemsLayout.cardRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: ItemsLayout.cardRadius)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }
                .accessibilityIdentifier("items-progress")
            }
        }

        @ViewBuilder
        private var inventory: some View {
            if store.model.state.allItems.isEmpty && !store.model.isBusy {
                ItemsEmptyState(
                    title: "No tracked items",
                    message: "Use Scan & Add to find tools you want UpdateBar to track.",
                    symbol: "shippingbox"
                )
            } else {
                ForEach(ManageItemsSectionKind.allCases, id: \.self) { kind in
                    if let section = store.sections.first(where: { $0.kind == kind }),
                        !section.items.isEmpty
                    {
                        ItemsStatusSection(store: store, section: section)
                    }
                }
                if store.sections.allSatisfy(\.items.isEmpty) {
                    ItemsEmptyState(
                        title: "No matching items",
                        message: "No tracked tool matches “\(store.selection.query)”.",
                        symbol: "magnifyingglass"
                    )
                    Button("Clear search") { store.setQuery("") }
                        .frame(maxWidth: .infinity)
                }
            }
        }

        private var toolbarSubtitle: String {
            let count = store.model.state.allItems.count
            guard let date = store.model.lastChecked else { return "\(count) tracked tools" }
            return
                "\(count) tracked tools · Checked \(date.formatted(.relative(presentation: .named)))"
        }

        private var progressTitle: String {
            if store.model.isUpdating {
                return store.model.activeActionTitle ?? "Updating tools"
            }
            return "Last update finished"
        }

        private var progressSubtitle: String {
            if store.model.stopRequested { return store.model.stopMessage }
            let progress = store.model.progress
            guard progress.totalCount > 0 else {
                return store.model.activeActionTitle ?? "Update in progress"
            }
            let running = progress.inFlightIDs.count
            return
                "\(progress.completedCount) of \(progress.totalCount) finished · \(running) running"
        }
    }

    private struct ItemsStatusSection: View {
        @ObservedObject var store: ItemsDashboardStore
        let section: ManageItemsSection
        @SwiftUI.State private var disclosed: Bool

        init(store: ItemsDashboardStore, section: ManageItemsSection) {
            self.store = store
            self.section = section
            _disclosed = SwiftUI.State(initialValue: section.isExpanded)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: ItemsLayout.regular) {
                if section.kind == .current || section.kind == .paused {
                    DisclosureGroup(isExpanded: disclosureBinding) {
                        compactRows
                            .padding(.top, 8)
                    } label: {
                        sectionHeader
                    }
                } else {
                    sectionHeader
                    if section.kind == .ready {
                        LazyVGrid(
                            columns: [
                                GridItem(
                                    .adaptive(minimum: ItemsLayout.cardMinimumWidth), spacing: 12
                                )
                            ],
                            spacing: 12
                        ) {
                            ForEach(section.items, id: \.id) { item in
                                ReadyItemCard(store: store, item: item)
                            }
                        }
                    } else {
                        compactRows
                    }
                }
            }
            .accessibilityIdentifier("items-section-\(String(describing: section.kind))")
        }

        private var disclosureBinding: Binding<Bool> {
            Binding(
                get: { section.isExpanded || disclosed },
                set: { disclosed = $0 }
            )
        }

        private var sectionHeader: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: section.kind.systemImage)
                        .foregroundStyle(sectionColor)
                        .accessibilityHidden(true)
                    Text(section.kind.title)
                        .font(.title3.weight(.semibold))
                    Text("\(section.items.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
                Text(section.kind.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        private var compactRows: some View {
            VStack(spacing: 0) {
                ForEach(section.items, id: \.id) { item in
                    CompactItemRow(store: store, item: item, kind: section.kind)
                    if item.id != section.items.last?.id { Divider() }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: ItemsLayout.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ItemsLayout.cardRadius)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }

        private var sectionColor: Color {
            switch section.kind {
            case .ready: .blue
            case .review: .orange
            case .attention: .red
            case .current: .green
            case .paused: .secondary
            }
        }
    }

    private struct ReadyItemCard: View {
        @ObservedObject var store: ItemsDashboardStore
        let item: StatusItem

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    ItemMonogram(item: item)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.headline).lineLimit(2)
                        Text(item.category.isEmpty ? "Uncategorized" : item.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Toggle(
                        "Select \(item.name)",
                        isOn: Binding(
                            get: { store.selection.contains(item.id) },
                            set: { _ in store.toggleSelection(item) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(store.model.isBusy || store.isMutationPending)
                    .accessibilityLabel(
                        store.selection.contains(item.id)
                            ? "Deselect \(item.name)" : "Select \(item.name)"
                    )
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(store.statusText(for: item))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(store.phase(for: item) == .failed ? .red : .secondary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Details") { store.showDetails(item) }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Show details for \(item.name)")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(
                store.selection.contains(item.id)
                    ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor)
            )
            .clipShape(RoundedRectangle(cornerRadius: ItemsLayout.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ItemsLayout.cardRadius)
                    .stroke(
                        store.selection.contains(item.id)
                            ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: store.selection.contains(item.id) ? 2 : 1
                    )
            }
            .accessibilityIdentifier("items-card-\(item.id)")
        }
    }

    private struct CompactItemRow: View {
        @ObservedObject var store: ItemsDashboardStore
        let item: StatusItem
        let kind: ManageItemsSectionKind

        var body: some View {
            HStack(spacing: 12) {
                ItemMonogram(item: item)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.headline).lineLimit(2)
                    Text(store.statusText(for: item))
                        .font(.caption)
                        .foregroundStyle(kind == .attention ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(kind == .review ? "Review" : "Details") { store.showDetails(item) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(
                        kind == .review
                            ? "Review commands for \(item.name)" : "Show details for \(item.name)"
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityIdentifier("items-row-\(item.id)")
        }
    }

    private struct ItemMonogram: View {
        let item: StatusItem

        var body: some View {
            Text(monogram)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)
                .background(Color.blue.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
        }

        private var monogram: String {
            let words = item.name.split(separator: " ")
            if words.count > 1 {
                return words.prefix(2).reduce(into: "") { result, word in
                    if let first = word.first { result.append(first) }
                }
            }
            return String(item.name.prefix(2))
        }
    }

    private struct ItemsNotice: View {
        let title: String
        let message: String?
        let symbol: String
        let color: Color

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private struct ItemDetailView: View {
        @ObservedObject var store: ItemsDashboardStore
        let item: StatusItem

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Review · \(item.name)").font(.title2.weight(.semibold))
                        Text(item.category.isEmpty ? "Uncategorized" : item.category)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Done", action: store.closeDetails)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Close item details")
                }
                .padding(20)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        LabeledContent("Status", value: store.statusText(for: item))
                        LabeledContent(
                            "Tracking",
                            value: store.displayedEnabledState(for: item) ? "Enabled" : "Disabled"
                        )
                        Button(
                            store.displayedEnabledState(for: item)
                                ? "Disable tracking" : "Enable tracking"
                        ) {
                            store.setEnabled(
                                id: item.id,
                                enabled: !store.displayedEnabledState(for: item)
                            )
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.model.isBusy || store.isMutationPending)
                        .accessibilityLabel(
                            store.displayedEnabledState(for: item)
                                ? "Disable tracking for \(item.name)"
                                : "Enable tracking for \(item.name)"
                        )

                        if let commands = store.model.approvals[item.id], !commands.isEmpty {
                            Divider()
                            Text("Commands").font(.headline)
                            ForEach(commands, id: \.field) { command in
                                CommandReviewCard(store: store, item: item, command: command)
                            }
                        }

                        if store.model.readyToCheckItems.contains(where: { $0.id == item.id }) {
                            Divider()
                            Text("Approval saved. Run a check to refresh this tool’s status.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Check Now", action: store.check)
                                .buttonStyle(.borderedProminent)
                                .disabled(store.model.isBusy)
                                .accessibilityLabel("Check for updates now")
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minWidth: 520, idealWidth: 600, minHeight: 400, idealHeight: 520)
            .accessibilityIdentifier("items-details")
        }
    }

    private struct CommandReviewCard: View {
        @ObservedObject var store: ItemsDashboardStore
        let item: StatusItem
        let command: CommandApprovalStatus

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(command.field).font(.headline)
                    Spacer()
                    Text(command.approved ? "Approved" : "Approval required")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(command.approved ? .green : .orange)
                }
                Text(SecretRedactor.redact(command.command))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let cwd = command.cwd, !cwd.isEmpty {
                    LabeledContent("Working directory") {
                        Text(SecretRedactor.redact(cwd))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                if !command.approved {
                    Toggle(
                        "I reviewed this exact command and working directory.",
                        isOn: Binding(
                            get: { store.model.isAcknowledged(id: item.id, field: command.field) },
                            set: {
                                store.setAcknowledged($0, id: item.id, field: command.field)
                            }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Confirm review of \(command.field)")
                }
                Button(command.approved ? "Revoke approval" : "Approve command") {
                    store.setApproval(id: item.id, field: command.field)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    store.model.reviewedApproval(id: item.id, field: command.field) == nil
                )
                .accessibilityLabel(
                    command.approved
                        ? "Revoke approval for \(command.field)"
                        : "Approve \(command.field)"
                )
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private struct ItemsEmptyState: View {
        let title: String
        let message: String
        let symbol: String

        var body: some View {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title).font(.title3.weight(.semibold))
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .accessibilityElement(children: .combine)
        }
    }

    extension ItemsDashboardStore {
        fileprivate var isMutationPending: Bool {
            model.state.allItems.contains { isMutationPending(id: $0.id) }
        }
    }
#endif
