import UpdateBarCore

public struct ManageItemsMutationGate {
    private enum Mutation {
        case enabled(Bool)
        case pinned(Bool)
    }

    private var expectedState: (id: String, mutation: Mutation)?

    public init() {}

    public var isPending: Bool {
        expectedState != nil
    }

    public func isPending(id: String) -> Bool {
        expectedState?.id == id
    }

    public mutating func begin(id: String, enabled: Bool) {
        expectedState = (id, .enabled(enabled))
    }

    public mutating func begin(id: String, pinned: Bool) {
        expectedState = (id, .pinned(pinned))
    }

    public mutating func accepts(_ items: [StatusItem]) -> Bool {
        guard let expectedState else { return true }
        guard let item = items.first(where: { $0.id == expectedState.id }) else {
            return false
        }
        switch expectedState.mutation {
        case .enabled(let enabled):
            guard (item.status != .disabled) == enabled else { return false }
        case .pinned(let pinned):
            guard item.pinned == pinned else { return false }
        }
        self.expectedState = nil
        return true
    }

    public mutating func cancel() {
        expectedState = nil
    }
}
