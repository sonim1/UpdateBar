import Foundation

public struct OpenTUICommand: Equatable, Sendable {
    public struct AuxiliaryFile: Equatable, Sendable {
        public var url: URL
        public var contents: String
    }

    /// Contents of the `.command` launcher script the app writes to disk.
    /// TUI discovery, UPDATEBAR_TUI overrides, and install guidance all live
    /// in the CLI's `tui` subcommand so the terminal only ever shows one
    /// short command.
    public var commandFileContents: String
    /// Extra file some terminals need before launch (Warp launch config).
    public var auxiliaryFile: AuxiliaryFile?
    public var executablePath: String
    public var arguments: [String]

    public init(
        cliPath: String,
        commandFileURL: URL,
        terminal: TUITerminal,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        commandFileContents = """
            #!/bin/sh
            exec \(Self.shellQuote(cliPath)) tui
            """
        executablePath = "/usr/bin/open"
        switch terminal.launchStyle {
        case .openDocument:
            auxiliaryFile = nil
            arguments = ["-b", terminal.id, commandFileURL.path]
        case .openWithArgs(let flags):
            auxiliaryFile = nil
            arguments = ["-nb", terminal.id, "--args"] + flags + [commandFileURL.path]
        case .warpLaunchConfigURI(let scheme):
            let configURL =
                homeDirectory
                .appendingPathComponent(".warp", isDirectory: true)
                .appendingPathComponent("launch_configurations", isDirectory: true)
                .appendingPathComponent("updatebar-tui.yaml", isDirectory: false)
            auxiliaryFile = AuxiliaryFile(
                url: configURL,
                contents: Self.warpLaunchConfig(
                    commandFilePath: commandFileURL.path,
                    homePath: homeDirectory.path
                )
            )
            let encodedPath =
                configURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                ?? configURL.path
            arguments = ["\(scheme)://launch/\(encodedPath)"]
        }
    }

    private static func warpLaunchConfig(commandFilePath: String, homePath: String) -> String {
        """
        ---
        name: UpdateBar TUI
        windows:
          - tabs:
              - title: UpdateBar TUI
                layout:
                  cwd: "\(homePath)"
                  commands:
                    - exec: \(shellQuote(commandFilePath))
        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
