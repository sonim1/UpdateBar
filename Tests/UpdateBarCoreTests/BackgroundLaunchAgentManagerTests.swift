import Foundation
import UpdateBarCore
import XCTest

final class BackgroundLaunchAgentManagerTests: XCTestCase {
    func testInstallWritesCheckOnlyLaunchAgentWithResolvedExecutableAndHome() throws {
        let root = try temporaryDirectory()
        let userHome = root.appendingPathComponent("user-home")
        let updateBarHome = root.appendingPathComponent("updatebar-home")
        let binDirectory = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: userHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: updateBarHome,
            withIntermediateDirectories: true
        )
        let executable = try writeExecutable(named: "updatebar", in: binDirectory)

        let manager = BackgroundLaunchAgentManager(
            environment: [
                "HOME": userHome.path,
                "UPDATEBAR_HOME": updateBarHome.path,
                "PATH": binDirectory.path,
            ],
            executableName: "updatebar",
            currentDirectory: root
        )

        XCTAssertFalse(manager.isInstalled)
        let plistURL = try manager.install(intervalSeconds: 123)

        XCTAssertEqual(plistURL, manager.plistURL)
        XCTAssertTrue(manager.isInstalled)
        let plist = try loadPlist(plistURL)
        XCTAssertEqual(plist["Label"] as? String, BackgroundLaunchAgentManager.label)
        XCTAssertEqual(plist["StartInterval"] as? Int, 123)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(
            plist["ProgramArguments"] as? [String],
            [executable.path, "check", "--exit-zero-on-outdated"]
        )
        XCTAssertEqual(
            (plist["EnvironmentVariables"] as? [String: String])?["UPDATEBAR_HOME"],
            updateBarHome.path
        )
    }

    func testUninstallRemovesExistingPlistAndReportsMissing() throws {
        let root = try temporaryDirectory()
        let binDirectory = root.appendingPathComponent("bin")
        _ = try writeExecutable(named: "updatebar", in: binDirectory)
        let manager = BackgroundLaunchAgentManager(
            environment: ["HOME": root.path, "PATH": binDirectory.path],
            executableName: "updatebar",
            currentDirectory: root
        )

        try manager.install(intervalSeconds: 60)

        XCTAssertTrue(try manager.uninstall())
        XCTAssertFalse(manager.isInstalled)
        XCTAssertFalse(try manager.uninstall())
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-background-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeExecutable(named name: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        return executable
    }

    private func loadPlist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }
}
