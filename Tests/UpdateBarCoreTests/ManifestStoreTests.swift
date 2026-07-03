import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class ManifestStoreTests: XCTestCase {
    func testDecodesManifestObjectShape() throws {
        let data = try Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json"))
        let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.items.count, 1)
        XCTAssertEqual(manifest.provenance.createdBy, "updatebar")

        let item = try XCTUnwrap(manifest.item(id: "claude-code"))
        XCTAssertEqual(item.id, "claude-code")
        XCTAssertEqual(item.name, "Claude Code")
        XCTAssertEqual(item.category, "cli")
        XCTAssertEqual(item.source.kind, .npm)
        XCTAssertEqual(item.source.ref, "@anthropic-ai/claude-code")
        XCTAssertEqual(item.versionScheme, .semver)
        XCTAssertEqual(item.check, .command("claude --version"))
        XCTAssertEqual(item.latest.strategy, .npmRegistry)
        XCTAssertEqual(item.versionParse, .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"))
        XCTAssertEqual(item.update.cmd, "npm i -g @anthropic-ai/claude-code@latest")
        XCTAssertNil(item.pin)
        XCTAssertTrue(item.enabled)
        XCTAssertEqual(item.trust.level, .trusted)
    }

    func testDecodeIgnoresLegacyNotifyValue() throws {
        let notifyTrue = try JSONDecoder.updateBar.decode(
            Manifest.self,
            from: validManifestDataUpdatingFirstItem { $0["notify"] = true }
        )
        let notifyFalse = try JSONDecoder.updateBar.decode(
            Manifest.self,
            from: validManifestDataUpdatingFirstItem { $0["notify"] = false }
        )

        XCTAssertEqual(notifyTrue.items, notifyFalse.items)
    }

    func testDecodeRejectsUnsupportedCheckFileQuery() throws {
        let data = try validManifestDataUpdatingFirstItem {
            $0["check"] = [
                "file": "/tmp/version.json",
                "query": "$.version",
            ] as [String: Any]
        }

        XCTAssertThrowsError(try JSONDecoder.updateBar.decode(Manifest.self, from: data))
    }

    func testDecodeRejectsUnsupportedJQVersionParse() throws {
        let data = try validManifestDataUpdatingFirstItem {
            $0["version_parse"] = ["jq": ".version"]
        }

        XCTAssertThrowsError(try JSONDecoder.updateBar.decode(Manifest.self, from: data))
    }

    func testDecodeRejectsStoredElevatedTrustLevel() throws {
        let data = try validManifestDataUpdatingFirstItem {
            var trust = try XCTUnwrap($0["trust"] as? [String: Any])
            trust["level"] = "elevated"
            $0["trust"] = trust
        }

        XCTAssertThrowsError(try JSONDecoder.updateBar.decode(Manifest.self, from: data))
    }

    func testReplacingAndRemovingItems() throws {
        let data = try Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json"))
        let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)
        var item = try XCTUnwrap(manifest.item(id: "claude-code"))
        item.name = "Claude Code CLI"

        let replaced = manifest.replacing(item: item)
        XCTAssertEqual(replaced.item(id: "claude-code")?.name, "Claude Code CLI")

        let removed = replaced.removing(id: "claude-code")
        XCTAssertNil(removed.item(id: "claude-code"))
        XCTAssertTrue(removed.items.isEmpty)
    }

    func testRecipeCommandFingerprintsChangeWhenCommandChanges() throws {
        let data = try Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json"))
        let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)
        var item = try XCTUnwrap(manifest.item(id: "claude-code"))

        let original = item.commandFingerprints()
        item.update.cmd = "npm update -g @anthropic-ai/claude-code"
        let changed = item.commandFingerprints()

        XCTAssertNotEqual(original["update.cmd"], changed["update.cmd"])
        XCTAssertEqual(original["check.cmd"], changed["check.cmd"])
    }

    func testUpdateFingerprintChangesWhenSourceOrLatestInputChanges() throws {
        let data = try Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json"))
        let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)
        var item = try XCTUnwrap(manifest.item(id: "claude-code"))

        let original = item.commandFingerprints()
        item.source.ref = "@anthropic-ai/other-tool"
        let changedSource = item.commandFingerprints()
        item.source.ref = "@anthropic-ai/claude-code"
        item.latest.pattern = #"([0-9]+\.[0-9]+)"#
        let changedLatest = item.commandFingerprints()

        XCTAssertNotEqual(original["update.cmd"], changedSource["update.cmd"])
        XCTAssertNotEqual(original["update.cmd"], changedLatest["update.cmd"])
        XCTAssertEqual(original["check.cmd"], changedSource["check.cmd"])
    }

    func testUpdateFingerprintDoesNotCollideWhenCommandAndCWDContainSeparators() throws {
        let data = try Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json"))
        let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)
        var first = try XCTUnwrap(manifest.item(id: "claude-code"))
        var second = first

        first.update.cmd = "tool --flag=a|b"
        first.update.cwd = "c"
        second.update.cmd = "tool --flag=a"
        second.update.cwd = "b|c"

        XCTAssertNotEqual(
            first.commandFingerprints()["update.cmd"],
            second.commandFingerprints()["update.cmd"]
        )
    }

    func testManifestStoreInitializesEmptyManifestInUpdateBarHome() throws {
        let root = try temporaryDirectory()
        let store = ManifestStore(paths: AppPaths(homeDirectory: root))

        let manifest = try store.load()

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertTrue(manifest.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path))
    }

    func testLoadExistingOrEmptyDoesNotCreateMissingManifestFile() throws {
        let root = try temporaryDirectory()
        let store = ManifestStore(paths: AppPaths(homeDirectory: root))

        let manifest = try store.loadExistingOrEmpty(now: Date(timeIntervalSince1970: 1_812_499_200))

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertTrue(manifest.items.isEmpty)
        XCTAssertEqual(manifest.provenance.createdBy, "updatebar")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path))
    }

    func testLoadExistingOrEmptyDoesNotCreateMissingHomeDirectory() throws {
        let root = try temporaryDirectory().appendingPathComponent("missing-home")
        let store = ManifestStore(paths: AppPaths(homeDirectory: root))

        let manifest = try store.loadExistingOrEmpty(now: Date(timeIntervalSince1970: 1_812_499_200))

        XCTAssertTrue(manifest.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testLoadExistingOrEmptyRepairsExistingHomePermissions() throws {
        let root = try temporaryDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        let manifestURL = root.appendingPathComponent("manifest.json")
        try Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json")).write(to: manifestURL)
        let store = ManifestStore(paths: AppPaths(homeDirectory: root))

        _ = try store.loadExistingOrEmpty()

        let homeAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual((homeAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testManifestStoreWritesAndReadsAtomicallyWithPrivatePermissions() throws {
        let root = try temporaryDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        let store = ManifestStore(paths: AppPaths(homeDirectory: root))
        let data = try Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json"))
        let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)

        try store.save(manifest)
        let loaded = try store.load()

        XCTAssertEqual(loaded, manifest)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: root.appendingPathComponent("manifest.json").path
        )
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let homeAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual((homeAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testManifestStoreOverwritesExistingFile() throws {
        let root = try temporaryDirectory()
        let store = ManifestStore(paths: AppPaths(homeDirectory: root))
        let data = try Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json"))
        let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)
        var updated = manifest
        var item = try XCTUnwrap(updated.items.first)
        item.name = "Updated Tool"
        updated = updated.replacing(item: item)

        try store.save(manifest)
        try store.save(updated)

        XCTAssertEqual(try store.load(), updated)
    }

    func testManifestStoreProvidesCrossProcessLockFileForReadModifyWrite() throws {
        let root = try temporaryDirectory()
        let store = ManifestStore(paths: AppPaths(homeDirectory: root))
        let data = try Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json"))
        let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)

        try store.withExclusiveLock {
            try store.save(manifest)
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.lock").path)
        )
        XCTAssertEqual(try store.load(), manifest)
    }

    func testManifestStoreReportsCorruptManifest() throws {
        let root = try temporaryDirectory()
        let manifestURL = root.appendingPathComponent("manifest.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: manifestURL)
        let store = ManifestStore(paths: AppPaths(homeDirectory: root))

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertTrue(String(describing: error).contains("manifest.json"))
        }
    }

    func testManifestStoreReportsDecodingFailureWithoutSwiftInternals() throws {
        let root = try temporaryDirectory()
        let manifestURL = root.appendingPathComponent("manifest.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(
            """
            {
              "schema_version": 1,
              "provenance": {
                "created_by": "updatebar",
                "created_at": "2026-06-09T00:00:00Z",
                "updated_at": "2026-06-09T00:00:00Z"
              }
            }
            """.utf8
        ).write(to: manifestURL)
        let store = ManifestStore(paths: AppPaths(homeDirectory: root))

        XCTAssertThrowsError(try store.load()) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("manifest.json"))
            XCTAssertTrue(message.contains("missing required key items"))
            XCTAssertFalse(message.contains("CodingKeys"))
            XCTAssertFalse(message.contains("keyNotFound"))
        }
    }

    func testAppPathsUsesExplicitHomeAndDoesNotEscapeIt() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)

        XCTAssertEqual(paths.manifestFile.deletingLastPathComponent().path, root.path)
        XCTAssertEqual(paths.stateFile.deletingLastPathComponent().path, root.path)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func validManifestDataUpdatingFirstItem(_ update: (inout [String: Any]) throws -> Void) throws -> Data {
        let data = try Data(contentsOf: TestFixtures.fixtureURL("manifests", "valid-basic.json"))
        let object = try JSONSerialization.jsonObject(with: data)
        var manifest = try XCTUnwrap(object as? [String: Any])
        var items = try XCTUnwrap(manifest["items"] as? [[String: Any]])
        var item = try XCTUnwrap(items.first)
        try update(&item)
        items[0] = item
        manifest["items"] = items
        return try JSONSerialization.data(withJSONObject: manifest)
    }
}
