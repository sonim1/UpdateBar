import Foundation

public struct BackgroundLaunchAgentManager {
    public static let label = "com.updatebar.check"

    private let environment: [String: String]
    private let executableName: String
    private let currentDirectory: URL
    private let fileManager: FileManager

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executableName: String = CommandLine.arguments[0],
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.executableName = executableName
        self.currentDirectory = currentDirectory
        self.fileManager = fileManager
    }

    public var plistURL: URL {
        userHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.label).plist", isDirectory: false)
    }

    public var isInstalled: Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    @discardableResult
    public func install(intervalSeconds: Int) throws -> URL {
        let directory = plistURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let plist = BackgroundLaunchAgentPlist(
            label: Self.label,
            programArguments: [
                executablePath,
                "check",
                "--exit-zero-on-outdated",
            ],
            startInterval: intervalSeconds,
            runAtLoad: true,
            environmentVariables: [
                "UPDATEBAR_HOME": AppPaths(environment: environment).homeDirectory.path
            ]
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(plist)
        try data.write(to: plistURL, options: [.atomic])
        return plistURL
    }

    public func uninstall() throws -> Bool {
        guard isInstalled else {
            return false
        }
        try fileManager.removeItem(at: plistURL)
        return true
    }

    private var userHome: URL {
        if let home = environment["HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home).standardizedFileURL
        }
        return fileManager.homeDirectoryForCurrentUser.standardizedFileURL
    }

    private var executablePath: String {
        if executableName.hasPrefix("/") {
            return URL(fileURLWithPath: executableName).standardizedFileURL.path
        }
        if executableName.contains("/") {
            let relativeExecutable = currentDirectory.appendingPathComponent(executableName)
            return relativeExecutable.standardizedFileURL.path
        }
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(executableName)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate.standardizedFileURL.path
            }
        }
        let fallbackExecutable = currentDirectory.appendingPathComponent(executableName)
        return fallbackExecutable.standardizedFileURL.path
    }
}

private struct BackgroundLaunchAgentPlist: Encodable {
    var label: String
    var programArguments: [String]
    var startInterval: Int
    var runAtLoad: Bool
    var environmentVariables: [String: String]

    enum CodingKeys: String, CodingKey {
        case label = "Label"
        case programArguments = "ProgramArguments"
        case startInterval = "StartInterval"
        case runAtLoad = "RunAtLoad"
        case environmentVariables = "EnvironmentVariables"
    }
}
