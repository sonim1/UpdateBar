#if os(macOS)
    import SwiftUI
    import UpdateBarCore

    @MainActor
    final class SettingsViewModel: ObservableObject {
        // Time-only values must remain valid on local daylight-saving transition days.
        static let timePickerCalendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            return calendar
        }()

        @Published var refreshInterval = "6h"
        @Published var requireHTTPS = true
        @Published var maxConcurrent = Config.default.update.maxConcurrent
        @Published var scheduleMode = Config.default.schedule.mode
        @Published var scheduleTime = Date(timeIntervalSinceReferenceDate: 9 * 60 * 60)
        @Published var status = "Ready"
        @Published var isRunning = false

        let version: String
        let build: String
        var onReload: () -> Void
        var onSave: () -> Void
        let onCheckForUpdates: () -> Void

        init(
            version: String,
            build: String,
            onReload: @escaping () -> Void,
            onSave: @escaping () -> Void,
            onCheckForUpdates: @escaping () -> Void
        ) {
            self.version = version
            self.build = build
            self.onReload = onReload
            self.onSave = onSave
            self.onCheckForUpdates = onCheckForUpdates
        }
    }

    struct SettingsView: View {
        @ObservedObject var model: SettingsViewModel

        var body: some View {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        section("Daily maintenance") {
                            Picker("Action", selection: $model.scheduleMode) {
                                Text("Off").tag(ScheduleMode.off)
                                Text("Check only").tag(ScheduleMode.check)
                                Text("Check and update approved items").tag(
                                    ScheduleMode.checkAndUpdate)
                            }
                            .accessibilityIdentifier("settings-schedule-mode")
                            DatePicker(
                                "Every day at (local time)", selection: $model.scheduleTime,
                                displayedComponents: .hourAndMinute
                            )
                            .environment(\.timeZone, SettingsViewModel.timePickerCalendar.timeZone)
                            .environment(\.calendar, SettingsViewModel.timePickerCalendar)
                            .disabled(model.scheduleMode == .off)
                            .accessibilityIdentifier("settings-schedule-time")
                            Text(
                                "Runs once a day while UpdateBar is open. Missed runs start after your Mac wakes or the current task finishes."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if model.scheduleMode == .checkAndUpdate {
                                Text(
                                    "Only approved, enabled, unpinned items with an available update will be updated. Commands are never approved automatically."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        section("General") {
                            LabeledContent("Status cache lifetime") {
                                TextField("6h", text: $model.refreshInterval)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 150)
                            }
                            Toggle("Require HTTPS sources", isOn: $model.requireHTTPS)
                            Stepper(
                                "Parallel updates: \(model.maxConcurrent)",
                                value: $model.maxConcurrent,
                                in: UpdateConfig.validRange
                            )
                            .accessibilityIdentifier("settings-max-concurrent")
                        }
                        section("UpdateBar app") {
                            LabeledContent("Current version") {
                                Text(
                                    model.build.isEmpty || model.build == "—"
                                        ? model.version : "\(model.version) (\(model.build))"
                                )
                                .foregroundStyle(.secondary)
                            }
                            Button("Check for Updates", action: model.onCheckForUpdates)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                HStack(spacing: 8) {
                    Button("Reload", action: model.onReload)
                    Button("Save", action: model.onSave)
                        .buttonStyle(.borderedProminent)
                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
            }
            .disabled(model.isRunning)
            .background(Color(nsColor: .windowBackgroundColor))
        }

        private var header: some View {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("UpdateBar").font(.title2.weight(.semibold))
                    Text("Preferences")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.isRunning ? model.status : "Ready")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        (model.isRunning ? Color.orange : Color.green).opacity(0.14),
                        in: Capsule()
                    )
                    .foregroundStyle(model.isRunning ? .orange : .green)
            }
        }

        private func section<Content: View>(
            _ title: String,
            @ViewBuilder content: () -> Content
        ) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                VStack(alignment: .leading, spacing: 12, content: content)
                    .padding(16)
                    .background(
                        Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
        }
    }
#endif
