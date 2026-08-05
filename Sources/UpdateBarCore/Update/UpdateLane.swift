import Foundation

/// Derives the package manager an update command will contend on.
///
/// Homebrew, npm, and similar tools take a process-wide lock, so two recipes
/// that resolve to the same lane must never run at the same time. The lane is
/// read from `update.cmd` rather than `Recipe.source.kind` because the lock
/// belongs to the tool being executed, not to where the version came from: a
/// recipe can have `source.kind == .githubRelease` and
/// `update.cmd == "brew upgrade foo"`.
enum UpdateLane {
    private static let wrappers: Set<String> = [
        "sudo", "env", "command", "nice", "nohup", "time", "exec",
    ]

    private static let wrapperValueFlags: [String: Set<String>] = [
        "sudo": ["-u", "-g", "-h", "-p", "-r", "-t", "-C", "-D", "-R", "-T", "-U"],
        "env": ["-u", "-S"],
        "nice": ["-n"],
        "time": ["-o", "-f"],
        "exec": ["-a"],
    ]

    /// Returns `nil` when no tool name can be read, in which case the caller
    /// should give the recipe a private lane so it runs unconstrained.
    static func key(forCommand command: String) -> String? {
        let tokens = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var i = 0
        var currentWrapper: String?

        while i < tokens.count {
            let text = tokens[i]

            if isEnvironmentAssignment(text) {
                i += 1
                continue
            }

            if text.hasPrefix("-") {
                // Only skip the next token if the current wrapper has this flag in its set.
                if let wrapper = currentWrapper,
                    let flagsForWrapper = wrapperValueFlags[wrapper],
                    flagsForWrapper.contains(text),
                    i + 1 < tokens.count
                {
                    i += 2  // Skip the flag and its argument
                    continue
                }
                i += 1
                continue
            }

            let name = URL(fileURLWithPath: text).lastPathComponent.lowercased()
            if name.isEmpty || name == "/" {
                i += 1
                continue
            }

            if wrappers.contains(name) {
                currentWrapper = name
                i += 1
                continue
            }

            return name
        }

        return nil
    }

    private static func isEnvironmentAssignment(_ token: String) -> Bool {
        guard let equals = token.firstIndex(of: "=") else { return false }
        let name = token[token.startIndex..<equals]
        guard let first = name.first, first == "_" || first.isLetter else { return false }
        return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }
}
