#if os(macOS)
    import Accessibility
    import AppKit
    import Charts
    import Foundation
    import SwiftUI
    import UpdateBarCore
    import UpdateBarMenuBar

    private struct DashboardView: View {
        var summary: DashboardSummary
        var onOpenItems: () -> Void

        private let metricColumns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("UpdateBar")
                            .font(.title2.weight(.semibold))
                        Text(statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 16)

                    Button(action: onOpenItems) {
                        Label("Manage Items", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Manage Items")
                }

                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 12) {
                    tile(
                        title: "Updates",
                        value: "\(summary.pendingUpdates)",
                        systemImage: "arrow.down.circle"
                    )
                    tile(
                        title: "Awaiting Approval",
                        value: "\(summary.approvalsWaiting)",
                        systemImage: "hourglass"
                    )
                    tile(
                        title: "Last Checked",
                        value: shortDate(summary.lastChecked),
                        systemImage: "magnifyingglass"
                    )
                    tile(
                        title: "Last Updated",
                        value: shortDate(summary.lastUpdated),
                        systemImage: "clock"
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Updates · last 4 weeks")
                        .font(.headline)

                    ZStack {
                        Chart(summary.updatesPerDay, id: \.day) { bucket in
                            BarMark(
                                x: .value("Day", bucket.day, unit: .day),
                                y: .value("Updates", bucket.count)
                            )
                        }
                        .chartYAxis {
                            AxisMarks(values: .automatic(desiredCount: 3))
                        }
                        .chartXScale(
                            range: .plotDimension(startPadding: 20, endPadding: 20)
                        )
                        .accessibilityChartDescriptor(
                            UpdatesChartDescriptor(buckets: summary.updatesPerDay)
                        )

                        if let chartEmptyMessage {
                            Text(chartEmptyMessage)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 120, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(20)
            .frame(minWidth: 620, minHeight: 420, alignment: .topLeading)
        }

        private var statusText: String {
            if summary.pendingUpdates == 0, summary.approvalsWaiting == 0 {
                return "Everything is up to date."
            }

            var parts: [String] = []
            if summary.pendingUpdates > 0 {
                let noun = summary.pendingUpdates == 1 ? "update" : "updates"
                parts.append("\(summary.pendingUpdates) \(noun) available")
            }
            if summary.approvalsWaiting > 0 {
                let noun = summary.approvalsWaiting == 1 ? "item" : "items"
                parts.append("\(summary.approvalsWaiting) \(noun) awaiting approval")
            }
            return parts.joined(separator: " · ")
        }

        private var totalUpdates: Int {
            summary.updatesPerDay.reduce(0) { $0 + $1.count }
        }

        private var chartEmptyMessage: String? {
            if summary.updatesPerDay.isEmpty {
                return "No update history available"
            }
            if totalUpdates == 0 {
                return "No updates in the last 4 weeks"
            }
            return nil
        }

        private func tile(title: String, value: String, systemImage: String) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 24, alignment: .leading)
                    .help(value)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                .quaternary.opacity(0.5),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value)
        }

        private func shortDate(_ date: Date?) -> String {
            guard let date else { return "–" }
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
    }

    private struct UpdatesChartDescriptor: AXChartDescriptorRepresentable {
        var buckets: [DashboardDayCount]

        func makeChartDescriptor() -> AXChartDescriptor {
            let dateLabels = buckets.map { dateLabel($0.day) }
            let xAxis = AXCategoricalDataAxisDescriptor(
                title: "Date",
                categoryOrder: dateLabels
            )
            let maximumCount = buckets.map(\.count).max() ?? 0
            let yAxis = AXNumericDataAxisDescriptor(
                title: "Update count",
                range: 0...Double(max(1, maximumCount)),
                gridlinePositions: []
            ) { value in
                countLabel(Int(value.rounded()))
            }
            let dataPoints = zip(buckets, dateLabels).map { bucket, dateLabel in
                AXDataPoint(
                    x: dateLabel,
                    y: Double(bucket.count),
                    label: "\(dateLabel): \(countLabel(bucket.count))"
                )
            }
            let series = AXDataSeriesDescriptor(
                name: "Daily updates",
                isContinuous: false,
                dataPoints: dataPoints
            )

            return AXChartDescriptor(
                title: "Updates in the last 4 weeks",
                summary: descriptorSummary,
                xAxis: xAxis,
                yAxis: yAxis,
                series: [series]
            )
        }

        private var descriptorSummary: String {
            guard let first = buckets.first, let last = buckets.last else {
                return "No daily update data is available."
            }
            let firstDate = dateLabel(first.day)
            let lastDate = dateLabel(last.day)
            return "Daily update counts from \(firstDate) through \(lastDate)."
        }

        private func dateLabel(_ date: Date) -> String {
            date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        }

        private func countLabel(_ count: Int) -> String {
            let noun = count == 1 ? "update" : "updates"
            return "\(count) \(noun)"
        }
    }

    final class DashboardPanelController: NSWindowController {
        private let service: any MenuBarServicing
        private let onOpenItems: () -> Void
        private let model = DashboardModel()

        init(
            service: any MenuBarServicing,
            onOpenItems: @escaping () -> Void
        ) {
            self.service = service
            self.onOpenItems = onOpenItems
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Dashboard"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 620, height: 420)
            super.init(window: window)
        }

        required init?(coder: NSCoder) {
            nil
        }

        func showWindowAndReload() {
            showWindow(nil)
            window?.center()
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            reload()
        }

        private func reload() {
            DispatchQueue.global(qos: .userInitiated).async { [service, model] in
                do {
                    let now = Date()
                    let since = Calendar.current.date(byAdding: .day, value: -28, to: now)
                    let snapshot = try service.status(refresh: false)
                    let events = try service.history(since: since)
                    let summary = model.summary(snapshot: snapshot, events: events, now: now)
                    DispatchQueue.main.async {
                        self.apply(summary)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.presentError(error)
                    }
                }
            }
        }

        private func apply(_ summary: DashboardSummary) {
            let view = DashboardView(
                summary: summary,
                onOpenItems: { [weak self] in
                    self?.onOpenItems()
                }
            )
            window?.contentView = NSHostingView(rootView: view)
        }

        private func presentError(_ error: Error) {
            guard let window else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "UpdateBar"
            alert.informativeText = SecretRedactor.redact(String(describing: error))
            alert.beginSheetModal(for: window)
        }
    }
#endif
