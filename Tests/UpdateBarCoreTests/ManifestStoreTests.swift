import XCTest
import UpdateBarCore
import UpdateBarTestSupport

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
        XCTAssertTrue(item.notify)
        XCTAssertEqual(item.trust.level, .trusted)
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

    func testManifestStoreInitializesEmptyManifestInUpdateBarHome() throws {
        let root = try temporaryDirectory()
        let store = ManifestStore(paths: AppPaths(homeDirectory: root))

        let manifest = try store.load()

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertTrue(manifest.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path))
    }

    func testManifestStoreWritesAndReadsAtomicallyWithPrivatePermissions() throws {
        let root = try temporaryDirectory()
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
}
