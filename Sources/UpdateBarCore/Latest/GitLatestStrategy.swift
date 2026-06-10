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
            let command = "git ls-remote \(recipe.source.ref) refs/heads/\(branch)"
            let result = try context.commandRunner.run(
                ShellCommand(command: command, cwd: nil),
                policy: ExecutionPolicy(timeout: 60, maxOutputBytes: 128 * 1024)
            )
            guard result.exitCode == 0 else { throw LatestError.commandFailed(result.stderr) }
            return result.stdout.split { $0 == "\t" || $0 == " " || $0 == "\n" }.first.map(String.init) ?? ""
        case .tags:
            let command = "git ls-remote --tags \(recipe.source.ref)"
            let result = try context.commandRunner.run(
                ShellCommand(command: command, cwd: nil),
                policy: ExecutionPolicy(timeout: 60, maxOutputBytes: 128 * 1024)
            )
            guard result.exitCode == 0 else { throw LatestError.commandFailed(result.stderr) }
            let tags = result.stdout.split(separator: "\n").compactMap { line -> String? in
                guard let tagPart = line.split(separator: "\t").last else { return nil }
                var tag = String(tagPart).replacingOccurrences(of: "refs/tags/", with: "")
                tag = tag.replacingOccurrences(of: "^{}", with: "")
                if tag.hasPrefix("v") { tag.removeFirst() }
                return tag
            }
            return try tags.max { lhs, rhs in
                (try? VersionComparator.compareSemVer(lhs, rhs)) == .orderedAscending
            } ?? {
                throw LatestError.parseFailed("no git tags found")
            }()
        }
    }
}
