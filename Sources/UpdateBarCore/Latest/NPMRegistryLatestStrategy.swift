import Foundation

public struct NPMRegistryLatestStrategy: LatestStrategy {
    public init() {}

    public func latest(for recipe: Recipe, context: LatestContext) throws -> String {
        let encoded = percentEncode(recipe.source.ref)
        guard let url = URL(string: "https://registry.npmjs.org/\(encoded)") else {
            throw LatestError.invalidSource("\(recipe.source.ref): invalid npm package ref")
        }
        let data = try context.httpClient.get(
            url: url,
            headers: [:],
            requireHTTPSFinalURL: true
        )
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let tags = object?["dist-tags"] as? [String: Any],
            let latest = tags["latest"] as? String
        else {
            throw LatestError.parseFailed("npm dist-tags.latest missing")
        }
        return latest
    }

    private func percentEncode(_ package: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return package.addingPercentEncoding(withAllowedCharacters: allowed) ?? package
    }
}
