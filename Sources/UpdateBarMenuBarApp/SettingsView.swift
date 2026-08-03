#if os(macOS)
    import SwiftUI
    import UpdateBarCore

    @MainActor
    final class SettingsViewModel: ObservableObject {
        @Published var refreshInterval = "6h"
        @Published var requireHTTPS = true
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    section("General") {
                        LabeledContent("Refresh interval") {
                            TextField("6h", text: $model.refreshInterval)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                        }
                        Toggle("Require HTTPS sources", isOn: $model.requireHTTPS)
                    }
                    section("Updates") {
                        LabeledContent("Current version") {
                            Text(model.version).foregroundStyle(.secondary)
                        }
                        Button("Check for Updates", action: model.onCheckForUpdates)
                            .buttonStyle(.borderedProminent)
                    }
                    HStack(spacing: 8) {
                        Button("Reload", action: model.onReload)
                        Button("Save", action: model.onSave)
                            .buttonStyle(.borderedProminent)
                        Text(model.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(model.isRunning)
            .background(Color(nsColor: .windowBackgroundColor))
        }

        private var header: some View {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("UpdateBar").font(.title2.weight(.semibold))
                    Text("Preferences")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Ready")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.14), in: Capsule())
                    .foregroundStyle(.green)
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
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
#endif
