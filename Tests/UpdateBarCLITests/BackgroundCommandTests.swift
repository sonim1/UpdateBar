import Foundation
import XCTest
import UpdateBarCore

#if os(macOS)
final class BackgroundCommandTests: XCTestCase {
    func testBackgroundInstallWritesCheckOnlyLaunchAgent() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-background-tests")
        let updatebarHome = home.appendingPathComponent("updatebar-home")
        try FileManager.default.createDirectory(at: updatebarHome, withIntermediateDirectories: true)
        let config = try CLIProcess.run(
            ["config", "set", "refresh.interval", "30m"],
            home: updatebarHome,
            environment: ["HOME": home.path]
        )
        XCTAssertEqual(config.exitCode, 0)

        let result = try CLIProcess.run(
            ["background", "install", "--yes", "--json"],
            home: updatebarHome,
            environment: ["HOME": home.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains(#""installed":true"#))

        let plistURL = home
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("com.updatebar.check.plist")
        let plist = try loadPlist(plistURL)
        XCTAssertEqual(plist["Label"] as? String, "com.updatebar.check")
        XCTAssertEqual(plist["StartInterval"] as? Int, 1800)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual((plist["EnvironmentVariables"] as? [String: String])?["UPDATEBAR_HOME"], updatebarHome.path)

        let arguments = try XCTUnwrap(plist["ProgramArguments"] as? [String])
        XCTAssertTrue(arguments[0].hasPrefix("/"))
        XCTAssertEqual(Array(arguments.dropFirst()), ["check", "--exit-zero-on-outdated"])
        XCTAssertFalse(arguments.contains("update"))
        XCTAssertFalse(arguments.contains("import"))
        XCTAssertFalse(arguments.contains("approve"))
        XCTAssertFalse(arguments.contains("remove"))
    }

    func testBackgroundInstallRequiresExplicitYes() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-background-tests")

        let result = try CLIProcess.run(
            ["background", "install", "--json"],
            home: home,
            environment: ["HOME": home.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stdout.contains(#""ok":false"#))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL(home: home).path))
    }

    func testBackgroundInstallDoesNotCreateDefaultConfigFile() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-background-tests")
        let updatebarHome = home.appendingPathComponent("updatebar-home")
        let paths = AppPaths(homeDirectory: updatebarHome)

        let result = try CLIProcess.run(
            ["background", "install", "--yes", "--json"],
            home: updatebarHome,
            environment: ["HOME": home.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains(#""installed":true"#))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.configFile.path))
    }

    func testBackgroundStatusAndUninstall() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-background-tests")

        let missing = try CLIProcess.run(["background", "status", "--json"], home: home, environment: ["HOME": home.path])
        XCTAssertEqual(missing.exitCode, 0)
        XCTAssertTrue(missing.stdout.contains(#""installed":false"#))

        _ = try CLIProcess.run(["background", "install", "--yes"], home: home, environment: ["HOME": home.path])
        let installed = try CLIProcess.run(["background", "status", "--json"], home: home, environment: ["HOME": home.path])
        XCTAssertEqual(installed.exitCode, 0)
        XCTAssertTrue(installed.stdout.contains(#""installed":true"#))

        let uninstall = try CLIProcess.run(["background", "uninstall", "--json"], home: home, environment: ["HOME": home.path])
        XCTAssertEqual(uninstall.exitCode, 0)
        XCTAssertTrue(uninstall.stdout.contains(#""removed":true"#))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL(home: home).path))
    }

    func testBackgroundActionJSONIncludesLaunchAgentLabel() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-background-tests")

        let install = try CLIProcess.run(["background", "install", "--yes", "--json"], home: home, environment: ["HOME": home.path])
        XCTAssertEqual(install.exitCode, 0)
        XCTAssertEqual(try jsonObject(in: install.stdout)["label"] as? String, "com.updatebar.check")

        let uninstall = try CLIProcess.run(["background", "uninstall", "--json"], home: home, environment: ["HOME": home.path])
        XCTAssertEqual(uninstall.exitCode, 0)
        XCTAssertEqual(try jsonObject(in: uninstall.stdout)["label"] as? String, "com.updatebar.check")
    }

    func testBackgroundStatusHumanOutputShowsLabelAndPath() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-background-tests")
        let plistPath = plistURL(home: home).path

        let missing = try CLIProcess.run(["background", "status"], home: home, environment: ["HOME": home.path])
        XCTAssertEqual(missing.exitCode, 0)
        XCTAssertEqual(missing.stderr, "")
        XCTAssertTrue(missing.stdout.contains("STATUS\tLABEL\tPATH"))
        XCTAssertTrue(missing.stdout.contains("not_installed\tcom.updatebar.check\t\(plistPath)"))

        _ = try CLIProcess.run(["background", "install", "--yes"], home: home, environment: ["HOME": home.path])

        let installed = try CLIProcess.run(["background", "status"], home: home, environment: ["HOME": home.path])
        XCTAssertEqual(installed.exitCode, 0)
        XCTAssertEqual(installed.stderr, "")
        XCTAssertTrue(installed.stdout.contains("STATUS\tLABEL\tPATH"))
        XCTAssertTrue(installed.stdout.contains("installed\tcom.updatebar.check\t\(plistPath)"))
    }

    func testBackgroundInstallAndUninstallHumanOutputShowsLabelAndPath() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-background-tests")
        let plistPath = plistURL(home: home).path

        let install = try CLIProcess.run(["background", "install", "--yes"], home: home, environment: ["HOME": home.path])
        XCTAssertEqual(install.exitCode, 0)
        XCTAssertEqual(install.stderr, "")
        XCTAssertTrue(install.stdout.contains("STATUS\tLABEL\tPATH"))
        XCTAssertTrue(install.stdout.contains("installed\tcom.updatebar.check\t\(plistPath)"))

        let uninstall = try CLIProcess.run(["background", "uninstall"], home: home, environment: ["HOME": home.path])
        XCTAssertEqual(uninstall.exitCode, 0)
        XCTAssertEqual(uninstall.stderr, "")
        XCTAssertTrue(uninstall.stdout.contains("STATUS\tLABEL\tPATH"))
        XCTAssertTrue(uninstall.stdout.contains("removed\tcom.updatebar.check\t\(plistPath)"))

        let missing = try CLIProcess.run(["background", "uninstall"], home: home, environment: ["HOME": home.path])
        XCTAssertEqual(missing.exitCode, 0)
        XCTAssertEqual(missing.stderr, "")
        XCTAssertTrue(missing.stdout.contains("STATUS\tLABEL\tPATH"))
        XCTAssertTrue(missing.stdout.contains("not_installed\tcom.updatebar.check\t\(plistPath)"))
    }

    func testBackgroundInstallAndUninstallHumanOutputShowsManualLaunchctlNextSteps() throws {
        let base = try makeTemporaryHome(prefix: "updatebar-cli-background-tests")
        let home = base.appendingPathComponent("Home With Spaces")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let quotedPlistPath = "'\(plistURL(home: home).path)'"

        let install = try CLIProcess.run(["background", "install", "--yes"], home: home, environment: ["HOME": home.path])
        XCTAssertEqual(install.exitCode, 0)
        XCTAssertEqual(install.stderr, "")
        XCTAssertTrue(install.stdout.contains("Next"))
        XCTAssertTrue(install.stdout.contains("launchctl bootstrap gui/$(id -u) \(quotedPlistPath)"))

        let uninstall = try CLIProcess.run(["background", "uninstall"], home: home, environment: ["HOME": home.path])
        XCTAssertEqual(uninstall.exitCode, 0)
        XCTAssertEqual(uninstall.stderr, "")
        XCTAssertTrue(uninstall.stdout.contains("Next"))
        XCTAssertTrue(uninstall.stdout.contains("launchctl bootout gui/$(id -u)/com.updatebar.check"))
    }

    func testBackgroundHumanOutputRedactsSecretLikeHomePath() throws {
        let base = try makeTemporaryHome(prefix: "updatebar-cli-background-tests")
        let secret = "sk-or-v1-secret-value"
        let home = base.appendingPathComponent(secret)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let install = try CLIProcess.run(["background", "install", "--yes"], home: home, environment: ["HOME": home.path])
        let status = try CLIProcess.run(["background", "status"], home: home, environment: ["HOME": home.path])

        XCTAssertEqual(install.exitCode, 0)
        XCTAssertEqual(status.exitCode, 0)
        XCTAssertTrue(install.stdout.contains("[REDACTED]"))
        XCTAssertTrue(status.stdout.contains("[REDACTED]"))
        XCTAssertFalse(install.stdout.contains(secret))
        XCTAssertFalse(status.stdout.contains(secret))
    }

    func testBackgroundJSONOutputRedactsSecretLikeHomePath() throws {
        let base = try makeTemporaryHome(prefix: "updatebar-cli-background-tests")
        let secret = "sk-or-v1-secret-value"
        let home = base.appendingPathComponent(secret)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let install = try CLIProcess.run(["background", "install", "--yes", "--json"], home: home, environment: ["HOME": home.path])
        let status = try CLIProcess.run(["background", "status", "--json"], home: home, environment: ["HOME": home.path])
        let uninstall = try CLIProcess.run(["background", "uninstall", "--json"], home: home, environment: ["HOME": home.path])

        for result in [install, status, uninstall] {
            XCTAssertEqual(result.exitCode, 0)
            XCTAssertTrue(result.stdout.contains("[REDACTED]"))
            XCTAssertFalse(result.stdout.contains(secret))
        }
    }

    func testBackgroundJSONCommandsWithJSONStreamEqualsProduceGuidance() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-background-tests")
        let cases = [
            ("background install", ["background", "install", "--json-stream=true"], "Run updatebar background install --yes --json"),
            ("background status", ["background", "status", "--json-stream=true"], "Run updatebar background status --json"),
            ("background uninstall", ["background", "uninstall", "--json-stream=true"], "Run updatebar background uninstall --json")
        ]

        for (command, arguments, guidance) in cases {
            let result = try CLIProcess.run(arguments, home: home, environment: ["HOME": home.path])
            let payload = try jsonObject(in: result.stdout)

            XCTAssertEqual(result.exitCode, 1, command)
            XCTAssertEqual(payload["code"] as? String, "usage_error", command)
            XCTAssertTrue(result.stdout.contains("\(command) does not support JSONL streaming"), command)
            XCTAssertTrue(result.stdout.contains(guidance), command)
            XCTAssertFalse(result.stdout.contains("Unknown option '--json-stream'"), command)
        }
    }

    private func plistURL(home: URL) -> URL {
        home
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("com.updatebar.check.plist")
    }

    private func loadPlist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private func jsonObject(in output: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
    }
}
#endif
