import Foundation
import XCTest
import UpdateBarCore

final class InitServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800)

    func testRegisterDoesNotPartiallySaveWhenSelectedRecipeIsInvalid() throws {
        let root = try temporaryDirectory()
        let paths = AppPaths(homeDirectory: root)
        let service = InitService(registryService: RegistryService(
            manifestStore: ManifestStore(paths: paths),
            stateStore: StateStore(paths: paths),
            now: { self.now }
        ))
        let secret = "sk-or-v1-secret-value"
        let good = candidate(recipe(id: "good"))
        var invalidRecipe = recipe(id: "bad")
        invalidRecipe.update.cmd = "OPENROUTER_API_KEY=\(secret) bad update"
        let bad = candidate(invalidRecipe)

        XCTAssertThrowsError(try service.register(
            candidates: [good, bad],
            selectedIDs: ["good", "bad"],
            replace: false
        )) { error in
            guard case let RegistryError.invalidManifest(errors) = error else {
                return XCTFail("expected invalid manifest, got \(error)")
            }
            XCTAssertTrue(errors.contains("items[1].update.cmd: must not contain literal secrets"))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.manifestFile.path))
        XCTAssertTrue(try ManifestStore(paths: paths).loadExistingOrEmpty().items.isEmpty)
    }

    func testInitServiceErrorDescriptionsRedactSecretLikeValues() {
        let secret = "sk-or-v1-secret-value"
        let error = InitServiceError.invalidSelection([
            "\(secret): not found",
            "tool: not importable (\(secret))"
        ])

        let message = String(describing: error)

        XCTAssertTrue(message.contains("[REDACTED]"))
        XCTAssertFalse(message.contains(secret))
    }

    private func candidate(_ recipe: Recipe) -> ScanCandidate {
        ScanCandidate(
            id: recipe.id,
            name: recipe.name,
            detector: .known,
            category: recipe.category,
            capability: .full,
            confidence: .high,
            installedVersion: nil,
            sourceRef: recipe.source.ref,
            recipe: recipe
        )
    }

    private func recipe(id: String) -> Recipe {
        var item = Recipe(
            id: id,
            name: id,
            category: "cli",
            path: nil,
            source: Source(kind: .custom, ref: id, branch: nil),
            versionScheme: .semver,
            check: .command("\(id) current"),
            latest: LatestSpec(strategy: .cmd, cmd: "\(id) latest", pattern: nil),
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: "\(id) update", cwd: nil),
            pin: nil,
            enabled: true,
            trust: Trust(level: .trusted, approvedCommands: [:])
        )
        TrustPolicy.approveAllCommands(in: &item)
        return item
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-init-service-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
