import ArgumentParser
import UpdateBarCore

struct BackgroundCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "background",
        abstract: "Manage the opt-in background check LaunchAgent.",
        shouldDisplay: false,
        subcommands: [Install.self, Status.self, Uninstall.self]
    )

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "install",
            abstract: "Install the background check LaunchAgent."
        )

        @Flag(name: .long, help: "Install without prompting for confirmation.")
        var yes = false

        @Flag(name: .long, help: "Print machine-readable JSON.")
        var json = false

        func run() throws {
#if os(macOS)
            guard yes else {
                throw ValidationError("background install requires --yes")
            }

            let manager = BackgroundLaunchAgentManager()
            let intervalSeconds = try ConfigStore().loadExistingOrDefault().refresh.interval.seconds
            let url = try manager.install(intervalSeconds: intervalSeconds)
            let payload = BackgroundInstallPayload(
                ok: true,
                installed: true,
                path: url.path,
                label: BackgroundLaunchAgentManager.label
            )
            if json {
                try printJSON(payload)
            } else {
                printBackgroundHuman(status: "installed", path: url.path)
                printBackgroundInstallNextStep(path: url.path)
            }
#else
            throw ValidationError("background helper is only supported on macOS")
#endif
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show background check LaunchAgent status."
        )

        @Flag(name: .long, help: "Print machine-readable JSON.")
        var json = false

        func run() throws {
#if os(macOS)
            let manager = BackgroundLaunchAgentManager()
            let payload = BackgroundStatusPayload(
                ok: true,
                installed: manager.isInstalled,
                path: manager.plistURL.path,
                label: BackgroundLaunchAgentManager.label
            )
            if json {
                try printJSON(payload)
            } else {
                printBackgroundHuman(status: payload.installed ? "installed" : "not_installed", path: payload.path)
            }
#else
            throw ValidationError("background helper is only supported on macOS")
#endif
        }
    }

    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "uninstall",
            abstract: "Remove the background check LaunchAgent."
        )

        @Flag(name: .long, help: "Print machine-readable JSON.")
        var json = false

        func run() throws {
#if os(macOS)
            let manager = BackgroundLaunchAgentManager()
            let removed = try manager.uninstall()
            let payload = BackgroundUninstallPayload(
                ok: true,
                removed: removed,
                path: manager.plistURL.path,
                label: BackgroundLaunchAgentManager.label
            )
            if json {
                try printJSON(payload)
            } else {
                printBackgroundHuman(status: removed ? "removed" : "not_installed", path: manager.plistURL.path)
                if removed {
                    printBackgroundUninstallNextStep()
                }
            }
#else
            throw ValidationError("background helper is only supported on macOS")
#endif
        }
    }
}

#if os(macOS)
private func printBackgroundHuman(status: String, path: String) {
    writeStdout("STATUS\tLABEL\tPATH")
    writeStdout("\(status)\t\(BackgroundLaunchAgentManager.label)\t\(path)")
}

private func printBackgroundInstallNextStep(path: String) {
    printNextCommands([
        "launchctl bootstrap gui/$(id -u) \(shellQuote(path))"
    ])
}

private func printBackgroundUninstallNextStep() {
    printNextCommands([
        "launchctl bootout gui/$(id -u)/\(BackgroundLaunchAgentManager.label)"
    ])
}

private func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}
#endif
