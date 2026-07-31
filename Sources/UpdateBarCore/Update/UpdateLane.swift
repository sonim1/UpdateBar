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

    /// Returns `nil` when no tool name can be read, in which case the caller
    /// should give the recipe a private lane so it runs unconstrained.
    static func key(forCommand command: String) -> String? {
        let tokens = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var i = 0

        while i < tokens.count {
            let text = tokens[i]

            if isEnvironmentAssignment(text) {
                i += 1
                continue
            }

            if text.hasPrefix("-") {
                // Single-letter options like -u typically take an argument.
                if text.count == 2 && text.dropFirst().first?.isLetter == true {
                    // Check if next token could be the option's argument.
                    if i + 1 < tokens.count && !tokens[i + 1].hasPrefix("-")
                        && !isEnvironmentAssignment(tokens[i + 1])
                    {
                        i += 2  // Skip the flag and its argument
                        continue
                    }
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
