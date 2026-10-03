public struct StatusApprovalsSnapshot: Equatable {
    public let status: StatusSnapshot
    public let approvalsByItemID: [String: [ApprovalStatus]]

    public init(status: StatusSnapshot, approvalsByItemID: [String: [ApprovalStatus]]) {
        self.status = status
        self.approvalsByItemID = approvalsByItemID
    }
}
