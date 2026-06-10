import Foundation

public struct GitHubReleaseLatestStrategy: LatestStrategy {
    public init() {}

    public func latest(for recipe: Recipe, context: LatestContext) throws -> String {
        let ref = recipe.source.ref
        let url: URL
        if ref.contains("github.com") {
            let parts = ref.split(separator: "/").suffix(2).map(String.init)
            guard parts.count == 2 else { throw LatestError.invalidSource(ref) }
            url = URL(string: "https://api.github.com/repos/\(parts[0])/\(parts[1])/releases")!
        } else {
            url = URL(string: "https://api.github.com/repos/\(ref)/releases")!
        }
        var headers: [String: String] = ["Accept": "application/vnd.github+json"]
        if let token = context.githubToken {
            headers["Authorization"] = "Bearer \(token)"
        }
        let data = try context.httpClient.get(url: url, headers: headers)
        let releases = try JSONDecoder().decode([Release].self, from: data)
        guard let release = releases.first(where: { !$0.draft && !$0.prerelease }) else {
            throw LatestError.parseFailed("no stable GitHub release found")
        }
        return release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
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
