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
            let intervalSeconds = try ConfigStore().load().refresh.interval.seconds
            let url = try manager.install(intervalSeconds: intervalSeconds)
            let payload = BackgroundInstallPayload(ok: true, installed: true, path: url.path)
            if json {
                try printJSON(payload)
            } else {
                print("installed \(url.path)")
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
                print("STATUS\tLABEL\tPATH")
                print("\(payload.installed ? "installed" : "not_installed")\t\(payload.label)\t\(payload.path)")
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
            let payload = BackgroundUninstallPayload(ok: true, removed: removed, path: manager.plistURL.path)
            if json {
                try printJSON(payload)
            } else {
                print(removed ? "uninstalled" : "not installed")
            }
#else
            throw ValidationError("background helper is only supported on macOS")
#endif
        }
    }
}
