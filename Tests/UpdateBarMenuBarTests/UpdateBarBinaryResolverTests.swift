import Foundation
import UpdateBarMenuBar
import XCTest

final class UpdateBarBinaryResolverTests: XCTestCase {
    func testUpdateBarBinOverrideWins() throws {
        let root = try temporaryDirectory()
        let override = try executable(at: root.appendingPathComponent("override-updatebar"))
        let bundled = try executable(at: root.appendingPathComponent("Resources/updatebar"))
        let pathBin = try executable(at: root.appendingPathComponent("bin/updatebar"))

        let resolution = try UpdateBarBinaryResolver().resolve(
            environment: ["UPDATEBAR_BIN": override.path, "PATH": pathBin.deletingLastPathComponent().path],
            bundledDirectory: bundled.deletingLastPathComponent(),
            developmentRoot: nil
        )

        XCTAssertEqual(resolution.path, override.path)
        XCTAssertEqual(resolution.source, .updateBarBin)
    }

    func testConfiguredPathWinsAfterEnvironmentOverride() throws {
        let root = try temporaryDirectory()
        let configured = try executable(at: root.appendingPathComponent("configured-updatebar"))

        let resolution = try UpdateBarBinaryResolver().resolve(
            environment: [:],
            configuredPath: configured.path,
            developmentRoot: nil
        )

        XCTAssertEqual(resolution.path, configured.path)
        XCTAssertEqual(resolution.source, .configured)
    }

    func testBundledBinaryWinsBeforePath() throws {
        let root = try temporaryDirectory()
        let bundled = try executable(at: root.appendingPathComponent("Resources/updatebar"))
        let pathBin = try executable(at: root.appendingPathComponent("bin/updatebar"))

        let resolution = try UpdateBarBinaryResolver().resolve(
            environment: ["PATH": pathBin.deletingLastPathComponent().path],
            bundledDirectory: bundled.deletingLastPathComponent(),
            developmentRoot: nil
        )

        XCTAssertEqual(resolution.path, bundled.path)
        XCTAssertEqual(resolution.source, .bundled)
    }

    func testPathWinsBeforeDevelopmentFallback() throws {
        let root = try temporaryDirectory()
        let pathBin = try executable(at: root.appendingPathComponent("bin/updatebar"))
        _ = try executable(at: root.appendingPathComponent(".build/debug/updatebar"))

        let resolution = try UpdateBarBinaryResolver().resolve(
            environment: ["PATH": pathBin.deletingLastPathComponent().path],
            developmentRoot: root
        )

        XCTAssertEqual(resolution.path, pathBin.path)
        XCTAssertEqual(resolution.source, .path)
    }

    func testPathResolutionIgnoresRelativeEntries() throws {
        let root = try temporaryDirectory()
        _ = try executable(at: root.appendingPathComponent("updatebar"))
        let originalDirectory = FileManager.default.currentDirectoryPath
        defer { FileManager.default.changeCurrentDirectoryPath(originalDirectory) }
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(root.path))

        XCTAssertThrowsError(try UpdateBarBinaryResolver().resolve(
            environment: ["PATH": "."],
            developmentRoot: nil,
            defaultPathEntries: []
        )) { error in
            XCTAssertEqual(error as? UpdateBarBinaryResolverError, .notFound)
        }
    }

    func testDevelopmentFallbackUsesSwiftPMDebugBinary() throws {
        let root = try temporaryDirectory()
        let devBinary = try executable(at: root.appendingPathComponent(".build/debug/updatebar"))

        let resolution = try UpdateBarBinaryResolver().resolve(
            environment: [:],
            developmentRoot: root,
            defaultPathEntries: []
        )

        XCTAssertEqual(resolution.path, devBinary.path)
        XCTAssertEqual(resolution.source, .developmentFallback)
    }

    func testInvalidExplicitPathThrows() throws {
        let root = try temporaryDirectory()
        let invalid = root.appendingPathComponent("missing-updatebar").path

        XCTAssertThrowsError(try UpdateBarBinaryResolver().resolve(
            environment: ["UPDATEBAR_BIN": invalid],
            developmentRoot: nil
        )) { error in
            XCTAssertEqual(
                error as? UpdateBarBinaryResolverError,
                .invalidPath(source: .updateBarBin, path: invalid)
            )
        }
    }

    private func executable(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url.standardizedFileURL
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-binary-resolver-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }
}
