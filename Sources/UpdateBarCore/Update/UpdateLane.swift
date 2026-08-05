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
    /// Commands whose executable cannot be determined without reproducing a
    /// shell wrapper's argument parser share one lane rather than risking an
    /// unsafe overlap with a package manager command.
    static let sharedSerialKey = "updatebar:shared-serial"

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

    private static let wrapperBooleanFlags: [String: Set<String>] = [
        "sudo": [
            "-A", "-b", "-E", "-H", "-K", "-k", "-n", "-S", "-s", "-v", "-i", "--non-interactive",
        ],
        "env": ["-i", "--ignore-environment"],
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
                guard let wrapper = currentWrapper else { return sharedSerialKey }
                if text == "--" {
                    i += 1
                    continue
                }
                if wrapper == "env", text == "-S" {
                    guard i + 1 < tokens.count, isUnambiguousToken(tokens[i + 1])
                    else { return sharedSerialKey }
                    i += 1
                    continue
                }
                if wrapperValueFlags[wrapper]?.contains(text) == true {
                    guard i + 1 < tokens.count else { return sharedSerialKey }
                    i += 2
                    continue
                }
                if wrapperBooleanFlags[wrapper]?.contains(text) == true {
                    i += 1
                    continue
                }
                return sharedSerialKey
            }

            guard isUnambiguousToken(text) else { return sharedSerialKey }
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

    private static func isUnambiguousToken(_ token: String) -> Bool {
        !token.isEmpty && !token.contains { "'\"`$;&|()<>\\".contains($0) }
    }
}
