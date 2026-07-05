import Foundation

public struct GitHubReleaseLatestStrategy: LatestStrategy {
    public init() {}

    public func latest(for recipe: Recipe, context: LatestContext) throws -> String {
        guard let repository = GitHubRepositoryRef.parse(recipe.source.ref),
            let url = repository.releasesAPIURL
        else {
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
