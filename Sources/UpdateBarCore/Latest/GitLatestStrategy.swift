import Foundation

public struct GitLatestStrategy: LatestStrategy {
    public enum Mode {
        case head
        case tags
    }

    private let mode: Mode

    public init(mode: Mode) {
        self.mode = mode
    }

    public func latest(for recipe: Recipe, context: LatestContext) throws -> String {
        switch mode {
        case .head:
            let branch = recipe.source.branch ?? "HEAD"
            let command = [
                "git",
                "ls-remote",
                "--",
                ShellQuote.single(recipe.source.ref),
                ShellQuote.single("refs/heads/\(branch)"),
            ].joined(separator: " ")
            let result = try context.commandRunner.run(
                ShellCommand(command: command, cwd: nil),
                policy: ExecutionPolicy(timeout: 60, maxOutputBytes: 128 * 1024)
            )
            guard result.exitCode == 0 else {
                throw LatestError.commandFailed(
                    "git ls-remote exited \(result.exitCode): \(SecretRedactor.redact(result.stderr))"
                )
            }
            let fields = result.stdout.split { $0 == "\t" || $0 == " " || $0 == "\n" }
            guard let head = fields.first.map(String.init) else {
                throw LatestError.parseFailed("git head not found: \(branch)")
            }
            return head
        case .tags:
            let command =
                "git ls-remote --tags -- \(ShellQuote.single(recipe.source.ref))"
            let result = try context.commandRunner.run(
                ShellCommand(command: command, cwd: nil),
                policy: ExecutionPolicy(timeout: 60, maxOutputBytes: 128 * 1024)
            )
            guard result.exitCode == 0 else {
                throw LatestError.commandFailed(
                    "git ls-remote exited \(result.exitCode): \(SecretRedactor.redact(result.stderr))"
                )
            }
            let tags = result.stdout.split(separator: "\n").compactMap { line -> String? in
                guard let tagPart = line.split(separator: "\t").last else { return nil }
                var tag = String(tagPart).replacingOccurrences(of: "refs/tags/", with: "")
                tag = tag.replacingOccurrences(of: "^{}", with: "")
                if tag.hasPrefix("v") { tag.removeFirst() }
                return tag
            }
            let semverTags = tags.filter { tag in
                (try? VersionComparator.compareSemVer(tag, tag)) != nil
            }
            let latest = semverTags.max { lhs, rhs in
                let comparison = try? VersionComparator.compareSemVer(lhs, rhs)
                return comparison == .orderedAscending
            }
            guard let latest else {
                throw LatestError.parseFailed("no git semver tags found")
            }
            return latest
        }
    }
}
