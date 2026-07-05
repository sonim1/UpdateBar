import Foundation

public struct AppPaths: Equatable {
    public var homeDirectory: URL

    public init(
        homeDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        if let homeDirectory {
            self.homeDirectory = URL(fileURLWithPath: homeDirectory.path).standardizedFileURL
            return
        }
        if let override = environment["UPDATEBAR_HOME"], !override.isEmpty {
            self.homeDirectory = URL(fileURLWithPath: override).standardizedFileURL
            return
        }
        if let homeOverride = environment["HOME"], !homeOverride.isEmpty {
            self.homeDirectory =
                URL(fileURLWithPath: homeOverride)
                .appendingPathComponent(".updatebar")
                .standardizedFileURL
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.homeDirectory =
            URL(fileURLWithPath: home.appendingPathComponent(".updatebar").path)
            .standardizedFileURL
    }

    public var manifestFile: URL {
        homeDirectory.appendingPathComponent("manifest.json", isDirectory: false)
    }

    public var stateFile: URL {
        homeDirectory.appendingPathComponent("state.json", isDirectory: false)
    }

    public var configFile: URL {
        homeDirectory.appendingPathComponent("config.toml", isDirectory: false)
    }
}
