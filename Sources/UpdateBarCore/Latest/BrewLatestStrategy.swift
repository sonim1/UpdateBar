import Foundation

public struct BrewLatestStrategy: LatestStrategy {
    public init() {}

    public func latest(for recipe: Recipe, context: LatestContext) throws -> String {
        let command = "brew info --json=v2 -- \(ShellQuote.single(recipe.source.ref))"
        let result = try context.commandRunner.run(
            ShellCommand(command: command, cwd: nil),
            policy: ExecutionPolicy(timeout: 60, maxOutputBytes: 128 * 1024)
        )
        guard result.exitCode == 0 else {
            throw LatestError.commandFailed(
                "brew info exited \(result.exitCode): \(SecretRedactor.redact(result.stderr))"
            )
        }
        let data = Data(result.stdout.utf8)
        let payload = try JSONDecoder().decode(BrewPayload.self, from: data)
        guard let stable = payload.formulae.first?.versions.stable else {
            throw LatestError.parseFailed("brew stable version missing")
        }
        return stable
    }

    private struct BrewPayload: Decodable {
        var formulae: [Formula]
    }

    private struct Formula: Decodable {
        var versions: Versions
    }

    private struct Versions: Decodable {
        var stable: String
    }
}
