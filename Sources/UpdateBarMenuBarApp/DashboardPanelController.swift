#if os(macOS)
    import AppKit
    import Charts
    import Foundation
    import SwiftUI
    import UpdateBarCore
    import UpdateBarMenuBar

    private struct DashboardView: View {
        var summary: DashboardSummary
        var onOpenItems: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    tile(
                        title: "Pending Updates",
                        value: "\(summary.pendingUpdates)"
                    )
                    tile(
                        title: "Awaiting Approval",
                        value: "\(summary.approvalsWaiting)"
                    )
                    tile(
                        title: "Last Checked",
                        value: shortDate(summary.lastChecked)
                    )
                    tile(
                        title: "Last Updated",
                        value: shortDate(summary.lastUpdated)
                    )
                }

                Text("Updates · last 4 weeks")
                    .font(.headline)
                Chart(summary.updatesPerDay, id: \.day) { bucket in
                    BarMark(
                        x: .value("Day", bucket.day, unit: .day),
                        y: .value("Updates", bucket.count)
                    )
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3))
                }
                .frame(minHeight: 160)

                HStack {
                    Spacer()
                    Button("Manage Items...", action: onOpenItems)
                }
            }
            .padding(16)
        }

        private func tile(title: String, value: String) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }

        private func shortDate(_ date: Date?) -> String {
            guard let date else { return "–" }
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
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
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 380),
                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "Overview"
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 520, height: 320)
            super.init(window: panel)
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
