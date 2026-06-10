import Foundation
import XCTest
import UpdateBarCore
import UpdateBarTestSupport

final class ValidateCommandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testValidateReadsRecipeFromStdin() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-validate-tests")
        let encoded = try JSONEncoder.updateBar.encode(recipe())

        let result = try CLIProcess.run(["validate", "-", "--json"], home: home, stdin: String(decoding: encoded, as: UTF8.self))

        XCTAssertEqual(result.exitCode, 0)
        let payload = try JSONDecoder().decode(ValidationPayload.self, from: Data(result.stdout.utf8))
        XCTAssertTrue(payload.valid)
        XCTAssertEqual(payload.errors, [])
    }

    func testValidateExplainRejectsUnsupportedJQVersionParse() throws {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-validate-tests")
        var item = recipe()
        item.versionParse = .jq(".version")
        let file = home.appendingPathComponent("jq-recipe.json")
        try JSONEncoder.updateBar.encode(item).write(to: file)

        let result = try CLIProcess.run(["validate", file.path, "--json", "--explain"], home: home)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stdout.contains("version_parse.jq"))
        XCTAssertTrue(result.stdout.contains("unsupported until runtime support is implemented"))
    }

    private func recipe() -> Recipe {
        Recipe(
            id: "tool",
            name: "Tool",
            category: "cli",
            path: nil,
            source: Source(kind: .custom, ref: "tool", branch: nil),
            versionScheme: .semver,
            check: .command("printf 'tool 1.0.0'"),
            latest: LatestSpec(strategy: .cmd, cmd: "printf 'tool 1.1.0'", pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: "printf updated", cwd: nil),
            pin: nil,
            enabled: true,
            notify: true,
            trust: Trust(level: .untrusted, approvedCommands: [:])
        )
    }

    private struct ValidationPayload: Decodable {
        var valid: Bool
        var errors: [String]
    }
}
