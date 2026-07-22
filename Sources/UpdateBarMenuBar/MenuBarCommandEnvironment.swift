import Foundation

public enum MenuBarCommandEnvironment {
    public static func make(
        base: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: String] {
        let allowedKeys = Set(["PATH", "HOME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR", "USER"])
        var environment = base.filter { allowedKeys.contains($0.key) }
        let existing = (base["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.hasPrefix("/") }
        let common = [
            homeDirectory.appendingPathComponent(".local/bin").path,
            homeDirectory.appendingPathComponent(".volta/bin").path,
            homeDirectory.appendingPathComponent(".asdf/shims").path,
            homeDirectory.appendingPathComponent(".nodenv/shims").path,
            homeDirectory.appendingPathComponent(".nvm/current/bin").path,
            homeDirectory.appendingPathComponent(".local/share/fnm/aliases/default/bin").path,
            homeDirectory.appendingPathComponent(".cargo/bin").path,
            homeDirectory.appendingPathComponent(".bun/bin").path,
            homeDirectory.appendingPathComponent(".local/share/mise/shims").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        var seen: Set<String> = []
        environment["PATH"] = (existing + common)
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
        return environment
    }
}
