import Foundation
import UpdateBarCore

public final class MenuBarActiveAction: @unchecked Sendable {
    public let title: String
    public let token: CancellationToken

    init(title: String, token: CancellationToken) {
        self.title = title
        self.token = token
    }
}

public enum MenuBarActionOutcome {
    case finished
    case cancelled
    case failed
}

public final class MenuBarActionCoordinator {
    public private(set) var activeAction: MenuBarActiveAction?
    public private(set) var lastActionNotice: String?

    public init() {}

    public func begin(_ title: String) -> MenuBarActiveAction? {
        if let activeAction {
            lastActionNotice = "Already running: \(activeAction.title)"
            return nil
        }
        let action = MenuBarActiveAction(title: title, token: CancellationToken())
        activeAction = action
        lastActionNotice = nil
        return action
    }

    @discardableResult
    public func cancelActive() -> MenuBarActiveAction? {
        guard let activeAction else { return nil }
        activeAction.token.cancel()
        lastActionNotice = "Cancelling: \(activeAction.title)"
        return activeAction
    }

    public func finish(_ action: MenuBarActiveAction, outcome: MenuBarActionOutcome) {
        guard activeAction === action else { return }
        activeAction = nil
        switch outcome {
        case .finished:
            lastActionNotice = "Finished: \(action.title)"
        case .cancelled:
            lastActionNotice = "Cancelled: \(action.title)"
        case .failed:
            lastActionNotice = "Failed: \(action.title)"
        }
    }
}
