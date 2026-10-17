import Foundation
import UpdateBarCore
import UpdateBarTestSupport
import XCTest

final class BrewScanVersionTests: XCTestCase {
    func testScannedBrewRecipesSkipDigitsInFormulaNamesWhenCheckingVersions() throws {
        for (name, version) in [
            ("node@22", "22.22.0"),
            ("python@3.13", "3.13.7"),
            ("e2e-fixture", "1.0.0"),
        ] {
            let output = "\(name) \(version)\n"
            let recipe = try scannedRecipe(output: output)
            XCTAssertEqual(
                try VersionParser.extract(from: output, using: recipe.versionParse),
                version,
                "Installed version must come after the complete formula name: \(name)"
            )
        }
    }

    func testScannedBrewRecipesKeepRevisionSuffixesForUnversionedNames() throws {
        let output = "jq 1.7.1_2\n"
        let recipe = try scannedRecipe(output: output)
        XCTAssertEqual(
            try VersionParser.extract(from: output, using: recipe.versionParse), "1.7.1_2")
    }

    private func scannedRecipe(output: String) throws -> Recipe {
        let commands = MockCommandExecutor(results: [
            ScanService.brewListCommand: CommandResult(exitCode: 0, stdout: output, stderr: "")
        ])
        let service = ScanService(
            commandRunner: commands,
            homeDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString)
        )
        let report = try service.scan(detectors: [.brew])
        XCTAssertEqual(report.errors, [])
        XCTAssertEqual(report.candidates.count, 1)
        return try XCTUnwrap(report.candidates.first?.recipe)
    }
}
