import UpdateBarCore

public enum MenuBarCommandReviewError: Error, CustomStringConvertible {
    case commandChanged

    public var description: String {
        "This command changed while you were reviewing it. Check again and review the new command."
    }
}

public struct MenuBarRetryCheckError: Error, CustomStringConvertible {
    public let description: String

    init(item: StatusItem) {
        description = SecretRedactor.redact(
            "Could not recheck \(item.name): \(item.error ?? "check failed"). No updates were retried."
        )
    }
}

extension MenuBarServicing {
    public func setReviewedApproval(
        id: String,
        reviewed: CommandApprovalStatus,
        approving: Bool,
        cancellationToken: CancellationToken? = nil
    ) throws {
        let current = try approvals(id: id).first { $0.field == reviewed.field }
        guard current == reviewed else { throw MenuBarCommandReviewError.commandChanged }
        if approving {
            try approve(id: id, field: reviewed.field, cancellationToken: cancellationToken)
        } else {
            try revoke(id: id, field: reviewed.field, cancellationToken: cancellationToken)
        }
    }

    public func retryFailedUpdates(
        ids: [String],
        cancellationToken: CancellationToken? = nil,
        onEvent: UpdateProgressHandler? = nil,
        stopSignal: UpdateStopSignal? = nil
    ) throws {
        guard !ids.isEmpty else { return }
        // Failed updates leave an error state. The existing planner requires
        // a successful check before it can classify the item as outdated again.
        try checkNow(cancellationToken: cancellationToken)
        guard stopSignal?.isStopRequested != true else { return }
        let snapshot = try status(refresh: false)
        if let failedCheck = snapshot.items.first(where: {
            ids.contains($0.id) && $0.status == .error
        }) {
            throw MenuBarRetryCheckError(item: failedCheck)
        }
        try update(
            ids: ids,
            cancellationToken: cancellationToken,
            onEvent: onEvent,
            stopSignal: stopSignal
        )
    }
}
