import UpdateBarCore
import UpdateBarMenuBar
import XCTest

final class ScanListModelTests: XCTestCase {
    func testRegisteredDisabledStatusTakesPrecedenceOverFullCandidate() {
        let candidate = candidate(id: "brew.jq", capability: .full, recipe: recipe())

        let rows = ScanListModel().rows(
            from: ScanReport(candidates: [candidate], errors: []),
            registeredStatuses: [candidate.id: .disabled]
        )

        XCTAssertEqual(rows.map(\.trackingState), [.disabled])
    }

    func testRegisteredAnyNonDisabledStatusTakesPrecedenceAsEnabled() {
        let candidates = [
            candidate(id: "known.ok", capability: .checkOnly, recipe: nil),
            candidate(id: "known.untrusted", capability: .metadataOnly, recipe: nil),
        ]
        let statuses: [String: ItemStatus] = [
            "known.ok": .ok,
            "known.untrusted": .untrusted,
        ]

        let rows = ScanListModel().rows(
            from: ScanReport(candidates: candidates, errors: []),
            registeredStatuses: statuses
        )

        XCTAssertEqual(rows.map(\.trackingState), [.enabled, .enabled])
    }

    func testUnregisteredFullCandidateWithRecipeIsUntracked() {
        let candidate = candidate(id: "brew.jq", capability: .full, recipe: recipe())

        let rows = ScanListModel().rows(
            from: ScanReport(candidates: [candidate], errors: []),
            registeredStatuses: [:]
        )

        XCTAssertEqual(rows.map(\.trackingState), [.untracked])
    }

    func testUnregisteredCheckOnlyCandidateIsUnavailableWithCapabilityReason() {
        let candidate = candidate(id: "known.claude", capability: .checkOnly, recipe: nil)

        let rows = ScanListModel().rows(
            from: ScanReport(candidates: [candidate], errors: []),
            registeredStatuses: [:]
        )

        XCTAssertEqual(rows.map(\.trackingState), [.unavailable("check-only")])
    }

    func testRowComputedPropertiesReflectEveryTrackingState() {
        let candidate = candidate(id: "brew.jq", capability: .full, recipe: recipe())
        let unavailable = ScanListRow(
            candidate: candidate,
            trackingState: .unavailable("check-only")
        )
        let untracked = ScanListRow(candidate: candidate, trackingState: .untracked)
        let enabled = ScanListRow(candidate: candidate, trackingState: .enabled)
        let disabled = ScanListRow(candidate: candidate, trackingState: .disabled)

        XCTAssertEqual(untracked.stateLabel, "new")
        XCTAssertFalse(untracked.isChecked)
        XCTAssertTrue(untracked.canToggle)

        XCTAssertEqual(enabled.stateLabel, "enabled")
        XCTAssertTrue(enabled.isChecked)
        XCTAssertTrue(enabled.canToggle)

        XCTAssertEqual(disabled.stateLabel, "disabled")
        XCTAssertFalse(disabled.isChecked)
        XCTAssertTrue(disabled.canToggle)

        XCTAssertEqual(unavailable.stateLabel, "check-only")
        XCTAssertFalse(unavailable.isChecked)
        XCTAssertFalse(unavailable.canToggle)
    }

    func testRowsPreserveReportCandidateOrder() {
        let candidates = [
            candidate(id: "third", capability: .unsupported, recipe: nil),
            candidate(id: "first", capability: .full, recipe: recipe()),
            candidate(id: "second", capability: .checkOnly, recipe: nil),
        ]

        let rows = ScanListModel().rows(
            from: ScanReport(candidates: candidates, errors: []),
            registeredStatuses: ["first": .ok]
        )

        XCTAssertEqual(rows.map { $0.candidate.id }, ["third", "first", "second"])
    }

    private func candidate(
        id: String,
        capability: ScanCapability,
        recipe: Recipe?
    ) -> ScanCandidate {
        ScanCandidate(
            id: id,
            name: id,
            detector: .known,
            category: "test",
            capability: capability,
            confidence: .high,
            installedVersion: nil,
            sourceRef: id,
            recipe: recipe
        )
    }

    private func recipe() -> Recipe {
        Recipe(
            id: "brew.jq",
            name: "jq",
            category: "shell-utility",
            path: nil,
            source: Source(kind: .brew, ref: "jq", branch: nil),
            versionScheme: .semver,
            check: .command("brew list --versions jq"),
            latest: LatestSpec(strategy: .cmd, cmd: "brew info jq", pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: "brew upgrade jq", cwd: nil),
            pin: nil,
            enabled: true,
            trust: Trust(level: .untrusted, approvedCommands: [:])
        )
    }
}
