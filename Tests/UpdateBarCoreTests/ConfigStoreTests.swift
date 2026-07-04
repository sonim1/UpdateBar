import UpdateBarCore
import XCTest

final class ConfigStoreTests: XCTestCase {
    func testDefaultConfigMatchesV1Decisions() {
        let config = Config.default

        XCTAssertEqual(config.refresh.interval, Duration(hours: 6))
        XCTAssertTrue(config.security.requireHTTPSSource)
        XCTAssertNil(config.get("notify.enabled"))
    }

    func testConfigStoreCreatesDefaultConfigFile() throws {
        let root = try temporaryDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        let store = ConfigStore(paths: AppPaths(homeDirectory: root))

        let config = try store.load()

        XCTAssertEqual(config, .default)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("config.toml").path))
        let configAttributes = try FileManager.default.attributesOfItem(
            atPath: root.appendingPathComponent("config.toml").path
        )
        XCTAssertEqual((configAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let homeAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual((homeAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testReadsAndWritesKnownConfigKeys() throws {
        let root = try temporaryDirectory()
        let store = ConfigStore(paths: AppPaths(homeDirectory: root))
        var config = Config.default
        config.refresh.interval = Duration(minutes: 30)
        config.security.requireHTTPSSource = false

        try store.save(config)
        let loaded = try store.load()

        XCTAssertEqual(loaded.refresh.interval, Duration(minutes: 30))
        XCTAssertFalse(loaded.security.requireHTTPSSource)
    }

    func testLoadExistingOrDefaultRepairsExistingHomePermissions() throws {
        let root = try temporaryDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try Data(
            """
            [refresh]
            interval = "30m"

            [security]
            require_https_source = true
            """.utf8
        ).write(to: root.appendingPathComponent("config.toml"))
        let store = ConfigStore(paths: AppPaths(homeDirectory: root))

        _ = try store.loadExistingOrDefault()

        let homeAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual((homeAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testSetKnownKeyRejectsUnknownKey() throws {
        var config = Config.default
        try config.set("refresh.interval", value: "30m")

        XCTAssertEqual(config.get("refresh.interval"), "30m")
        XCTAssertNil(config.get("refresh.concurrency"))
        XCTAssertNil(config.get("provider.default"))
        XCTAssertNil(config.get("notify.enabled"))
        XCTAssertNil(config.get("security.allow_import_exec"))
        XCTAssertThrowsError(try config.set("provider.default", value: "openrouter"))
        XCTAssertThrowsError(try config.set("refresh.concurrency", value: "2"))
        XCTAssertThrowsError(try config.set("notify.enabled", value: "false"))
        XCTAssertThrowsError(try config.set("security.allow_import_exec", value: "true"))
        XCTAssertThrowsError(try config.set("unknown.key", value: "x"))
    }

    func testRenderedConfigOmitsRemovedConfigKeys() throws {
        let root = try temporaryDirectory()
        let store = ConfigStore(paths: AppPaths(homeDirectory: root))

        let text = store.renderForDisplay(.default)

        XCTAssertFalse(text.contains("allow_import_exec"))
        XCTAssertFalse(text.contains("concurrency"))
        XCTAssertFalse(text.contains("notify"))
        XCTAssertTrue(text.contains("interval"))
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
        XCTAssertNil(config.get("refresh.concurrency"))
        XCTAssertNil(config.get("provider.default"))
        XCTAssertNil(config.get("notify.enabled"))
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

        XCTAssertThrowsError(try ConfigStore(paths: AppPaths(homeDirectory: root)).load()) {
            error in
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
            [security]
            require_https_source = maybe
            """.utf8
        ).write(to: configFile)

        XCTAssertThrowsError(try ConfigStore(paths: AppPaths(homeDirectory: root)).load()) {
            error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("line 2"))
            XCTAssertTrue(message.contains("security.require_https_source: invalid value maybe"))
        }
    }

    func testInvalidRefreshIntervalReportsConfigKey() throws {
        let root = try temporaryDirectory()
        let configFile = root.appendingPathComponent("config.toml")
        try Data(
            """
            [refresh]
            interval = "never"
            """.utf8
        ).write(to: configFile)

        XCTAssertThrowsError(try ConfigStore(paths: AppPaths(homeDirectory: root)).load()) {
            error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("line 2"))
            XCTAssertTrue(message.contains("refresh.interval: invalid value never"))
            XCTAssertFalse(message.contains("duration: invalid value never"))
        }
    }

    func testInvalidConfigLineRedactsSecretLikeContent() throws {
        let root = try temporaryDirectory()
        let configFile = root.appendingPathComponent("config.toml")
        let secret = "sk-or-v1-secret-value"
        try Data(
            """
            [refresh]
            \(secret)
            """.utf8
        ).write(to: configFile)

        XCTAssertThrowsError(try ConfigStore(paths: AppPaths(homeDirectory: root)).load()) {
            error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("line 2"))
            XCTAssertTrue(message.contains("invalid line [REDACTED]"))
            XCTAssertFalse(message.contains(secret))
        }
    }

    func testInvalidConfigValueRedactsSecretLikeContent() throws {
        let root = try temporaryDirectory()
        let configFile = root.appendingPathComponent("config.toml")
        let secret = "sk-or-v1-secret-value"
        try Data(
            """
            [security]
            require_https_source = \(secret)
            """.utf8
        ).write(to: configFile)

        XCTAssertThrowsError(try ConfigStore(paths: AppPaths(homeDirectory: root)).load()) {
            error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("line 2"))
            XCTAssertTrue(
                message.contains("security.require_https_source: invalid value [REDACTED]"))
            XCTAssertFalse(message.contains(secret))
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
