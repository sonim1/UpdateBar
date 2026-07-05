import Foundation
import UpdateBarCore
import XCTest

final class DoctorCommandTests: XCTestCase {
    func testDoctorHumanReportsCorePathsWithoutCreatingFiles() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doctor-tests")
        let paths = AppPaths(homeDirectory: home)

        let result = try CLIProcess.run(["doctor"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("OK\tconfig"))
        XCTAssertTrue(result.stdout.contains("OK\tmanifest"))
        XCTAssertTrue(result.stdout.contains("OK\tstate"))
        XCTAssertTrue(result.stdout.contains(paths.homeDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.configFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.manifestFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.stateFile.path))
    }

    func testDoctorJSONReportsOKChecks() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doctor-tests")

        let result = try CLIProcess.run(["doctor", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        let payload = try JSONDecoder.updateBar.decode(
            DoctorPayload.self, from: Data(result.stdout.utf8))
        XCTAssertTrue(payload.ok)
        XCTAssertEqual(payload.checks.map(\.name), ["home", "config", "manifest", "state"])
        XCTAssertTrue(payload.checks.allSatisfy(\.ok))
    }

    func testDoctorJSONReportsCorruptManifest() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-doctor-tests")
        let paths = AppPaths(homeDirectory: home)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: paths.manifestFile)

        let result = try CLIProcess.run(["doctor", "--json"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        let payload = try JSONDecoder.updateBar.decode(
            DoctorPayload.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertEqual(payload.checks.first(where: { $0.name == "manifest" })?.ok, false)
        XCTAssertTrue(
            payload.checks.first(where: { $0.name == "manifest" })?.message.contains(
                "corrupt") ?? false)
    }

    private struct DoctorPayload: Decodable {
        var ok: Bool
        var home: String
        var checks: [Check]

        struct Check: Decodable {
            var name: String
            var ok: Bool
            var path: String?
            var message: String
        }
    }
}
