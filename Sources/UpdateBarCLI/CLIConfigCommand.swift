import ArgumentParser
import UpdateBarCore

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Read or update UpdateBar configuration.",
        shouldDisplay: false,
        subcommands: [Get.self, Set.self]
    )

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Read one config value or all config."
        )

        @Argument(help: "Config key to read; omit to show all config.")
        var key: String?

        @Flag(name: .long, help: "Print machine-readable JSON.")
        var json = false

        func run() throws {
            let config = try ConfigStore().load()
            if let key {
                guard let value = config.get(key) else {
                    throw ConfigError.unknownKey(key)
                }
                if json {
                    try printJSON(ConfigValuePayload(key: key, value: value))
                } else {
                    print(value)
                }
            } else if json {
                try printJSON(ConfigDumpPayload(config: config))
            } else {
                print(ConfigStore().renderForDisplay(config))
            }
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Update one config value."
        )

        @Argument(help: "Config key to update.")
        var key: String

        @Argument(help: "Value to store.")
        var value: String

        @Flag(name: .long, help: "Print machine-readable JSON.")
        var json = false

        func run() throws {
            let store = ConfigStore()
            var config = try store.load()
            try config.set(key, value: value)
            try store.save(config)
            if json {
                try printJSON(ConfigSetPayload(ok: true, key: key, value: value))
            } else {
                print("updated \(key)")
            }
        }
    }
}
