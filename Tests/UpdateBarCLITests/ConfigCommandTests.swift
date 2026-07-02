import Foundation
import XCTest

final class ConfigCommandTests: XCTestCase {
    func testConfigSetSupportsJSONOutput() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-config-tests")

        let result = try CLIProcess.run(["config", "set", "notify.enabled", "false", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains(#""ok":true"#))
        XCTAssertTrue(result.stdout.contains(#""key":"notify.enabled""#))
        XCTAssertTrue(result.stdout.contains(#""value":"false""#))
    }

    func testConfigJSONOmitsRemovedImportExecKey() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-config-tests")

        let result = try CLIProcess.run(["config", "get", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.stdout.contains("allow_import_exec"))
        XCTAssertTrue(result.stdout.contains("require_https_source"))
    }
}
