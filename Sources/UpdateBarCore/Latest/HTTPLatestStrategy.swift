import Foundation

public struct HTTPLatestStrategy: LatestStrategy {
    public init() {}

    public func latest(for recipe: Recipe, context: LatestContext) throws -> String {
        guard let url = URL(string: recipe.source.ref) else {
            throw LatestError.invalidSource(recipe.source.ref)
        }
        guard let pattern = recipe.latest.pattern else {
            throw LatestError.missingField("latest.pattern")
        }
        let data = try context.httpClient.get(url: url, headers: [:])
        let text = String(decoding: data, as: UTF8.self)
        return try VersionParser.extract(from: text, using: .regex(pattern))
    }
}

public struct CommandLatestStrategy: LatestStrategy {
    public init() {}

    public func latest(for recipe: Recipe, context: LatestContext) throws -> String {
        guard let cmd = recipe.latest.cmd else {
            throw LatestError.missingField("latest.cmd")
        }
        let result = try context.commandRunner.run(
            ShellCommand(command: cmd, cwd: nil),
            policy: ExecutionPolicy(timeout: 60, maxOutputBytes: 128 * 1024)
        )
        guard result.exitCode == 0 else { throw LatestError.commandFailed(result.stderr) }
        return try VersionParser.extract(from: result.stdout, using: recipe.versionParse)
    }
}
