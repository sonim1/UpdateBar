import Foundation
import UpdateBarCore

public struct ScanListRow: Equatable {
    public var candidate: ScanCandidate
    public var isRegistered: Bool
    public var isSelected: Bool

    public init(candidate: ScanCandidate, isRegistered: Bool, isSelected: Bool = false) {
        self.candidate = candidate
        self.isRegistered = isRegistered
        self.isSelected = isSelected
    }

    /// Only unregistered candidates with a full recipe can be imported.
    public var isImportable: Bool {
        !isRegistered && candidate.capability == .full && candidate.recipe != nil
    }

    public var stateLabel: String {
        if isRegistered { return "registered" }
        return isImportable ? "importable" : candidate.capability.rawValue
    }
}

public struct ScanListModel: Sendable {
    public init() {}

    public func rows(
        from report: ScanReport,
        registeredIDs: Set<String>
    ) -> [ScanListRow] {
        report.candidates.map { candidate in
            ScanListRow(
                candidate: candidate,
                isRegistered: registeredIDs.contains(candidate.id)
            )
        }
    }
}
