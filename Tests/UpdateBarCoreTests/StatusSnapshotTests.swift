import XCTest
import UpdateBarCore
import UpdateBarTestSupport

final class StatusSnapshotTests: XCTestCase {
    func testBuildsMenuBarStatusContractFromManifestAndState() throws {
        let manifest = try loadManifest()
        let now = Date(timeIntervalSince1970: 1_812_499_200)
        let state = State(
            schemaVersion: 1,
            generatedAt: now,
            items: [
                "claude-code": ItemState(
                    current: "1.4.2",
                    latest: "1.5.0",
                    status: .outdated,
                    lastChecked: now,
                    error: nil,
                    backoffUntil: nil
                )
            ]
        )

        let snapshot = StatusSnapshot.from(manifest: manifest, state: state, now: now)

        XCTAssertEqual(snapshot.summary.total, 1)
        XCTAssertEqual(snapshot.summary.outdated, 1)
        XCTAssertEqual(snapshot.summary.errors, 0)
        XCTAssertEqual(snapshot.summary.untrusted, 0)
        XCTAssertEqual(snapshot.summary.pinned, 0)
        XCTAssertEqual(snapshot.items.first?.id, "claude-code")
        XCTAssertEqual(snapshot.items.first?.status, .outdated)
        XCTAssertEqual(snapshot.items.first?.pinned, false)
    }

    func testStatusSummaryCountsAttentionStates() throws {
        var outdated = try loadManifest().items[0]
        outdated.id = "outdated"
        outdated.name = "Outdated"

        var untrusted = outdated
        untrusted.id = "untrusted"
        untrusted.name = "Untrusted"
        untrusted.trust.level = .untrusted

        var pinned = outdated
        pinned.id = "pinned"
        pinned.name = "Pinned"
        pinned.pin = "1.4.2"

        var disabled = outdated
        disabled.id = "disabled"
        disabled.name = "Disabled"
        disabled.enabled = false

        var checking = outdated
        checking.id = "checking"
        checking.name = "Checking"

        var differs = outdated
        differs.id = "differs"
        differs.name = "Differs"

        let now = Date(timeIntervalSince1970: 1_812_499_200)
        let manifest = Manifest(
            schemaVersion: 1,
            items: [outdated, untrusted, pinned, disabled, checking, differs],
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        )
        let state = State(
            schemaVersion: 1,
            generatedAt: now,
            items: [
                "outdated": itemState(status: .outdated, now: now),
                "untrusted": itemState(status: .outdated, now: now),
                "pinned": itemState(status: .outdated, now: now),
                "disabled": itemState(status: .outdated, now: now),
                "checking": itemState(status: .checking, now: now),
                "differs": itemState(status: .differs, now: now)
            ]
        )

        let snapshot = StatusSnapshot.from(manifest: manifest, state: state, now: now)

        XCTAssertEqual(snapshot.summary.total, 6)
        XCTAssertEqual(snapshot.summary.outdated, 1)
        XCTAssertEqual(snapshot.summary.errors, 0)
        XCTAssertEqual(snapshot.summary.untrusted, 1)
        XCTAssertEqual(snapshot.summary.pinned, 1)
        XCTAssertEqual(snapshot.summary.disabled, 1)
        XCTAssertEqual(snapshot.summary.checking, 1)
        XCTAssertEqual(snapshot.summary.differs, 1)
    }

    func testStatusPriorityUsesOverridesBeforeVersionStatus() throws {
        var manifest = try loadManifest()
        let now = Date(timeIntervalSince1970: 1_812_499_200)
        let base = ItemState(
            current: "1.4.2",
            latest: "1.5.0",
            status: .outdated,
            lastChecked: now,
            error: nil,
            backoffUntil: nil
        )

        manifest.items[0].enabled = false
        XCTAssertEqual(status(for: manifest, itemState: base), .disabled)

        manifest.items[0].enabled = true
        manifest.items[0].pin = "1.4.2"
        XCTAssertEqual(status(for: manifest, itemState: base), .pinned)

        manifest.items[0].pin = nil
        manifest.items[0].trust.level = .untrusted
        XCTAssertEqual(status(for: manifest, itemState: base), .untrusted)

        manifest.items[0].trust.level = .trusted
        var errored = base
        errored.status = .error
        errored.error = "command failed"
        XCTAssertEqual(status(for: manifest, itemState: errored), .error)

        var checking = base
        checking.status = .checking
        XCTAssertEqual(status(for: manifest, itemState: checking), .checking)
    }

    private func status(for manifest: Manifest, itemState: ItemState) -> ItemStatus {
        let state = State(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_812_499_200),
            items: ["claude-code": itemState]
        )
        return StatusSnapshot.from(
            manifest: manifest,
            state: state,
            now: Date(timeIntervalSince1970: 1_812_499_200)
        ).items[0].status
    }

    private func itemState(status: ItemStatus, now: Date) -> ItemState {
        ItemState(
            current: "1.4.2",
            latest: "1.5.0",
            status: status,
            lastChecked: now,
            error: nil,
            backoffUntil: nil
        )
    }

    private func loadManifest() throws -> Manifest {
        let data = try Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json"))
        return try JSONDecoder.updateBar.decode(Manifest.self, from: data)
    }
}
