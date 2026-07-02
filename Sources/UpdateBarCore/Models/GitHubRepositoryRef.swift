import Foundation

struct GitHubRepositoryRef: Equatable {
    var owner: String
    var name: String

    static func parse(_ ref: String) -> GitHubRepositoryRef? {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == ref, !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
            let host = url.host?.lowercased(),
            host == "github.com" || host == "www.github.com"
        {
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { return nil }
            return make(owner: parts[0], name: parts[1])
        }

        guard !trimmed.contains("github.com") else { return nil }
        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return nil }
        return make(owner: parts[0], name: parts[1])
    }

    var releasesAPIURL: URL? {
        URL(string: "https://api.github.com/repos/\(owner)/\(name)/releases")
    }

    private static func make(owner: String, name: String) -> GitHubRepositoryRef? {
        guard isValidPart(owner), isValidPart(name) else { return nil }
        return GitHubRepositoryRef(owner: owner, name: name)
    }

    private static func isValidPart(_ value: String) -> Bool {
        !value.isEmpty && !value.contains(where: \.isWhitespace)
    }
}
