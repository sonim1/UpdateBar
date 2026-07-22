import UpdateBarCore

public struct ManageItemsMutationGate {
    private var expectedState: (id: String, enabled: Bool)?

    public init() {}

    public var isPending: Bool {
        expectedState != nil
    }

    public func isPending(id: String) -> Bool {
        expectedState?.id == id
    }

    public mutating func begin(id: String, enabled: Bool) {
        expectedState = (id, enabled)
    }

    public mutating func accepts(_ items: [StatusItem]) -> Bool {
        guard let expectedState else { return true }
        guard let item = items.first(where: { $0.id == expectedState.id }) else {
            return false
        }
        guard (item.status != .disabled) == expectedState.enabled else {
            return false
        }
        self.expectedState = nil
        return true
    }

    public mutating func cancel() {
        expectedState = nil
    }
}
