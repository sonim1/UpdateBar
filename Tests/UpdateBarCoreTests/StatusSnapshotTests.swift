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

    func testUnapprovedCommandFingerprintOverridesStoredOutdatedState() throws {
        let manifest = try loadManifest(approved: false)
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

        XCTAssertEqual(snapshot.summary.outdated, 0)
        XCTAssertEqual(snapshot.summary.untrusted, 1)
        XCTAssertEqual(snapshot.items.first?.status, .untrusted)
    }

    func testStatusSnapshotRedactsStoredErrorSecrets() throws {
        let manifest = try loadManifest()
        let now = Date(timeIntervalSince1970: 1_812_499_200)
        let secret = "sk-or-v1-secret-value"
        let state = State(
            schemaVersion: 1,
            generatedAt: now,
            items: [
                "claude-code": ItemState(
                    current: "1.4.2",
                    latest: nil,
                    status: .error,
                    lastChecked: now,
                    error: "failed with OPENROUTER_API_KEY=\(secret)",
                    backoffUntil: nil
                )
            ]
        )

        let snapshot = StatusSnapshot.from(manifest: manifest, state: state, now: now)

        XCTAssertEqual(snapshot.items.first?.status, .error)
        XCTAssertTrue(snapshot.items.first?.error?.contains("[REDACTED]") ?? false)
        XCTAssertFalse(snapshot.items.first?.error?.contains(secret) ?? true)
        XCTAssertFalse(snapshot.items.first?.error?.contains("OPENROUTER_API_KEY=") ?? true)
    }

    func testStatusSnapshotRedactsStoredVersionSecrets() throws {
        let manifest = try loadManifest()
        let now = Date(timeIntervalSince1970: 1_812_499_200)
        let secret = "sk-or-v1-status-secret-value"
        let state = State(
            schemaVersion: 1,
            generatedAt: now,
            items: [
                "claude-code": ItemState(
                    current: secret,
                    latest: secret,
                    status: .ok,
                    lastChecked: now,
                    error: nil,
                    backoffUntil: nil
                )
            ]
        )

        let snapshot = StatusSnapshot.from(manifest: manifest, state: state, now: now)

        XCTAssertEqual(snapshot.items.first?.current, "[REDACTED]")
        XCTAssertEqual(snapshot.items.first?.latest, "[REDACTED]")
    }

    func testStatusSummaryCountsAttentionStates() throws {
        let outdated = try recipe(id: "outdated", name: "Outdated")

        var untrusted = outdated
        untrusted.id = "untrusted"
        untrusted.name = "Untrusted"
        untrusted.trust.level = .untrusted

        var pinned = try recipe(id: "pinned", name: "Pinned")
        pinned.pin = "1.4.2"

        var disabled = try recipe(id: "disabled", name: "Disabled")
        disabled.enabled = false

        let checking = try recipe(id: "checking", name: "Checking")

        let differs = try recipe(id: "differs", name: "Differs")

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

    private func recipe(id: String, name: String) throws -> Recipe {
        var item = try loadManifest().items[0]
        item.id = id
        item.name = name
        TrustPolicy.approveAllCommands(in: &item)
        return item
    }

    private func loadManifest(approved: Bool = true) throws -> Manifest {
        let data = try Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json"))
        var manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)
        if approved {
            for index in manifest.items.indices {
                TrustPolicy.approveAllCommands(in: &manifest.items[index])
            }
        }
        return manifest
    }
}
