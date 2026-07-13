public struct MenuBarRefreshGenerationGate: Sendable {
    private var latestToken = 0

    public init() {}

    public mutating func begin() -> Int {
        latestToken += 1
        return latestToken
    }

    public func isCurrent(_ token: Int) -> Bool {
        token == latestToken
    }
}
