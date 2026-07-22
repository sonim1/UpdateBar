import Foundation
import UpdateBarCore

public enum ScanTrackingState: Equatable, Sendable {
    case untracked
    case enabled
    case disabled
    case unavailable(String)
}

public struct ScanListRow: Equatable {
    public var candidate: ScanCandidate
    public var trackingState: ScanTrackingState

    public init(candidate: ScanCandidate, trackingState: ScanTrackingState) {
        self.candidate = candidate
        self.trackingState = trackingState
    }

    public var isChecked: Bool {
        trackingState == .enabled
    }

    public var canToggle: Bool {
        if case .unavailable = trackingState {
            return false
        }
        return true
    }

    public var stateLabel: String {
        switch trackingState {
        case .untracked:
            return "new"
        case .enabled:
            return "enabled"
        case .disabled:
            return "disabled"
        case .unavailable(let reason):
            return reason
        }
    }
}

public struct ScanListModel: Sendable {
    public init() {}

    public func rows(
        from report: ScanReport,
        registeredStatuses: [String: ItemStatus]
    ) -> [ScanListRow] {
        report.candidates.map { candidate in
            let trackingState: ScanTrackingState
            if let status = registeredStatuses[candidate.id] {
                trackingState = status == .disabled ? .disabled : .enabled
            } else if candidate.capability == .full, candidate.recipe != nil {
                trackingState = .untracked
            } else {
                trackingState = .unavailable(candidate.capability.rawValue)
            }
            return ScanListRow(candidate: candidate, trackingState: trackingState)
        }
    }
}
