import Foundation
import UpdateBarCore

public final class MenuBarActiveAction: @unchecked Sendable {
    public let title: String
    public let token: CancellationToken
    public let stopSignal: UpdateStopSignal
    /// Main-queue only. The app hops before applying progress events.
    public private(set) var progress = MenuBarItemProgress()

    init(title: String, token: CancellationToken) {
        self.title = title
        self.token = token
        self.stopSignal = UpdateStopSignal()
    }

    public var isStopRequested: Bool { stopSignal.isStopRequested }

    public func requestStop() {
        stopSignal.requestStop()
    }

    public func apply(_ event: UpdateProgressEvent) {
        progress.apply(event)
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

    /// Drains the queue: the running command finishes, nothing new starts.
    /// Deliberately not a cancel — killing a half-finished package manager
    /// leaves state UpdateBar cannot describe.
    @discardableResult
    public func stopActive() -> MenuBarActiveAction? {
        guard let activeAction else { return nil }
        activeAction.requestStop()
        lastActionNotice = "Stopping after current: \(activeAction.title)"
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
