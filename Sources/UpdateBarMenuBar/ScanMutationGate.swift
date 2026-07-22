import Foundation

public enum ScanMutationServiceIntent: Equatable, Sendable {
    case register
    case setEnabled(Bool)
}

public struct ScanRowMutation: Equatable, Sendable {
    public var id: String
    public var previous: ScanTrackingState
    public var target: ScanTrackingState

    public init(id: String, previous: ScanTrackingState, target: ScanTrackingState) {
        self.id = id
        self.previous = previous
        self.target = target
    }

    public var serviceIntent: ScanMutationServiceIntent? {
        switch previous {
        case .untracked:
            return .register
        case .enabled:
            return .setEnabled(false)
        case .disabled:
            return .setEnabled(true)
        case .unavailable:
            return nil
        }
    }
}

public struct ScanMutationGate: Sendable {
    private var pending: [String: ScanRowMutation] = [:]

    public init() {}

    public var hasPendingMutations: Bool {
        !pending.isEmpty
    }

    public func isPending(id: String) -> Bool {
        pending[id] != nil
    }

    public mutating func begin(
        id: String,
        previous: ScanTrackingState,
        target: ScanTrackingState
    ) -> ScanRowMutation? {
        guard pending[id] == nil else { return nil }
        let mutation = ScanRowMutation(id: id, previous: previous, target: target)
        pending[id] = mutation
        return mutation
    }

    public mutating func finish(id: String) -> ScanRowMutation? {
        pending.removeValue(forKey: id)
    }
}
