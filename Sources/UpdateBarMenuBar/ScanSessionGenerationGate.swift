public struct ScanSessionGenerationGate: Sendable {
    private var latestToken = 0

    public init() {}

    public mutating func beginManualScan() -> Int {
        latestToken += 1
        return latestToken
    }

    public mutating func invalidateForWindowClose() {
        latestToken += 1
    }

    public func acceptsCurrentScan(_ token: Int) -> Bool {
        token == latestToken
    }
}
