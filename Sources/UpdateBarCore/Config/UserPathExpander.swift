import Foundation

enum UserPathExpander {
    static func homeDirectory(environment: [String: String]) -> URL {
        if let home = environment["HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    static func expandTilde(in path: String, homeDirectory: URL) -> String {
        guard path == "~" || path.hasPrefix("~/") else {
            return path
        }
        let home = homeDirectory.path
        if path == "~" { return home }
        return home + String(path.dropFirst())
    }
}
