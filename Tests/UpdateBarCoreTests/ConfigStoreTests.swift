import XCTest
import UpdateBarCore

final class ConfigStoreTests: XCTestCase {
    func testDefaultConfigMatchesV1Decisions() {
        let config = Config.default

        XCTAssertEqual(config.refresh.interval, Duration(hours: 6))
        XCTAssertEqual(config.refresh.concurrency, 8)
        XCTAssertTrue(config.security.requireHTTPSSource)
        XCTAssertTrue(config.notify.enabled)
    }

    func testConfigStoreCreatesDefaultConfigFile() throws {
        let root = try temporaryDirectory()
        let store = ConfigStore(paths: AppPaths(homeDirectory: root))

        let config = try store.load()

        XCTAssertEqual(config, .default)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("config.toml").path))
    }

    func testReadsAndWritesKnownConfigKeys() throws {
        let root = try temporaryDirectory()
        let store = ConfigStore(paths: AppPaths(homeDirectory: root))
        var config = Config.default
        config.refresh.interval = Duration(minutes: 30)
        config.refresh.concurrency = 4
        config.security.requireHTTPSSource = false

        try store.save(config)
        let loaded = try store.load()

        XCTAssertEqual(loaded.refresh.interval, Duration(minutes: 30))
        XCTAssertEqual(loaded.refresh.concurrency, 4)
        XCTAssertFalse(loaded.security.requireHTTPSSource)
    }

    func testSetKnownKeyRejectsUnknownKey() throws {
        var config = Config.default
        try config.set("refresh.interval", value: "30m")
        try config.set("refresh.concurrency", value: "2")

        XCTAssertEqual(config.get("refresh.interval"), "30m")
        XCTAssertEqual(config.get("refresh.concurrency"), "2")
        XCTAssertNil(config.get("provider.default"))
        XCTAssertNil(config.get("security.allow_import_exec"))
        XCTAssertThrowsError(try config.set("provider.default", value: "openrouter"))
        XCTAssertThrowsError(try config.set("security.allow_import_exec", value: "true"))
        XCTAssertThrowsError(try config.set("unknown.key", value: "x"))
    }

    func testRenderedConfigOmitsRemovedImportExecKey() throws {
        let root = try temporaryDirectory()
        let store = ConfigStore(paths: AppPaths(homeDirectory: root))

        let text = store.renderForDisplay(.default)

        XCTAssertFalse(text.contains("allow_import_exec"))
        XCTAssertTrue(text.contains("require_https_source"))
    }

    func testLoadsOldProviderConfigButDropsRemovedAIKeys() throws {
        let root = try temporaryDirectory()
        let configFile = root.appendingPathComponent("config.toml")
        try Data(
            """
            [provider]
            default = "openrouter"
            model = "google/gemini-3.5-flash"

            [refresh]
            interval = "30m"
            concurrency = 2

            [security]
            allow_import_exec = false
            require_https_source = true
            allow_plaintext_secret_file = true

            [notify]
            enabled = true
            """.utf8
        ).write(to: configFile)

        let config = try ConfigStore(paths: AppPaths(homeDirectory: root)).load()

        XCTAssertEqual(config.refresh.interval, Duration(minutes: 30))
        XCTAssertEqual(config.refresh.concurrency, 2)
        XCTAssertNil(config.get("provider.default"))
        XCTAssertNil(config.get("security.allow_plaintext_secret_file"))
    }

    func testInvalidConfigLineReportsLineNumber() throws {
        let root = try temporaryDirectory()
        let configFile = root.appendingPathComponent("config.toml")
        try Data(
            """
            [refresh]
            concurrency 2
            """.utf8
        ).write(to: configFile)

        XCTAssertThrowsError(try ConfigStore(paths: AppPaths(homeDirectory: root)).load()) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("line 2"))
            XCTAssertTrue(message.contains("invalid line concurrency 2"))
        }
    }

    func testInvalidConfigValueReportsLineNumber() throws {
        let root = try temporaryDirectory()
        let configFile = root.appendingPathComponent("config.toml")
        try Data(
            """
            [refresh]
            concurrency = no
            """.utf8
        ).write(to: configFile)

        XCTAssertThrowsError(try ConfigStore(paths: AppPaths(homeDirectory: root)).load()) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("line 2"))
            XCTAssertTrue(message.contains("refresh.concurrency: invalid value no"))
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
