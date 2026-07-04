import Foundation
import UpdateBarCore
import XCTest

final class ConfigCommandTests: XCTestCase {
    func testConfigGetDoesNotCreateDefaultConfigFile() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-config-tests")
        let paths = AppPaths(homeDirectory: home)

        let result = try CLIProcess.run(
            ["config", "get", "security.require_https_source"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "true")
        XCTAssertEqual(result.stderr, "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.configFile.path))
    }

    func testConfigSetSupportsJSONOutput() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-config-tests")

        let result = try CLIProcess.run(
            ["config", "set", "security.require_https_source", "false", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains(#""ok":true"#))
        XCTAssertTrue(result.stdout.contains(#""key":"security.require_https_source""#))
        XCTAssertTrue(result.stdout.contains(#""value":"false""#))
    }

    func testConfigGetUnknownKeyJSONReturnsConfigError() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-config-tests")

        let result = try CLIProcess.run(["config", "get", "missing.key", "--json"], home: home)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(payload.code, "config_error")
        XCTAssertTrue(payload.errors.contains("missing.key: unknown config key"))
        XCTAssertTrue(
            payload.errors.contains {
                $0.contains("Known config keys: refresh.interval, security.require_https_source")
            })
    }

    func testConfigSetRejectsRemovedNotifyKey() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-config-tests")
        let knownKeys =
            "Known config keys: refresh.interval, "
            + "security.require_https_source"

        let result = try CLIProcess.run(
            ["config", "set", "notify.enabled", "false", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stdout.contains(#""ok":false"#))
        XCTAssertTrue(result.stdout.contains("unknown config key"))
        XCTAssertTrue(result.stdout.contains(knownKeys))
    }

    func testConfigGetUnknownKeyHumanListsKnownKeys() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-config-tests")
        let knownKeys =
            "Known config keys: refresh.interval, "
            + "security.require_https_source"

        let result = try CLIProcess.run(["config", "get", "missing.key"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("missing.key: unknown config key"))
        XCTAssertTrue(result.stderr.contains(knownKeys))
    }

    func testConfigSetInvalidIntervalJSONReportsConfigKey() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-config-tests")

        let result = try CLIProcess.run(
            ["config", "set", "refresh.interval", "never", "--json"], home: home)
        let payload = try JSONDecoder().decode(ErrorEnvelope.self, from: Data(result.stdout.utf8))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(payload.code, "config_error")
        XCTAssertTrue(payload.errors.contains("refresh.interval: invalid value never"))
        XCTAssertFalse(payload.errors.contains("duration: invalid value never"))
    }

    func testConfigSetInvalidKeyDoesNotCreateConfigFile() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-config-tests")
        let paths = AppPaths(homeDirectory: home)

        let result = try CLIProcess.run(
            ["config", "set", "missing.key", "value", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.configFile.path))
    }

    func testConfigJSONOmitsRemovedConfigKeys() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-config-tests")

        let result = try CLIProcess.run(["config", "get", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.stdout.contains("allow_import_exec"))
        XCTAssertFalse(result.stdout.contains("concurrency"))
        XCTAssertFalse(result.stdout.contains("notify"))
        XCTAssertTrue(result.stdout.contains("interval"))
        XCTAssertTrue(result.stdout.contains("require_https_source"))
    }

    private struct ErrorEnvelope: Decodable {
        var code: String
        var errors: [String]
    }
}
