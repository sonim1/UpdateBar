public enum SubprocessEnvironment {
    public static let presentationKeys: Set<String> = [
        "PATH",
        "HOME",
        "LANG",
        "LC_ALL",
        "LC_CTYPE",
        "TMPDIR",
        "USER",
        "TERM",
        "COLORTERM",
        "NO_COLOR",
        "FORCE_COLOR",
        "UPDATEBAR_HOME",
        "GITHUB_TOKEN",
        "GH_TOKEN",
    ]

    public static func presentation(from source: [String: String]) -> [String: String] {
        var environment = source.filter { presentationKeys.contains($0.key) && !$0.value.isEmpty }
        if let path = environment["PATH"] {
            environment["PATH"] = path
                .split(separator: ":", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { $0.hasPrefix("/") }
                .joined(separator: ":")
        }
        return environment
    }
}
