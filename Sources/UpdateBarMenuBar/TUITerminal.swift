import Foundation

public struct TUITerminal: Equatable, Sendable, Identifiable {
    public enum LaunchStyle: Equatable, Sendable {
        /// The app opens `.command` files as documents (Terminal, iTerm).
        case openDocument
        /// The app needs the command file passed as a process argument,
        /// optionally behind terminal-specific flags (Ghostty, kitty, ...).
        case openWithArgs([String])
    }

    /// Application bundle identifier; also the persisted selection key.
    public var id: String
    public var name: String
    public var launchStyle: LaunchStyle

    public init(id: String, name: String, launchStyle: LaunchStyle) {
        self.id = id
        self.name = name
        self.launchStyle = launchStyle
    }

    public static let known: [TUITerminal] = [
        TUITerminal(
            id: "com.apple.Terminal",
            name: "Terminal",
            launchStyle: .openDocument
        ),
        TUITerminal(
            id: "com.googlecode.iterm2",
            name: "iTerm",
            launchStyle: .openDocument
        ),
        TUITerminal(
            id: "com.mitchellh.ghostty",
            name: "Ghostty",
            launchStyle: .openWithArgs(["-e"])
        ),
        TUITerminal(
            id: "net.kovidgoyal.kitty",
            name: "kitty",
            launchStyle: .openWithArgs([])
        ),
        TUITerminal(
            id: "org.alacritty",
            name: "Alacritty",
            launchStyle: .openWithArgs(["-e"])
        ),
        TUITerminal(
            id: "com.github.wez.wezterm",
            name: "WezTerm",
            launchStyle: .openWithArgs(["start", "--"])
        ),
    ]

    public static let fallback = known[0]

    public static func known(id: String) -> TUITerminal? {
        known.first { $0.id == id }
    }
}
