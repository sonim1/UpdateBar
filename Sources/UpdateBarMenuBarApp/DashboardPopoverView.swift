#if os(macOS)
    import SwiftUI
    import UpdateBarMenuBar

    enum DashboardPopoverLayout {
        static let size = CGSize(width: 340, height: 420)
    }

    enum DashboardPopoverTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case updates = "Updates"
        case approvals = "Approvals"

        var id: Self { self }
    }

    struct DashboardPopoverView: View {
        let model: DashboardPopoverModel
        let onOpenFullDashboard: () -> Void

        @State private var selection = DashboardPopoverTab.overview

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                header

                Picker("Section", selection: $selection) {
                    ForEach(DashboardPopoverTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Section")

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        tabContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .frame(
                width: DashboardPopoverLayout.size.width,
                height: DashboardPopoverLayout.size.height,
                alignment: .topLeading
            )
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("UpdateBar")
                        .font(.headline)

                    Spacer()

                    Label("\(model.trackedItemCount) tracked", systemImage: "shippingbox")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(action: onOpenFullDashboard) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Open Full Dashboard")
                    .accessibilityLabel("Open Full Dashboard")
                }

                HStack(spacing: 6) {
                    Image(systemName: healthSymbol)
                        .accessibilityHidden(true)
                    Text(healthLabel)
                        .fontWeight(.medium)
                    Spacer()
                    Text(lastCheckedLabel)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }

        @ViewBuilder
        private var tabContent: some View {
            switch selection {
            case .overview:
                overviewRows
            case .updates:
                itemRows(model.updates, emptyMessage: "No updates available")
            case .approvals:
                itemRows(model.approvals, emptyMessage: "No approvals waiting")
            }
        }

        private var overviewRows: some View {
            VStack(alignment: .leading, spacing: 0) {
                summaryRow(
                    title: "Updates",
                    value: model.updateCount,
                    systemImage: "arrow.down.circle"
                )
                summaryRow(
                    title: "Approvals",
                    value: model.approvalCount,
                    systemImage: "checkmark.shield"
                )
                summaryRow(
                    title: "Errors",
                    value: model.errorCount,
                    systemImage: "exclamationmark.triangle"
                )

                if let activeActionTitle = model.activeActionTitle {
                    detailRow(title: "Running", detail: activeActionTitle)
                }
                if let lastActionNotice = model.lastActionNotice {
                    detailRow(title: "Recent", detail: lastActionNotice)
                }
                if let errorMessage = model.errorMessage {
                    detailRow(title: "Error", detail: errorMessage)
                }

                ForEach(model.errors) { row in
                    itemRow(row, systemImage: "exclamationmark.triangle")
                }
            }
        }

        @ViewBuilder
        private func itemRows(_ rows: [DashboardPopoverRow], emptyMessage: String) -> some View {
            if rows.isEmpty {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                ForEach(rows) { row in
                    itemRow(row, systemImage: "circle.fill")
                }
            }
        }

        private func summaryRow(title: String, value: Int, systemImage: String) -> some View {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
                Text("\(value)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        }

        private func itemRow(_ row: DashboardPopoverRow, systemImage: String) -> some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .frame(width: 16, height: 18)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title)
                            .fontWeight(.medium)
                        Spacer(minLength: 8)
                        Text(row.stateLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 9)
            .accessibilityElement(children: .combine)
        }

        private func detailRow(title: String, detail: String) -> some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.callout)
                    .lineLimit(2)
            }
            .padding(.vertical, 9)
            .accessibilityElement(children: .combine)
        }

        private var healthLabel: String {
            if model.errorCount > 0 || model.errorMessage != nil {
                return "Needs attention"
            }
            if model.updateCount > 0 || model.approvalCount > 0 {
                return "Action available"
            }
            return "Up to date"
        }

        private var healthSymbol: String {
            model.errorCount > 0 || model.errorMessage != nil
                ? "exclamationmark.triangle.fill"
                : "checkmark.circle.fill"
        }

        private var lastCheckedLabel: String {
            guard let lastChecked = model.lastChecked else {
                return "Not checked"
            }
            return lastChecked.formatted(.relative(presentation: .named))
        }
    }
#endif
