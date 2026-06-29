import Foundation
import UpdateBarCore
import XCTest

final class InitCommandTests: XCTestCase {
    func testInitSelectAddsOnlySelectedFullCandidatesAsUntrusted() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            [
                "init", "--json", "--detectors", "brew,npm_global",
                "--select", "brew.gh,npm.typescript",
            ],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        let payload = try JSONDecoder.updateBar.decode(
            InitPayload.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(payload.added.sorted(), ["brew.gh", "npm.typescript"])
        XCTAssertEqual(payload.replaced, [])
        XCTAssertEqual(payload.skipped, [])

        let manifest = try ManifestStore(paths: AppPaths(homeDirectory: home)).load()
        XCTAssertEqual(manifest.items.map(\.id).sorted(), ["brew.gh", "npm.typescript"])
        XCTAssertEqual(manifest.item(id: "brew.gh")?.trust.level, .untrusted)
        XCTAssertEqual(manifest.item(id: "brew.gh")?.trust.approvedCommands, [:])
        XCTAssertNil(manifest.item(id: "brew.jq"))
    }

    func testInitSkipsDuplicateCandidatesUnlessReplaceIsPassed() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let first = try CLIProcess.run(
            [
                "init", "--json", "--detectors", "brew",
                "--select", "brew.gh",
            ],
            home: home,
            environment: ["PATH": bin.path]
        )
        let duplicate = try CLIProcess.run(
            [
                "init", "--json", "--detectors", "brew",
                "--select", "brew.gh",
            ],
            home: home,
            environment: ["PATH": bin.path]
        )
        let replaced = try CLIProcess.run(
            [
                "init", "--json", "--detectors", "brew",
                "--select", "brew.gh", "--replace",
            ],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(first.exitCode, 0)
        XCTAssertEqual(duplicate.exitCode, 0)
        XCTAssertEqual(replaced.exitCode, 0)

        let duplicatePayload = try JSONDecoder.updateBar.decode(
            InitPayload.self, from: Data(duplicate.stdout.utf8))
        let replacedPayload = try JSONDecoder.updateBar.decode(
            InitPayload.self, from: Data(replaced.stdout.utf8))
        XCTAssertEqual(duplicatePayload.added, [])
        XCTAssertEqual(duplicatePayload.replaced, [])
        XCTAssertEqual(duplicatePayload.skipped, ["brew.gh"])
        XCTAssertEqual(replacedPayload.added, [])
        XCTAssertEqual(replacedPayload.replaced, ["brew.gh"])
        XCTAssertEqual(replacedPayload.skipped, [])
    }

    func testInitInteractiveSelectionAcceptsCandidateNumbers() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            ["init", "--detectors", "brew"],
            home: home,
            stdin: "2\n",
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("[1] gh"))
        XCTAssertTrue(result.stdout.contains("[2] jq"))
        XCTAssertTrue(result.stdout.contains("added 1"))
        let manifest = try ManifestStore(paths: AppPaths(homeDirectory: home)).load()
        XCTAssertEqual(manifest.items.map(\.id), ["brew.jq"])
    }

    func testInitRejectsUnsupportedCandidates() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeKnownTool(home: home)

        let result = try CLIProcess.run(
            ["init", "--json", "--detectors", "known", "--select", "known.gh"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder.updateBar.decode(
            InitPayload.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertTrue(payload.errors.contains("known.gh: not importable"))
        XCTAssertTrue(try ManifestStore(paths: AppPaths(homeDirectory: home)).load().items.isEmpty)
    }

    private func fakeManagers(home: URL) throws -> URL {
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            if [ "$1" = "list" ]; then
              printf 'jq 1.7.1\\ngh 2.74.0\\n'
            fi
            """
        )
        try writeExecutable(
            bin.appendingPathComponent("npm"),
            """
            #!/bin/sh
            if [ "$1" = "ls" ]; then
              printf '{"dependencies":{"typescript":{"version":"5.8.3"}}}\\n'
            fi
            """
        )
        return bin
    }

    private func fakeKnownTool(home: URL) throws -> URL {
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("gh"),
            """
            #!/bin/sh
            printf 'gh version 2.74.0\\n'
            """
        )
        return bin
    }

    private func writeExecutable(_ url: URL, _ body: String) throws {
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private struct InitPayload: Decodable {
        var ok: Bool
        var added: [String]
        var replaced: [String]
        var skipped: [String]
        var errors: [String]
    }
}
