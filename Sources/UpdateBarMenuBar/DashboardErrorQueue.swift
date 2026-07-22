public struct DashboardErrorPresentation: Equatable, Sendable {
    public let token: Int
    public let message: String

    public init(token: Int, message: String) {
        self.token = token
        self.message = message
    }
}

public struct DashboardErrorQueue: Equatable, Sendable {
    private var messages: [String] = []
    private var activePresentation: DashboardErrorPresentation?
    private var nextToken = 0

    public init() {}

    public var hasActivePresentation: Bool {
        activePresentation != nil
    }

    public var queuedMessageCount: Int {
        messages.count
    }

    public mutating func enqueue(_ message: String) {
        messages.append(message)
    }

    public mutating func beginNextPresentation() -> DashboardErrorPresentation? {
        guard activePresentation == nil, !messages.isEmpty else { return nil }
        nextToken &+= 1
        let presentation = DashboardErrorPresentation(
            token: nextToken,
            message: messages.removeFirst()
        )
        activePresentation = presentation
        return presentation
    }

    @discardableResult
    public mutating func finishPresentation(token: Int) -> Bool {
        guard activePresentation?.token == token else { return false }
        activePresentation = nil
        return true
    }

    public mutating func clear() {
        messages.removeAll()
        activePresentation = nil
    }
}
