import Foundation
import UpdateBarCore

public struct DashboardMetricPresentation: Equatable, Sendable {
    public let iconName: String
    public let visibleValue: String
    public let help: String
    public let accessibilityLabel: String
    public let accessibilityValue: String

    public init(
        iconName: String,
        visibleValue: String,
        help: String,
        accessibilityLabel: String,
        accessibilityValue: String
    ) {
        self.iconName = iconName
        self.visibleValue = visibleValue
        self.help = help
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
    }
}

public struct DashboardScanCountPresentation: Equatable, Sendable {
    public let visibleValue: String
    public let help: String
    public let accessibilityLabel: String

    public init(
        visibleValue: String,
        help: String,
        accessibilityLabel: String
    ) {
        self.visibleValue = visibleValue
        self.help = help
        self.accessibilityLabel = accessibilityLabel
    }
}

public enum DashboardScanControlState: Equatable, Sendable {
    case ready
    case scanning
    case failed
}

public struct DashboardScanControlPresentation: Equatable, Sendable {
    public let iconName: String?
    public let toolTip: String
    public let accessibilityLabel: String

    public init(
        iconName: String?,
        toolTip: String,
        accessibilityLabel: String
    ) {
        self.iconName = iconName
        self.toolTip = toolTip
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct DashboardPresentationModel: Sendable {
    public static let itemsRefreshHelp = "Refresh items"
    public static let scanTrackingHelp =
        "Unchecked registered tools are disabled, not deleted."

    private let localeIdentifier: String
    private let timeZoneIdentifier: String

    public init(locale: Locale = .current, timeZone: TimeZone = .current) {
        localeIdentifier = locale.identifier
        timeZoneIdentifier = timeZone.identifier
    }

    public func overviewMetrics(
        for summary: DashboardSummary
    ) -> [DashboardMetricPresentation] {
        let approvalNoun = summary.approvalsWaiting == 1 ? "item" : "items"
        return [
            DashboardMetricPresentation(
                iconName: "arrow.down.circle",
                visibleValue: String(summary.pendingUpdates),
                help: "Updates: \(summary.pendingUpdates) available.",
                accessibilityLabel: "Updates",
                accessibilityValue: "\(summary.pendingUpdates) available"
            ),
            DashboardMetricPresentation(
                iconName: "hourglass",
                visibleValue: String(summary.approvalsWaiting),
                help: "Awaiting Approval: \(summary.approvalsWaiting) \(approvalNoun).",
                accessibilityLabel: "Awaiting Approval",
                accessibilityValue: "\(summary.approvalsWaiting) \(approvalNoun)"
            ),
            dateMetric(
                title: "Last Checked",
                iconName: "magnifyingglass",
                date: summary.lastChecked
            ),
            dateMetric(
                title: "Last Updated",
                iconName: "clock",
                date: summary.lastUpdated
            ),
        ]
    }

    public func scanCounts(
        discovered: Int,
        enabled: Int,
        disabled: Int
    ) -> [DashboardScanCountPresentation] {
        [
            scanCount(
                title: "Discovered",
                value: discovered,
                meaning: "Tools found by the most recent manual scan."
            ),
            scanCount(
                title: "Enabled",
                value: enabled,
                meaning: "Discovered registered tools that are enabled."
            ),
            scanCount(
                title: "Disabled",
                value: disabled,
                meaning: Self.scanTrackingHelp
            ),
        ]
    }

    public func scanControl(
        state: DashboardScanControlState
    ) -> DashboardScanControlPresentation {
        switch state {
        case .ready:
            return DashboardScanControlPresentation(
                iconName: nil,
                toolTip: "Scan for installed tools",
                accessibilityLabel: "Scan for installed tools"
            )
        case .scanning:
            return DashboardScanControlPresentation(
                iconName: nil,
                toolTip: "Scanning for installed tools",
                accessibilityLabel: "Scanning for installed tools"
            )
        case .failed:
            return DashboardScanControlPresentation(
                iconName: "exclamationmark.triangle.fill",
                toolTip: "Scan failed. Try again.",
                accessibilityLabel: "Scan failed. Scan again"
            )
        }
    }

    public func scanRowActionLabel(
        candidateName: String,
        isChecked: Bool
    ) -> String {
        let action = isChecked ? "Disable" : "Enable"
        return "\(action) \(SecretRedactor.redact(candidateName))"
    }

    public func scanMutationFailureAnnouncement(
        candidateName: String,
        restoredState: ScanTrackingState,
        message: String
    ) -> String {
        let restoredLabel: String
        switch restoredState {
        case .untracked:
            restoredLabel = "New"
        case .enabled:
            restoredLabel = "Enabled"
        case .disabled:
            restoredLabel = "Disabled"
        case .unavailable:
            restoredLabel = "Unavailable"
        }
        return "Update failed for \(SecretRedactor.redact(candidateName)). "
            + "Restored \(restoredLabel). \(SecretRedactor.redact(message))"
    }

    private func dateMetric(
        title: String,
        iconName: String,
        date: Date?
    ) -> DashboardMetricPresentation {
        guard let date else {
            return DashboardMetricPresentation(
                iconName: iconName,
                visibleValue: "–",
                help: "\(title): Not available.",
                accessibilityLabel: title,
                accessibilityValue: "Not available"
            )
        }

        let fullValue = fullDateFormatter.string(from: date)
        return DashboardMetricPresentation(
            iconName: iconName,
            visibleValue: compactDateFormatter.string(from: date),
            help: "\(title): \(fullValue).",
            accessibilityLabel: title,
            accessibilityValue: fullValue
        )
    }

    private func scanCount(
        title: String,
        value: Int,
        meaning: String
    ) -> DashboardScanCountPresentation {
        DashboardScanCountPresentation(
            visibleValue: String(value),
            help: "\(title): \(value). \(meaning)",
            accessibilityLabel: title
        )
    }

    private var compactDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("MMMdhm")
        return formatter
    }

    private var fullDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
        formatter.dateStyle = .full
        formatter.timeStyle = .long
        return formatter
    }
}
