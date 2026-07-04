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
        source.filter { presentationKeys.contains($0.key) && !$0.value.isEmpty }
    }
}
