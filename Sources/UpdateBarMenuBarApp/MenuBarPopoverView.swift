#if os(macOS)
    import Foundation
    import SwiftUI
    import UpdateBarMenuBar

    enum MenuBarPopoverLayout {
        static let size = CGSize(width: 340, height: 520)
    }

    enum MenuBarPopoverTab: String, CaseIterable, Hashable, Identifiable {
        case overview = "Overview"
        case updates = "Updates"
        case approvals = "Approvals"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .overview:
                return "rectangle.grid.1x2"
            case .updates:
                return "arrow.down.circle"
            case .approvals:
                return "checkmark.shield"
            }
        }
    }

    struct MenuBarPopoverView: View {
        let model: MenuBarPopoverModel
        let onItemAction: (MenuBarPopoverRow) -> Void
        let onMenuAction: (MenuBarMenuAction) -> Void
        let onAbout: () -> Void

        @State private var selectedTab: MenuBarPopoverTab = .overview

        var body: some View {
            VStack(spacing: 0) {
                header
                Divider()
                tabBar
                Divider()
                selectedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                Divider()
                commandArea
            }
            .frame(
                width: MenuBarPopoverLayout.size.width,
                height: MenuBarPopoverLayout.size.height,
                alignment: .top
            )
            .background(Color.clear)
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("UpdateBar")
                        .font(.headline)
                    Spacer(minLength: 8)
                    Label("\(model.trackedItemCount) tracked", systemImage: "shippingbox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Label(model.headerTitle, systemImage: model.headerSymbol)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .help(model.headerHealthText)
                        .accessibilityLabel(model.headerHealthText)
                    Spacer(minLength: 8)
                    Label(lastCheckedSummary, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(lastCheckedText)
                        .accessibilityLabel(lastCheckedText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }

        private var tabBar: some View {
            Picker("Section", selection: $selectedTab) {
                ForEach(MenuBarPopoverTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }

        @ViewBuilder
        private var selectedContent: some View {
            switch selectedTab {
            case .overview:
                overview
            case .updates:
                rowList(
                    model.updates,
                    emptyTitle: "No updates available",
                    emptyDetail: "Tracked items are current.",
                    emptySymbol: "checkmark.circle"
                )
            case .approvals:
                rowList(
                    model.approvals,
                    emptyTitle: "No approvals needed",
                    emptyDetail: "There are no commands waiting for approval.",
                    emptySymbol: "checkmark.shield"
                )
            }
        }

        private var overview: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    countSummary

                    if let activeActionTitle = model.activeActionTitle {
                        overviewDivider
                        statusRow(
                            "Running",
                            detail: activeActionTitle,
                            symbol: "bolt.horizontal.circle"
                        )
                    }
                    if let lastActionNotice = model.lastActionNotice {
                        overviewDivider
                        statusRow("Last action", detail: lastActionNotice, symbol: "info.circle")
                    }
                    if let errorMessage = model.errorMessage {
                        overviewDivider
                        statusRow(
                            "Error",
                            detail: errorMessage,
                            symbol: "exclamationmark.triangle"
                        )
                    }

                    summarySection("Available Updates", rows: model.updates)
                    summarySection("Errors", rows: model.errors)

                    if model.updates.isEmpty && model.errors.isEmpty
                        && model.activeActionTitle == nil && model.lastActionNotice == nil
                        && model.errorMessage == nil
                    {
                        overviewDivider
                        statusRow(
                            "Status",
                            detail: "All tracked items are current.",
                            symbol: "checkmark.circle"
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }

        private var countSummary: some View {
            HStack(spacing: 0) {
                summaryCount("Updates", value: model.updateCount, symbol: "arrow.down.circle")
                Divider()
                    .frame(height: 28)
                summaryCount("Approvals", value: model.approvalCount, symbol: "checkmark.shield")
                Divider()
                    .frame(height: 28)
                summaryCount(
                    "Errors", value: model.errorCount, symbol: "exclamationmark.triangle")
            }
            .padding(.vertical, 3)
        }

        private func summaryCount(_ title: String, value: Int, symbol: String) -> some View {
            VStack(spacing: 1) {
                Text("\(value)")
                    .font(.callout.monospacedDigit().weight(.semibold))
                Label(title, systemImage: symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(value)")
        }

        private var overviewDivider: some View {
            Divider()
                .padding(.vertical, 4)
        }

        private func statusRow(_ title: String, detail: String, symbol: String) -> some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(detail)")
            .help(detail)
        }

        @ViewBuilder
        private func summarySection(_ title: String, rows: [MenuBarPopoverRow]) -> some View {
            if !rows.isEmpty {
                overviewDivider
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                let visibleRows = Array(rows.prefix(3))
                ForEach(visibleRows) { row in
                    rowView(row)
                    if row.id != visibleRows.last?.id {
                        Divider()
                            .padding(.leading, 25)
                    }
                }

                if rows.count > visibleRows.count {
                    Text("\(rows.count - visibleRows.count) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 3)
                        .padding(.leading, 25)
                }
            }
        }

        private func rowList(
            _ rows: [MenuBarPopoverRow],
            emptyTitle: String,
            emptyDetail: String,
            emptySymbol: String
        ) -> some View {
            Group {
                if rows.isEmpty {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: emptySymbol)
                            .frame(width: 16)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(emptyTitle)
                                .font(.callout.weight(.medium))
                            Text(emptyDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
                    .accessibilityElement(children: .combine)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                rowView(row)
                                if row.id != rows.last?.id {
                                    Divider()
                                        .padding(.leading, 25)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                }
            }
        }

        @ViewBuilder
        private func rowView(_ row: MenuBarPopoverRow) -> some View {
            if row.action != nil {
                Button {
                    onItemAction(row)
                } label: {
                    rowLabel(row)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rowAccessibilityLabel(row))
                .help(row.detail)
            } else {
                rowLabel(row)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(rowAccessibilityLabel(row))
                    .help(row.detail)
            }
        }

        private func rowLabel(_ row: MenuBarPopoverRow) -> some View {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: rowSymbol(row))
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(row.stateLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }

        private var commandArea: some View {
            VStack(spacing: 0) {
                if let activeActionTitle = model.activeActionTitle {
                    commandButton("Cancel Current Action", symbol: "stop.circle") {
                        onItemAction(cancelCurrentActionRow(title: activeActionTitle))
                    }
                    commandDivider
                }

                commandButton("Open Dashboard", symbol: "rectangle.grid.1x2") {
                    onMenuAction(.overview)
                }
                commandButton("Manage Items", symbol: "list.bullet.rectangle") {
                    onMenuAction(.manageItems)
                }

                commandDivider

                openTUICommand
                commandButton("Refresh", symbol: "arrow.clockwise") {
                    onMenuAction(.refreshStatus)
                }

                commandDivider

                commandButton("Settings", symbol: "gearshape") {
                    onMenuAction(.openConfig)
                }
                commandButton("About", symbol: "info.circle", action: onAbout)
                moreMenu
                commandButton("Quit", symbol: "power") {
                    onMenuAction(.quit)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }

        private var commandDivider: some View {
            Divider()
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
        }

        @ViewBuilder
        private var openTUICommand: some View {
            if model.terminals.count > 1 {
                Menu {
                    ForEach(model.terminals) { terminal in
                        Button {
                            onItemAction(openTUIRow(for: terminal))
                        } label: {
                            Label(
                                terminal.id == model.selectedTerminalID
                                    ? "\(terminal.name) (Selected)" : terminal.name,
                                systemImage: terminal.id == model.selectedTerminalID
                                    ? "checkmark" : "terminal"
                            )
                        }
                    }
                } label: {
                    MenuCommandLabel(title: "Open TUI", symbol: "terminal")
                }
                .menuStyle(.borderlessButton)
                .commandRowStyle()
                .accessibilityLabel("Open TUI")
            } else {
                commandButton("Open TUI", symbol: "terminal") {
                    if let terminal = model.terminals.first {
                        onItemAction(openTUIRow(for: terminal))
                    } else {
                        onMenuAction(.openTUI)
                    }
                }
            }
        }

        private var moreMenu: some View {
            Menu {
                Button {
                    onMenuAction(.checkNow)
                } label: {
                    Label("Check Now", systemImage: "magnifyingglass")
                }
                Button {
                    onMenuAction(.updateAllApprovedOutdated)
                } label: {
                    Label("Run Updates", systemImage: "arrow.down.circle")
                }
                .disabled(model.updateCount == 0)
                .help(
                    model.updateCount == 0
                        ? "No updates available."
                        : "Runs approved outdated items after confirmation."
                )
                .accessibilityLabel("Run Updates")
                .accessibilityValue(
                    model.updateCount == 0
                        ? "No updates available."
                        : "\(model.updateCount) update\(model.updateCount == 1 ? "" : "s") available."
                )
                Divider()
                Button {
                    onMenuAction(.scanAndAdd)
                } label: {
                    Label("Scan & Add", systemImage: "plus.magnifyingglass")
                }
                Button {
                    onMenuAction(.viewLogs)
                } label: {
                    Label("View Logs", systemImage: "doc.text.magnifyingglass")
                }
            } label: {
                MenuCommandLabel(title: "More", symbol: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .commandRowStyle()
            .accessibilityLabel("More actions")
        }

        private func commandButton(
            _ title: String,
            symbol: String,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                MenuCommandLabel(title: title, symbol: symbol)
            }
            .buttonStyle(.plain)
            .commandRowStyle()
            .accessibilityLabel(title)
        }

        private func openTUIRow(for terminal: TUITerminal) -> MenuBarPopoverRow {
            MenuBarPopoverRow(
                id: "open-tui-\(terminal.id)",
                title: "Open TUI",
                detail: "Open in \(terminal.name)",
                stateLabel: terminal.id == model.selectedTerminalID
                    ? "Selected terminal" : "Terminal",
                action: .openTUIInTerminal(bundleID: terminal.id),
                confirmation: nil
            )
        }

        private func cancelCurrentActionRow(title: String) -> MenuBarPopoverRow {
            MenuBarPopoverRow(
                id: "cancel-current-action",
                title: "Cancel Current Action",
                detail: title,
                stateLabel: "Running",
                action: .cancelCurrentAction,
                confirmation: nil
            )
        }

        private func rowAccessibilityLabel(_ row: MenuBarPopoverRow) -> String {
            "\(row.title), \(row.detail), \(row.stateLabel)"
        }

        private func rowSymbol(_ row: MenuBarPopoverRow) -> String {
            if let action = row.action {
                switch action {
                case .update:
                    return "arrow.down.circle"
                case .approve:
                    return "checkmark.circle"
                case .revoke:
                    return "xmark.circle"
                case .openTUIInTerminal:
                    return "terminal"
                case .menu:
                    return "arrow.right.circle"
                case .cancelCurrentAction:
                    return "stop.circle"
                }
            }

            if row.stateLabel.localizedCaseInsensitiveContains("error") {
                return "exclamationmark.triangle"
            }
            if row.stateLabel.localizedCaseInsensitiveContains("approval") {
                return "checkmark.shield"
            }
            return "info.circle"
        }

        private var lastCheckedSummary: String {
            guard let lastChecked = model.lastChecked else {
                return "Never"
            }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return formatter.localizedString(for: lastChecked, relativeTo: Date())
        }

        private var lastCheckedText: String {
            guard let lastChecked = model.lastChecked else {
                return "Last checked: Never"
            }
            let date = lastChecked.formatted(
                .dateTime.month(.abbreviated).day().hour().minute()
            )
            return "Last checked: \(lastCheckedSummary) (\(date))"
        }

    }

    private struct MenuCommandLabel: View {
        let title: String
        let symbol: String

        var body: some View {
            Label(title, systemImage: symbol)
                .font(.callout)
                .lineLimit(1)
                .padding(.horizontal, 7)
        }
    }

    private struct CommandRowModifier: ViewModifier {
        @FocusState private var isFocused: Bool
        @State private var isHovered = false

        func body(content: Content) -> some View {
            content
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .contentShape(Rectangle())
                .focused($isFocused)
                .background(
                    isFocused
                        ? Color.accentColor.opacity(0.18)
                        : isHovered ? Color.primary.opacity(0.07) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .onHover { isHovered = $0 }
        }
    }

    extension View {
        fileprivate func commandRowStyle() -> some View {
            modifier(CommandRowModifier())
        }
    }
#endif
