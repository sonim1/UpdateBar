#if os(macOS)
    import Foundation
    import SwiftUI
    import UpdateBarMenuBar

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

        private let commandColumns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]

        var body: some View {
            VStack(spacing: 0) {
                header
                Divider()
                tabBar
                Divider()
                selectedContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: 240, alignment: .top)
                Divider()
                commandArea
            }
            .frame(width: 390, height: 560, alignment: .top)
            .background(Color.clear)
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("UpdateBar")
                        .font(.headline)
                    Spacer(minLength: 8)
                    Label("\(model.trackedItemCount) tracked", systemImage: "shippingbox")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(model.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .help(model.title)

                Label(lastCheckedText, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Label(healthText, systemImage: healthSymbol)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }

        private var tabBar: some View {
            HStack(spacing: 6) {
                ForEach(MenuBarPopoverTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.rawValue, systemImage: tab.systemImage)
                            .font(.callout.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .foregroundStyle(
                                selectedTab == tab ? Color.accentColor : Color.primary
                            )
                            .background(
                                selectedTab == tab
                                    ? Color.accentColor.opacity(0.14) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.rawValue)
                    .accessibilityValue(selectedTab == tab ? "Selected" : "Not selected")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
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
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        metric("Updates", value: model.updateCount, symbol: "arrow.down.circle")
                        metric("Approval", value: model.approvalCount, symbol: "checkmark.shield")
                        metric(
                            "Errors", value: model.errorCount, symbol: "exclamationmark.triangle")
                    }

                    if let activeActionTitle = model.activeActionTitle {
                        notice(
                            "Running",
                            detail: activeActionTitle,
                            symbol: "bolt.horizontal.circle"
                        )
                    }
                    if let lastActionNotice = model.lastActionNotice {
                        notice("Last action", detail: lastActionNotice, symbol: "info.circle")
                    }
                    if let errorMessage = model.errorMessage {
                        notice(
                            "Error",
                            detail: errorMessage,
                            symbol: "exclamationmark.triangle"
                        )
                    }

                    summarySection("Available Updates", rows: model.updates)
                    summarySection("Errors", rows: model.errors)
                }
                .padding(12)
            }
        }

        private func metric(_ title: String, value: Int, symbol: String) -> some View {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(value)")
                    .font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
        }

        private func notice(_ title: String, detail: String, symbol: String) -> some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: symbol)
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
            .padding(8)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(detail)")
            .help(detail)
        }

        @ViewBuilder
        private func summarySection(_ title: String, rows: [MenuBarPopoverRow]) -> some View {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(rows.prefix(3))) { row in
                        rowView(row)
                    }

                    if rows.count > 3 {
                        Text("\(rows.count - 3) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                    VStack(spacing: 6) {
                        Image(systemName: emptySymbol)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(emptyTitle)
                            .font(.headline)
                        Text(emptyDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
                    .accessibilityElement(children: .combine)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                rowView(row)
                                Divider()
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
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

                VStack(alignment: .leading, spacing: 2) {
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
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }

        private var commandArea: some View {
            VStack(spacing: 6) {
                if let activeActionTitle = model.activeActionTitle {
                    commandButton("Cancel Current Action", symbol: "stop.circle") {
                        onItemAction(cancelCurrentActionRow(title: activeActionTitle))
                    }
                }
                commandGrid
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }

        private var commandGrid: some View {
            LazyVGrid(columns: commandColumns, spacing: 6) {
                commandButton("Open Dashboard", symbol: "rectangle.grid.1x2") {
                    onMenuAction(.overview)
                }
                commandButton("Manage Items", symbol: "list.bullet.rectangle") {
                    onMenuAction(.manageItems)
                }
                openTUICommand
                commandButton("Refresh", symbol: "arrow.clockwise") {
                    onMenuAction(.refreshStatus)
                }
                commandButton("Settings", symbol: "gearshape") {
                    onMenuAction(.openConfig)
                }
                commandButton("About", symbol: "info.circle", action: onAbout)
                moreMenu
                commandButton("Quit", symbol: "power") {
                    onMenuAction(.quit)
                }
            }
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
                    commandLabel("Open TUI", symbol: "terminal")
                }
                .menuStyle(.borderlessButton)
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
                commandLabel("More", symbol: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("More actions")
        }

        private func commandButton(
            _ title: String,
            symbol: String,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                commandLabel(title, symbol: symbol)
            }
            .buttonStyle(.plain)
        }

        private func commandLabel(_ title: String, symbol: String) -> some View {
            Label(title, systemImage: symbol)
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 28)
                .padding(.horizontal, 8)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
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

        private var lastCheckedText: String {
            guard let lastChecked = model.lastChecked else {
                return "Last checked: Never"
            }
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .short
            let relative = relativeFormatter.localizedString(for: lastChecked, relativeTo: Date())
            let date = lastChecked.formatted(
                .dateTime.month(.abbreviated).day().hour().minute()
            )
            return "Last checked: \(relative) (\(date))"
        }

        private var healthText: String {
            if model.errorCount > 0 {
                return "Health: \(model.errorCount) error\(model.errorCount == 1 ? "" : "s")"
            }
            if model.approvalCount > 0 {
                return
                    "Health: approval required for \(model.approvalCount) item\(model.approvalCount == 1 ? "" : "s")"
            }
            if model.updateCount > 0 {
                return
                    "Health: \(model.updateCount) update\(model.updateCount == 1 ? "" : "s") available"
            }
            return "Health: All tracked items are current"
        }

        private var healthSymbol: String {
            if model.errorCount > 0 {
                return "exclamationmark.triangle"
            }
            if model.approvalCount > 0 {
                return "checkmark.shield"
            }
            if model.updateCount > 0 {
                return "arrow.down.circle"
            }
            return "checkmark.circle"
        }
    }
#endif
