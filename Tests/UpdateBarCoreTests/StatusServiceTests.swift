import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class StatusServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_812_499_200)

    func testSnapshotLoadsManifestAndState() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let manifest = try loadManifest()
        try ManifestStore(paths: paths).save(manifest)
        try StateStore(paths: paths).save(State(
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
        ))

        let snapshot = try statusService(paths: paths).snapshot()

        XCTAssertEqual(snapshot.generatedAt, now)
        XCTAssertEqual(snapshot.summary.outdated, 1)
        XCTAssertEqual(snapshot.items.map(\.id), ["claude-code"])
        XCTAssertEqual(snapshot.items.first?.status, .outdated)
    }

    func testRefreshMarksOnlyStaleTrustedEnabledUnpinnedItemsChecking() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let stale = try recipe(id: "stale")
        let fresh = try recipe(id: "fresh")
        var pinned = try recipe(id: "pinned")
        pinned.pin = "1.0.0"
        var disabled = try recipe(id: "disabled")
        disabled.enabled = false
        var untrusted = try recipe(id: "untrusted")
        untrusted.trust.level = .untrusted
        try ManifestStore(paths: paths).save(manifest(items: [
            stale,
            fresh,
            pinned,
            disabled,
            untrusted
        ]))
        var config = Config.default
        config.refresh.interval = Duration(hours: 1)
        try ConfigStore(paths: paths).save(config)
        let staleChecked = now.addingTimeInterval(-7_200)
        let freshChecked = now.addingTimeInterval(-60)
        try StateStore(paths: paths).save(State(
            schemaVersion: 1,
            generatedAt: staleChecked,
            items: [
                "stale": itemState(lastChecked: staleChecked, error: "old error"),
                "fresh": itemState(lastChecked: freshChecked),
                "pinned": itemState(lastChecked: staleChecked),
                "disabled": itemState(lastChecked: staleChecked),
                "untrusted": itemState(lastChecked: staleChecked)
            ]
        ))

        let snapshot = try statusService(paths: paths).snapshot(refresh: true)
        let persisted = try StateStore(paths: paths).load()

        XCTAssertEqual(snapshot.items.first { $0.id == "stale" }?.status, .checking)
        XCTAssertEqual(snapshot.items.first { $0.id == "fresh" }?.status, .ok)
        XCTAssertEqual(snapshot.items.first { $0.id == "pinned" }?.status, .pinned)
        XCTAssertEqual(snapshot.items.first { $0.id == "disabled" }?.status, .disabled)
        XCTAssertEqual(snapshot.items.first { $0.id == "untrusted" }?.status, .untrusted)
        XCTAssertEqual(persisted.generatedAt, now)
        XCTAssertEqual(persisted.items["stale"]?.status, .checking)
        XCTAssertEqual(persisted.items["stale"]?.current, "1.0.0")
        XCTAssertEqual(persisted.items["stale"]?.latest, "1.0.0")
        XCTAssertNil(persisted.items["stale"]?.error)
        XCTAssertEqual(persisted.items["fresh"]?.status, .ok)
    }

    private func statusService(paths: AppPaths) -> StatusService {
        StatusService(
            manifestStore: ManifestStore(paths: paths),
            stateStore: StateStore(paths: paths),
            configStore: ConfigStore(paths: paths),
            now: { self.now }
        )
    }

    private func loadManifest() throws -> Manifest {
        let data = try Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json"))
        return try JSONDecoder.updateBar.decode(Manifest.self, from: data)
    }

    private func manifest(items: [Recipe]) -> Manifest {
        Manifest(
            schemaVersion: 1,
            items: items,
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)
        )
    }

    private func recipe(id: String) throws -> Recipe {
        var item = try XCTUnwrap(loadManifest().items.first)
        item.id = id
        item.name = id
        return item
    }

    private func itemState(lastChecked: Date, error: String? = nil) -> ItemState {
        ItemState(
            current: "1.0.0",
            latest: "1.0.0",
            status: .ok,
            lastChecked: lastChecked,
            error: error,
            backoffUntil: nil
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-status-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
