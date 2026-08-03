#if os(macOS)
    import SwiftUI

    struct AboutView: View {
        let version: String
        let build: String
        let onSupport: () -> Void
        let onAcknowledgments: () -> Void

        var body: some View {
            VStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 88, height: 88)
                Text("UpdateBar").font(.title.weight(.semibold))
                Text("Keep your local developer tools up to date, safely and quietly.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                VStack(spacing: 4) {
                    Text("Version (version)")
                    if !build.isEmpty && build != "—" { Text("Build (build)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Contact Support", action: onSupport)
                    Button("Acknowledgments", action: onAcknowledgments)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(36)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
#endif
