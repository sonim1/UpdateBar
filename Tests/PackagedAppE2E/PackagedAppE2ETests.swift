import AppKit
import XCTest

@MainActor
final class PackagedAppE2ETests: XCTestCase {
    func testFirstRunUpdateAndPersistedHistory() throws {
        continueAfterFailure = false
        let fixture = try makeFixture()

        try registerAndApprove(fixture)
        fixture.capture("reviewed-and-checked")
        click(fixture.app.buttons["items-update"])
        try fixture.wait("successful update history") {
            try fixture.updates().last?.outcome == "updated"
        }
        XCTAssertEqual(try fixture.installedVersion(), "2.0.0")
        let event = try XCTUnwrap(fixture.updates().last)
        XCTAssertEqual(event.from, "1.0.0")
        XCTAssertEqual(event.to, "2.0.0")
        XCTAssertEqual(event.target, "2.0.0")
        XCTAssertNil(event.error)
        showHistory(fixture, outcome: "updated")
        fixture.capture("successful-update")

        fixture.app.terminate()
        fixture.launch()
        openDashboard(fixture)
        let item = try XCTUnwrap(fixture.status().items.first)
        XCTAssertEqual(item.id, "brew.e2e-fixture")
        XCTAssertEqual(item.status, "ok")
        XCTAssertEqual(item.current, "2.0.0")
        let approvals = try fixture.approvals()
        XCTAssertEqual(Set(approvals.map(\.field)), ["check.cmd", "update.cmd"])
        XCTAssertTrue(approvals.allSatisfy(\.approved))
        XCTAssertEqual(try fixture.updates().count, 1)
        showHistory(fixture, outcome: "updated")
        fixture.capture("persisted-after-relaunch")
    }

    func testExitZeroWithoutInstalledVersionChangeIsFailure() throws {
        continueAfterFailure = false
        let fixture = try makeFixture()
        try fixture.setUpdateMode("noop")

        try registerAndApprove(fixture)
        click(fixture.app.buttons["items-update"])
        try fixture.wait("failed update history") {
            try fixture.updates().last?.outcome == "failed"
        }
        XCTAssertEqual(try fixture.installedVersion(), "1.0.0")
        let event = try XCTUnwrap(fixture.updates().last)
        XCTAssertEqual(event.from, "1.0.0")
        XCTAssertEqual(event.to, "1.0.0")
        XCTAssertEqual(event.target, "2.0.0")
        XCTAssertEqual(event.commandExitCode, 0)
        XCTAssertFalse(try XCTUnwrap(event.error).isEmpty)
        showHistory(fixture, outcome: "failed")
        click(fixture.app.tables["Update history"].staticTexts["brew.e2e-fixture failed"])
        let detail = fixture.app.textViews["logs-failure-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        XCTAssertTrue((detail.value as? String)?.contains("Exit code: 0") == true)
        fixture.capture("verified-noop-failure")
    }

    func testEmptyScanCanBeRetriedWithoutRegisteringOrApprovingAnything() throws {
        continueAfterFailure = false
        let fixture = try makeFixture(includeBrew: false)
        fixture.launch()
        openDashboard(fixture)
        selectSection("Items", in: fixture)
        click(fixture.app.buttons["items-scan-add"])
        XCTAssertTrue(
            fixture.app.staticTexts["scan-guidance-initial"].waitForExistence(timeout: 10))
        click(fixture.app.buttons["Scan for installed tools"])
        XCTAssertTrue(fixture.app.staticTexts["scan-guidance-empty"].waitForExistence(timeout: 15))
        XCTAssertEqual(try fixture.status().items.count, 0)
        fixture.capture("empty-scan")

        try fixture.installBrew()
        click(fixture.app.buttons["Scan for installed tools"])
        XCTAssertTrue(fixture.app.checkBoxes["Enable e2e-fixture"].waitForExistence(timeout: 15))
        XCTAssertEqual(try fixture.status().items.count, 0)
        XCTAssertEqual(try fixture.updates().count, 0)
        XCTAssertEqual(try fixture.installedVersion(), "1.0.0")
        fixture.capture("scan-retry-without-mutation")
    }

    private func registerAndApprove(_ fixture: AppFixture) throws {
        fixture.launch()
        openDashboard(fixture)
        XCTAssertEqual(try fixture.status().items.count, 0)
        selectSection("Items", in: fixture)
        click(fixture.app.buttons["items-scan-add"])
        click(fixture.app.buttons["Scan for installed tools"])
        click(fixture.app.checkBoxes["Enable e2e-fixture"])
        try fixture.wait("registered scan candidate") {
            try fixture.status().items.map(\.id) == ["brew.e2e-fixture"]
        }
        let approvals = try fixture.approvals()
        XCTAssertEqual(Set(approvals.map(\.field)), ["check.cmd", "update.cmd"])
        XCTAssertTrue(approvals.allSatisfy { !$0.approved })
        XCTAssertEqual(try fixture.installedVersion(), "1.0.0")
        XCTAssertEqual(try fixture.updates().count, 0)
        XCTAssertFalse(try fixture.brewCalls().contains("upgrade"))

        selectSection("Items", in: fixture)
        XCTAssertFalse(fixture.app.buttons["items-update"].isEnabled)
        click(fixture.app.buttons["Review commands for e2e-fixture"])
        for field in ["check.cmd", "update.cmd"] {
            let approve = fixture.app.buttons["Approve \(field)"]
            XCTAssertTrue(approve.waitForExistence(timeout: 10))
            XCTAssertFalse(approve.isEnabled, "Exact-command acknowledgement must precede approval")
            click(fixture.app.checkBoxes["Confirm review of \(field)"])
            click(approve)
            try fixture.wait("saved approval for \(field)") {
                try fixture.approvals().contains { $0.field == field && $0.approved }
            }
        }
        click(fixture.app.buttons["Close item details"])
        click(fixture.app.buttons["items-check"])
        try fixture.wait("outdated checked status") {
            try fixture.status().items.first?.status == "outdated"
        }
        let item = try XCTUnwrap(fixture.status().items.first)
        XCTAssertEqual(item.current, "1.0.0")
        XCTAssertEqual(item.latest, "2.0.0")
        XCTAssertEqual(try fixture.updates().count, 0)
        XCTAssertFalse(try fixture.brewCalls().contains("upgrade"))
    }

    private func makeFixture(includeBrew: Bool = true) throws -> AppFixture {
        let fixture = try AppFixture(includeBrew: includeBrew)
        addTeardownBlock { await fixture.finish() }
        return fixture
    }

    private func openDashboard(_ fixture: AppFixture) {
        click(
            fixture.app.descendants(matching: .any).matching(identifier: "updatebar-status-button")
                .firstMatch)
        click(fixture.app.menuItems["Dashboard"])
        XCTAssertTrue(fixture.app.windows["Dashboard"].waitForExistence(timeout: 10))
    }

    private func selectSection(_ title: String, in fixture: AppFixture) {
        click(fixture.app.tables["Dashboard sections"].staticTexts[title])
    }

    private func showHistory(_ fixture: AppFixture, outcome: String) {
        selectSection("Logs", in: fixture)
        XCTAssertTrue(
            fixture.app.tables["Update history"].staticTexts["brew.e2e-fixture \(outcome)"]
                .waitForExistence(timeout: 10)
        )
    }

    private func click(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            element.waitForExistence(timeout: 15), "Missing UI control", file: file, line: line)
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: element)
        XCTAssertEqual(
            XCTWaiter.wait(for: [ready], timeout: 15), .completed, file: file, line: line)
        element.click()
    }
}

@MainActor
private final class AppFixture {
    let app: XCUIApplication
    private let root: URL
    private let cli: URL
    private let environment: [String: String]
    private var launched = false

    init(includeBrew: Bool = true) throws {
        guard
            let path = Bundle(for: PackagedAppE2ETests.self)
                .object(forInfoDictionaryKey: "UpdateBarE2EAppPath") as? String,
            path.hasPrefix("/"),
            let bundle = Bundle(url: URL(fileURLWithPath: path)),
            let identifier = bundle.bundleIdentifier
        else {
            throw FixtureError.invalidBundle
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty
        else {
            throw FixtureError.appAlreadyRunning
        }
        let bundleURL = URL(fileURLWithPath: path)
        app = XCUIApplication(url: bundleURL)
        cli = bundleURL.appendingPathComponent("Contents/Resources/updatebar")
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "updatebar-packaged-e2e-\(UUID().uuidString)", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        environment = [
            "HOME": root.path,
            "CFFIXED_USER_HOME": root.path,
            "UPDATEBAR_HOME": root.path,
            "PATH": bin.path,
            "LANG": "en_US.UTF-8",
        ]
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: bin.appendingPathComponent("head"),
            withDestinationURL: URL(fileURLWithPath: "/usr/bin/head"))
        try "1.0.0\n".write(
            to: root.appendingPathComponent("installed-version"), atomically: true, encoding: .utf8)
        try setUpdateMode("success")
        if includeBrew { try installBrew() }
        app.launchEnvironment = environment
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)"]
    }

    func launch() {
        launched = true
        app.launch()
    }

    func installBrew() throws {
        let script = """
            #!/bin/sh
            set -eu
            fixture_home=\(shellQuote(root.path))
            printf '%s\\n' "$*" >> "$fixture_home/brew-calls"
            case "$1" in
              --version) printf 'Homebrew 4.0.0\\n' ;;
              leaves) printf 'e2e-fixture\\n' ;;
              list) printf 'e2e-fixture %s\\n' "$(/bin/cat "$fixture_home/installed-version")" ;;
              info) printf '{"formulae":[{"name":"e2e-fixture","versions":{"stable":"2.0.0"}}]}\\n' ;;
              upgrade)
                [ "$#" -eq 2 ] && [ "$2" = e2e-fixture ] || exit 64
                case "$(/bin/cat "$fixture_home/update-mode")" in
                  success) printf '2.0.0\\n' > "$fixture_home/installed-version" ;;
                  noop) printf 'Fixture command exited successfully without installing anything\\n' ;;
                  *) printf 'Unsupported fixture update mode\\n' >&2; exit 64 ;;
                esac ;;
              *) printf 'Unsupported fixture brew operation\\n' >&2; exit 64 ;;
            esac
            """
        let path = root.appendingPathComponent("bin/brew")
        try script.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }

    func setUpdateMode(_ mode: String) throws {
        try mode.write(
            to: root.appendingPathComponent("update-mode"), atomically: true, encoding: .utf8)
    }

    func installedVersion() throws -> String {
        try String(contentsOf: root.appendingPathComponent("installed-version"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func brewCalls() throws -> String {
        try String(contentsOf: root.appendingPathComponent("brew-calls"), encoding: .utf8)
    }

    func status() throws -> Status {
        try readCLI(["status", "--exit-zero-on-outdated", "--json"])
    }

    func approvals() throws -> [Approval] {
        try readCLI(["approvals", "brew.e2e-fixture", "--json"])
    }

    func updates() throws -> [History] {
        let events: [History] = try readCLI(["history", "--json"])
        return events.filter { $0.event == "update_finished" }
    }

    func wait(_ description: String, until condition: () throws -> Bool) throws {
        let deadline = Date().addingTimeInterval(20)
        repeat {
            if try condition() { return }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        throw FixtureError.timedOut(description)
    }

    func capture(_ stage: String) {
        guard launched, app.state != .notRunning else { return }
        XCTContext.runActivity(named: stage) { activity in
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = stage
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "\(stage)-ui-tree"
            tree.lifetime = .keepAlways
            activity.add(tree)
        }
    }

    func finish() {
        capture("final-state")
        if launched { app.terminate() }
        XCTContext.runActivity(named: "saved fixture state") { activity in
            for name in ["manifest.json", "state.json", "history.jsonl", "brew-calls"] {
                if let data = FileManager.default.contents(
                    atPath: root.appendingPathComponent(name).path)
                {
                    let attachment = XCTAttachment(
                        data: data, uniformTypeIdentifier: "public.plain-text")
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    activity.add(attachment)
                }
            }
        }
        XCTAssertNoThrow(try FileManager.default.removeItem(at: root))
    }

    private func readCLI<T: Decodable>(_ arguments: [String]) throws -> T {
        let process = Process()
        process.executableURL = cli
        process.arguments = arguments
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FixtureError.cliFailed(arguments, String(decoding: diagnostics, as: UTF8.self))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private enum FixtureError: LocalizedError {
    case invalidBundle
    case appAlreadyRunning
    case timedOut(String)
    case cliFailed([String], String)

    var errorDescription: String? {
        switch self {
        case .invalidBundle:
            "Run Scripts/app-e2e.sh with a packaged UpdateBar.app."
        case .appAlreadyRunning:
            "Quit the running UpdateBar app before testing; E2E will not terminate an existing instance."
        case .timedOut(let condition):
            "Timed out waiting for \(condition)."
        case .cliFailed(let arguments, let diagnostics):
            "Bundled CLI \(arguments.joined(separator: " ")) failed: \(diagnostics)"
        }
    }
}

private struct Status: Decodable {
    let items: [Item]

    struct Item: Decodable {
        let id: String
        let current: String?
        let latest: String?
        let status: String
    }
}

private struct Approval: Decodable {
    let field: String
    let approved: Bool
}

private struct History: Decodable {
    let event: String
    let from: String?
    let to: String?
    let outcome: String?
    let target: String?
    let error: String?
    let commandExitCode: Int?
}
