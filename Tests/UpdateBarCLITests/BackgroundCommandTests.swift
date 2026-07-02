import Foundation
import XCTest

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
}
#endif
