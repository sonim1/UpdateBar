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
        try StateStore(paths: paths).save(
            State(
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

    func testSnapshotWithoutRefreshDoesNotCreateMissingStateFile() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        try ManifestStore(paths: paths).save(manifest(items: [try recipe(id: "tool")]))

        let snapshot = try statusService(paths: paths).snapshot()

        XCTAssertEqual(snapshot.summary.total, 1)
        XCTAssertEqual(snapshot.items.first?.status, .checking)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
    }

    func testSnapshotWithoutRefreshDoesNotCreateMissingManifestOrStateFiles() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)

        let snapshot = try statusService(paths: paths).snapshot()

        XCTAssertEqual(snapshot.summary.total, 0)
        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.manifestFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
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
        untrusted.trust.approvedCommands = [:]
        try ManifestStore(paths: paths).save(
            manifest(items: [
                stale,
                fresh,
                pinned,
                disabled,
                untrusted,
            ]))
        var config = Config.default
        config.refresh.interval = Duration(hours: 1)
        try ConfigStore(paths: paths).save(config)
        let staleChecked = now.addingTimeInterval(-7_200)
        let freshChecked = now.addingTimeInterval(-60)
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1,
                generatedAt: staleChecked,
                items: [
                    "stale": itemState(lastChecked: staleChecked, error: "old error"),
                    "fresh": itemState(lastChecked: freshChecked),
                    "pinned": itemState(lastChecked: staleChecked),
                    "disabled": itemState(lastChecked: staleChecked),
                    "untrusted": itemState(lastChecked: staleChecked),
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

    func testRefreshDoesNotMarkStaleItemCheckingWhenCheckCommandIsUnapproved() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        var item = try recipe(id: "partial")
        item.trust.approvedCommands.removeValue(forKey: "check.cmd")
        try ManifestStore(paths: paths).save(manifest(items: [item]))
        var config = Config.default
        config.refresh.interval = Duration(hours: 1)
        try ConfigStore(paths: paths).save(config)
        let staleChecked = now.addingTimeInterval(-7_200)
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1,
                generatedAt: staleChecked,
                items: ["partial": itemState(lastChecked: staleChecked)]
            ))

        let snapshot = try statusService(paths: paths).snapshot(refresh: true)
        let persisted = try StateStore(paths: paths).load()

        XCTAssertEqual(snapshot.items.first?.status, .untrusted)
        XCTAssertEqual(persisted.items["partial"]?.status, .ok)
    }

    func testRefreshTreatsFutureAndExpiredTimestampsAsStale() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(homeDirectory: root)
        var config = Config.default
        config.refresh.interval = Duration(hours: 1)
        let ttl = TimeInterval(config.refresh.interval.seconds)
        let cases: [(id: String, age: TimeInterval, expected: ItemStatus)] = [
            ("future", -60, .checking),
            ("now", 0, .ok),
            ("fresh", ttl - 1, .ok),
            ("boundary", ttl, .checking),
            ("expired", ttl + 1, .checking),
        ]
        try ManifestStore(paths: paths).save(
            manifest(items: try cases.map { try recipe(id: $0.id) }))
        try ConfigStore(paths: paths).save(config)
        try StateStore(paths: paths).save(
            State(
                schemaVersion: 1, generatedAt: now,
                items: Dictionary(
                    uniqueKeysWithValues: cases.map {
                        ($0.id, itemState(lastChecked: now.addingTimeInterval(-$0.age)))
                    })
            ))

        let snapshot = try statusService(paths: paths).snapshot(refresh: true)

        for entry in cases {
            XCTAssertEqual(
                snapshot.items.first { $0.id == entry.id }?.status, entry.expected, entry.id)
        }
    }

    func testSnapshotWithApprovalsIncludesAllItemsWithoutCreatingStateOrConfig() throws {
        for count in [0, 1, 100] {
            let root = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let paths = AppPaths(homeDirectory: root)
            let recipes = try (0..<count).map { try recipe(id: "tool-\($0)") }
            try ManifestStore(paths: paths).save(manifest(items: recipes))

            let snapshot = try statusService(paths: paths).snapshotWithApprovals()

            XCTAssertEqual(snapshot.status.summary.total, count)
            XCTAssertEqual(Set(snapshot.approvalsByItemID.keys), Set(recipes.map(\.id)))
            for rows in snapshot.approvalsByItemID.values {
                XCTAssertEqual(rows.map(\.field), ["check.cmd", "update.cmd"])
                XCTAssertTrue(rows.allSatisfy(\.approved))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: paths.configFile.path))
        }
    }

    func testSnapshotWithApprovalsReflectsCommandEditOnNextRead() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(homeDirectory: root)
        var item = try recipe(id: "tool")
        let store = ManifestStore(paths: paths)
        try store.save(manifest(items: [item]))
        let first = try statusService(paths: paths).snapshotWithApprovals()

        item.update.cwd = "/tmp"
        try store.save(manifest(items: [item]))
        let second = try statusService(paths: paths).snapshotWithApprovals()
        let firstApproval = try XCTUnwrap(
            first.approvalsByItemID["tool"]?.first { $0.field == "update.cmd" })
        let secondApproval = try XCTUnwrap(
            second.approvalsByItemID["tool"]?.first { $0.field == "update.cmd" })

        XCTAssertTrue(firstApproval.approved)
        XCTAssertFalse(secondApproval.approved)
        XCTAssertNotEqual(firstApproval.fingerprint, secondApproval.fingerprint)
        XCTAssertNil(firstApproval.cwd)
        XCTAssertEqual(secondApproval.cwd, "/tmp")
        XCTAssertEqual(second.status.items.first?.status, .untrusted)
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
        var manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)
        for index in manifest.items.indices {
            TestApprovals.approveAllCommands(in: &manifest.items[index])
        }
        return manifest
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
        TestApprovals.approveAllCommands(in: &item)
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
