import Foundation

public struct GitHubReleaseLatestStrategy: LatestStrategy {
    public init() {}

    public func latest(for recipe: Recipe, context: LatestContext) throws -> String {
        let repository = try repositoryParts(from: recipe.source.ref)
        guard let url = URL(
            string: "https://api.github.com/repos/\(repository.owner)/\(repository.name)/releases"
        ) else {
            throw invalidRepositoryRef(recipe.source.ref)
        }
        var headers: [String: String] = ["Accept": "application/vnd.github+json"]
        if let token = context.githubToken {
            headers["Authorization"] = "Bearer \(token)"
        }
        let data = try context.httpClient.get(
            url: url,
            headers: headers,
            requireHTTPSFinalURL: true
        )
        let releases = try JSONDecoder().decode([Release].self, from: data)
        guard let release = releases.first(where: { !$0.draft && !$0.prerelease }) else {
            throw LatestError.parseFailed("no stable GitHub release found")
        }
        if release.tagName.hasPrefix("v") {
            return String(release.tagName.dropFirst())
        }
        return release.tagName
    }

    private func repositoryParts(from ref: String) throws -> (owner: String, name: String) {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == ref, !trimmed.isEmpty else {
            throw invalidRepositoryRef(ref)
        }

        if let url = URL(string: trimmed),
            let host = url.host?.lowercased(),
            host == "github.com" || host == "www.github.com"
        {
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else {
                throw invalidRepositoryRef(ref)
            }
            return try validatedRepository(owner: parts[0], name: parts[1], ref: ref)
        }

        guard !trimmed.contains("github.com") else {
            throw invalidRepositoryRef(ref)
        }
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count == 2 else {
            throw invalidRepositoryRef(ref)
        }
        return try validatedRepository(owner: parts[0], name: parts[1], ref: ref)
    }

    private func validatedRepository(
        owner: String,
        name: String,
        ref: String
    ) throws -> (owner: String, name: String) {
        guard !owner.isEmpty,
            !name.isEmpty,
            !owner.contains(where: \.isWhitespace),
            !name.contains(where: \.isWhitespace)
        else {
            throw invalidRepositoryRef(ref)
        }
        return (owner, name)
    }

    private func invalidRepositoryRef(_ ref: String) -> LatestError {
        LatestError.invalidSource("\(ref): invalid GitHub repository ref")
    }

    private struct Release: Decodable {
        var tagName: String
        var draft: Bool
        var prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft
            case prerelease
        }
    }
}
