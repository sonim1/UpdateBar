import Foundation
import UpdateBarCore
import XCTest

final class InitCommandTests: XCTestCase {
    func testInitSelectAddsOnlySelectedFullCandidatesAsUntrusted() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home, includeNPM: true)

        let result = try CLIProcess.run(
            [
                "init", "--json", "--select", "brew.gh,npm.typescript",
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
                "init", "--json", "--select", "brew.gh",
            ],
            home: home,
            environment: ["PATH": bin.path]
        )
        let duplicate = try CLIProcess.run(
            [
                "init", "--json", "--select", "brew.gh",
            ],
            home: home,
            environment: ["PATH": bin.path]
        )
        let replaced = try CLIProcess.run(
            [
                "init", "--json", "--select", "brew.gh", "--replace",
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

    func testInitDeduplicatesRepeatedScanCandidates() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            if [ "$1" = "leaves" ]; then
              printf 'gh\\ngh\\n'
            elif [ "$1" = "list" ]; then
              printf 'gh 2.74.0\\ngh 2.74.0\\n'
            fi
            """
        )

        let result = try CLIProcess.run(
            ["init", "--json", "--select", "ALL"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        let payload = try JSONDecoder.updateBar.decode(
            InitPayload.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(payload.added, ["brew.gh"])
        let manifest = try ManifestStore(paths: AppPaths(homeDirectory: home)).load()
        XCTAssertEqual(manifest.items.map(\.id), ["brew.gh"])
    }

    func testInitInteractiveSelectionAcceptsCandidateNumbers() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            ["init"],
            home: home,
            stdin: "2\n",
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("ITEM\tID\tCATEGORY\tSOURCE"))
        XCTAssertTrue(result.stdout.contains("[1] gh"))
        XCTAssertTrue(result.stdout.contains("[1] gh 2.74.0\tbrew.gh\tcloud-devops\tbrew"))
        XCTAssertTrue(result.stdout.contains("[2] jq"))
        XCTAssertTrue(result.stdout.contains("[2] jq 1.7.1\tbrew.jq\tshell-utility\tbrew"))
        XCTAssertTrue(result.stdout.contains("added 1"))
        let manifest = try ManifestStore(paths: AppPaths(homeDirectory: home)).load()
        XCTAssertEqual(manifest.items.map(\.id), ["brew.jq"])
    }

    func testInitSelectAcceptsCandidateNumbersInHeadlessMode() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            ["init", "--json", "--select", "2"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        let payload = try JSONDecoder.updateBar.decode(
            InitPayload.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(payload.added, ["brew.jq"])
        let manifest = try ManifestStore(paths: AppPaths(homeDirectory: home)).load()
        XCTAssertEqual(manifest.items.map(\.id), ["brew.jq"])
    }

    func testInitHumanModePrintsApprovalNextStepBeforeCheck() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            ["init", "--select", "brew.gh"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("added 1"))
        XCTAssertTrue(result.stdout.contains("Next"))
        XCTAssertTrue(result.stdout.contains("updatebar approvals brew.gh"))
        XCTAssertFalse(result.stdout.contains("updatebar check brew.gh"))
    }

    func testInitHumanModeExplainsSkippedDuplicates() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        _ = try CLIProcess.run(
            ["init", "--select", "brew.gh"],
            home: home,
            environment: ["PATH": bin.path]
        )

        let result = try CLIProcess.run(
            ["init", "--select", "brew.gh"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("skipped 1"))
        XCTAssertTrue(result.stdout.contains("brew.gh"))
        XCTAssertTrue(result.stdout.contains("--replace"))
    }

    func testInitInteractiveSelectionAcceptsAll() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            ["init"],
            home: home,
            stdin: "all\n",
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("numbers, ids, or all"))
        let manifest = try ManifestStore(paths: AppPaths(homeDirectory: home)).load()
        XCTAssertEqual(manifest.items.map(\.id).sorted(), ["brew.gh", "brew.jq"])
    }

    func testInitWithoutSelectionExplainsHeadlessSelectUsage() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            ["init"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stdout.contains("[1] gh"))
        XCTAssertTrue(result.stderr.contains("Select items to add (numbers, ids, or all): \nselection required"))
        XCTAssertFalse(result.stderr.contains("Select items to add (numbers, ids, or all): selection required"))
        XCTAssertTrue(result.stderr.contains("selection required"))
        XCTAssertTrue(result.stderr.contains("--select"))
        XCTAssertTrue(result.stderr.contains("all"))
    }

    func testInitInteractiveSelectionAcceptsWhitespaceSeparatedNumbers() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            ["init"],
            home: home,
            stdin: "1 2\n",
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        let manifest = try ManifestStore(paths: AppPaths(homeDirectory: home)).load()
        XCTAssertEqual(manifest.items.map(\.id).sorted(), ["brew.gh", "brew.jq"])
    }

    func testInitRejectsUnsupportedCandidates() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeKnownTool(home: home)

        let result = try CLIProcess.run(
            ["init", "--json", "--select", "known.gh"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder.updateBar.decode(
            InitPayload.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertTrue(payload.errors.contains { $0.contains("known.gh: not importable") })
        XCTAssertTrue(payload.errors.contains { $0.contains("check-only") })
        XCTAssertTrue(try ManifestStore(paths: AppPaths(homeDirectory: home)).load().items.isEmpty)
    }

    func testInitUnknownSelectionSuggestsScanForCandidateIDs() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            ["init", "--json", "--select", "brew.missing"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder.updateBar.decode(
            InitPayload.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertTrue(payload.errors.contains { $0.contains("brew.missing: not found") })
        XCTAssertTrue(payload.errors.contains { $0.contains("updatebar scan") })
    }

    func testInitUnknownCategorySelectionSuggestsFilteredScan() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            ["init", "--json", "--category", "cloud-devops", "--select", "brew.missing"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder.updateBar.decode(
            InitPayload.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertTrue(payload.errors.contains { $0.contains("brew.missing: not found") })
        XCTAssertTrue(payload.errors.contains { $0.contains("updatebar scan --category cloud-devops") })
    }

    func testInitJSONRequiresHeadlessSelection() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            ["init", "--json"],
            home: home,
            stdin: "1\n",
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertFalse(result.stdout.contains("Recommended"))
        let payload = try JSONDecoder.updateBar.decode(
            ErrorPayload.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertTrue(payload.errors.contains { $0.contains("init --json requires --select") })
        XCTAssertTrue(payload.errors.contains { $0.contains("init --select all --json") })
        XCTAssertTrue(payload.errors.contains { $0.contains("updatebar scan") })
    }

    func testInitSelectSupportsWhitespaceAndDedupe() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            [
                "init", "--json", "--select", "brew.gh, brew.jq, brew.gh",
            ],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        let payload = try JSONDecoder.updateBar.decode(
            InitPayload.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(payload.added, ["brew.gh", "brew.jq"])
        let manifest = try ManifestStore(paths: AppPaths(homeDirectory: home)).load()
        XCTAssertEqual(manifest.items.map(\.id), ["brew.gh", "brew.jq"])
    }

    func testInitSelectSupportsUppercaseAll() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            [
                "init", "--json", "--select", "ALL",
            ],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        let payload = try JSONDecoder.updateBar.decode(
            InitPayload.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(payload.added, ["brew.gh", "brew.jq"])
    }

    func testInitRejectsAllCombinedWithExplicitSelections() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            [
                "init", "--json", "--select", "all,brew.gh",
            ],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder.updateBar.decode(
            ErrorPayload.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertTrue(payload.errors.contains { $0.contains("select: all cannot be combined") })
    }

    func testInitDetectorsFlagIsRemovedFromCLI() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let result = try CLIProcess.run(
            ["init", "--json", "--detectors", "brew", "--select", "all"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("init --detectors was removed"))
        XCTAssertTrue(result.stdout.contains("Run updatebar init --category <category>"))
        XCTAssertTrue(result.stdout.contains("Default scan sources are selected automatically"))
    }

    func testInitFiltersCategoryCaseInsensitive() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            [
                "init", "--json", "--category", "CLOUD-DEVOPS",
                "--select", "brew.gh",
            ],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        let payload = try JSONDecoder.updateBar.decode(
            InitPayload.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(payload.added, ["brew.gh"])
        let manifest = try ManifestStore(paths: AppPaths(homeDirectory: home)).load()
        XCTAssertEqual(manifest.items.map(\.id), ["brew.gh"])
    }

    func testInitFiltersCategoryWithWhitespaceAndUnderscore() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            [
                "init", "--json", "--category", "CLOUD_DEVOPS",
                "--select", "brew.gh",
            ],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        let payload = try JSONDecoder.updateBar.decode(
            InitPayload.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(payload.added, ["brew.gh"])
        let manifest = try ManifestStore(paths: AppPaths(homeDirectory: home)).load()
        XCTAssertEqual(manifest.items.map(\.id), ["brew.gh"])
    }

    func testInitFiltersCategoryAliasWithoutSeparator() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            [
                "init", "--json", "--category", "clouddevops",
                "--select", "brew.gh",
            ],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 0)
        let payload = try JSONDecoder.updateBar.decode(
            InitPayload.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(payload.added, ["brew.gh"])
        let manifest = try ManifestStore(paths: AppPaths(homeDirectory: home)).load()
        XCTAssertEqual(manifest.items.map(\.id), ["brew.gh"])
    }

    func testInitRejectsBlankCategoryFilter() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = try fakeManagers(home: home)

        let result = try CLIProcess.run(
            ["init", "--json", "--category", "___", "--select", "brew.gh"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder.updateBar.decode(
            ErrorPayload.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertTrue(payload.errors.contains { $0.contains("category must not be empty") })
    }

    func testInitRejectsBlankCategoryBeforeRunningDetectors() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = home.appendingPathComponent("bin")
        let marker = home.appendingPathComponent("detector-ran")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            printf 'ran' > \(marker.path)
            printf 'detector should not run\\n' >&2
            exit 42
            """
        )

        let result = try CLIProcess.run(
            [
                "init", "--json", "--category", "___", "--select", "brew.gh",
            ],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder.updateBar.decode(
            ErrorPayload.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertTrue(payload.errors.contains { $0.contains("category must not be empty") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(result.stderr.contains("detector should not run"))
    }

    func testInitCategoryMCPServerRunsOnlyRelevantDefaultDetector() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = home.appendingPathComponent("bin")
        let marker = home.appendingPathComponent("brew-ran")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            printf 'ran' > \(marker.path)
            exit 42
            """
        )
        let config = home.appendingPathComponent(".cursor/mcp.json")
        try FileManager.default.createDirectory(
            at: config.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"mcpServers":{"filesystem":{"command":"npx"}}}"#.write(
            to: config,
            atomically: true,
            encoding: .utf8
        )

        let result = try CLIProcess.run(
            ["init", "--json", "--category", "mcp-server", "--select", "all"],
            home: home,
            environment: ["HOME": home.path, "PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder.updateBar.decode(
            ErrorPayload.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertTrue(payload.errors.contains { $0.contains("No importable candidates found") })
        XCTAssertTrue(payload.errors.contains { $0.contains("review-only") })
        XCTAssertTrue(payload.errors.contains { $0.contains("updatebar scan --category mcp-server") })
        XCTAssertTrue(payload.errors.contains { $0.contains("updatebar scan without --category") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testInitWithoutSelectRequiresImportableCandidates() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            if [ "$1" = "leaves" ]; then
              printf ''
            elif [ "$1" = "list" ]; then
              printf ''
            fi
            """
        )

        let result = try CLIProcess.run(
            ["init"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("No importable candidates found"))
    }

    func testInitWithoutSelectReportsScanErrorsWhenNoCandidatesAreImportable() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            printf 'brew exploded\\n' >&2
            exit 42
            """
        )

        let result = try CLIProcess.run(
            ["init"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("No importable candidates found"))
        XCTAssertTrue(result.stderr.contains("brew"))
        XCTAssertTrue(result.stderr.contains("brew exploded"))
        XCTAssertFalse(result.stderr.contains("if command -v brew"))
    }

    func testInitAllRequiresImportableCandidatesInJSONMode() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            if [ "$1" = "leaves" ]; then
              printf ''
            elif [ "$1" = "list" ]; then
              printf ''
            fi
            """
        )

        let result = try CLIProcess.run(
            ["init", "--json", "--select", "ALL"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder.updateBar.decode(
            ErrorPayload.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertTrue(payload.errors.contains { $0.contains("No importable candidates found") })
    }

    func testInitAllReportsScanErrorsInJSONModeWhenNoCandidatesAreImportable() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-init-tests")
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            printf 'brew exploded\\n' >&2
            exit 42
            """
        )

        let result = try CLIProcess.run(
            ["init", "--json", "--select", "ALL"],
            home: home,
            environment: ["PATH": bin.path]
        )

        XCTAssertEqual(result.exitCode, 1)
        let payload = try JSONDecoder.updateBar.decode(
            ErrorPayload.self, from: Data(result.stdout.utf8))
        XCTAssertFalse(payload.ok)
        XCTAssertTrue(payload.errors.contains { $0.contains("No importable candidates found") })
        XCTAssertTrue(payload.errors.contains { $0.contains("brew") && $0.contains("brew exploded") })
        XCTAssertFalse(payload.errors.contains { $0.contains("if command -v brew") })
    }

    private func fakeManagers(home: URL, includeNPM: Bool = false) throws -> URL {
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable(
            bin.appendingPathComponent("brew"),
            """
            #!/bin/sh
            if [ "$1" = "leaves" ]; then
              printf 'jq\\ngh\\n'
            elif [ "$1" = "list" ]; then
              printf 'jq 1.7.1\\ngh 2.74.0\\n'
            fi
            """
        )
        if includeNPM {
            try writeExecutable(
                bin.appendingPathComponent("npm"),
                """
                #!/bin/sh
                if [ "$1" = "ls" ]; then
                  printf '{"dependencies":{"typescript":{"version":"5.8.3"}}}\\n'
                fi
                """
            )
        }
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

    private struct ErrorPayload: Decodable {
        var ok: Bool
        var errors: [String]
    }
}
