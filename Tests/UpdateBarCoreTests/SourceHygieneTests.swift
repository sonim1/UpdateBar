import Foundation
import XCTest

final class SourceHygieneTests: XCTestCase {
    func testProductionSourcesAvoidForceUnwrapSyntax() throws {
        let sourceRoot = URL(fileURLWithPath: "Sources")
        let sourceFiles = try swiftSourceFiles(under: sourceRoot)
        var violations: [String] = []

        for file in sourceFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if line.contains("!.")
                    || line.contains(")!")
                    || line.contains("try!")
                    || line.contains(" as!")
                {
                    violations.append("\(file.path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertEqual(
            violations,
            [],
            "Production sources should throw typed errors instead of force-unwrapping:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testCLISourcesRouteHumanStdoutThroughOutputHelpers() throws {
        let sourceRoot = URL(fileURLWithPath: "Sources/UpdateBarCLI")
        let sourceFiles = try swiftSourceFiles(under: sourceRoot)
            .filter { $0.lastPathComponent != "CLIOutput.swift" }
        var violations: [String] = []

        for file in sourceFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.contains("print(")
            {
                violations.append("\(file.path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        XCTAssertEqual(
            violations,
            [],
            "Human CLI stdout should use writeStdout so redaction stays centralized:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testCLISourcesUseSharedShellQuotingHelper() throws {
        let sourceRoot = URL(fileURLWithPath: "Sources/UpdateBarCLI")
        let sourceFiles = try swiftSourceFiles(under: sourceRoot)
        var violations: [String] = []

        for file in sourceFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.contains("replacingOccurrences(of: \"'\", with:")
            {
                violations.append("\(file.path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        XCTAssertEqual(
            violations,
            [],
            "CLI shell command templates should use UpdateBarCore.ShellQuote instead of local quoting copies:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testCLIMutationJSONPayloadsUseRedactedHelpers() throws {
        let sourceRoot = URL(fileURLWithPath: "Sources/UpdateBarCLI")
        let sourceFiles = try swiftSourceFiles(under: sourceRoot)
            .filter { $0.lastPathComponent != "CLIPayloads.swift" }
        var violations: [String] = []

        for file in sourceFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.contains("ItemMutationPayload(ok:")
                    || line.contains("ApprovalMutationPayload(ok:")
            {
                violations.append("\(file.path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        XCTAssertEqual(
            violations,
            [],
            "CLI mutation JSON should use redacted payload helpers instead of embedding Recipe values directly:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testCLIMutationHumanOutputDoesNotPrintRawRecipeIDs() throws {
        let sourceRoot = URL(fileURLWithPath: "Sources/UpdateBarCLI")
        let sourceFiles = try swiftSourceFiles(under: sourceRoot)
        var violations: [String] = []

        for file in sourceFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.contains("writeStdout(")
                    && (line.contains("\\(recipe.id")
                        || line.contains("edited \\(id)"))
            {
                violations.append("\(file.path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        XCTAssertEqual(
            violations,
            [],
            "CLI human mutation output should redact Recipe ids before printing:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testRegistryApprovalRequiresExplicitCommandField() throws {
        let file = URL(fileURLWithPath: "Sources/UpdateBarCore/Registry/RegistryService.swift")
        let contents = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(contents.contains("public func approve(id: String, field: String) throws -> Recipe"))
        XCTAssertFalse(contents.contains("field: String? = nil"))
        XCTAssertFalse(contents.contains("approveAllCommands(in: &recipe)"))
    }

    func testCoreDoesNotExposeLegacyCommandApprovalStore() {
        let file = URL(fileURLWithPath: "Sources/UpdateBarCore/Execution/CommandApprovalStore.swift")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "CommandApprovalStore should not re-expose broad command approval APIs."
        )
    }

    func testTrustPolicyDoesNotExposeBroadApprovalMutation() throws {
        let file = URL(fileURLWithPath: "Sources/UpdateBarCore/Security/TrustPolicy.swift")
        let contents = try String(contentsOf: file, encoding: .utf8)

        XCTAssertFalse(
            contents.contains("approveAllCommands"),
            "Broad approve-all mutation helpers belong in UpdateBarTestSupport, not production TrustPolicy."
        )
    }

    func testPackageDoesNotPublishTestSupportProduct() throws {
        let contents = try String(contentsOfFile: "Package.swift", encoding: .utf8)

        XCTAssertFalse(
            contents.contains(#".library(name: "UpdateBarTestSupport""#),
            "UpdateBarTestSupport should stay an internal test target dependency, not a published package product."
        )
    }

    func testPackageDoesNotPublishInternalMenuBarLibraryProduct() throws {
        let contents = try String(contentsOfFile: "Package.swift", encoding: .utf8)

        XCTAssertFalse(
            contents.contains(#".library(name: "UpdateBarMenuBar""#),
            "UpdateBarMenuBar should stay an internal target behind the updatebar-menubar executable product."
        )
    }

    func testCLICategoryHelpUsesSharedDescription() throws {
        let sourceRoot = URL(fileURLWithPath: "Sources/UpdateBarCLI")
        let sourceFiles = try swiftSourceFiles(under: sourceRoot)
            .filter { $0.lastPathComponent != "CLIWorkflowSupport.swift" }
        var violations: [String] = []

        for file in sourceFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.contains("ai-agent, package-manager")
            {
                violations.append("\(file.path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        XCTAssertEqual(
            violations,
            [],
            "CLI category help should use scanCategoryDescription() instead of duplicating the category list:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testCLIScanCategoryMetadataComesFromCore() throws {
        let file = URL(fileURLWithPath: "Sources/UpdateBarCLI/CLIWorkflowSupport.swift")
        let contents = try String(contentsOf: file, encoding: .utf8)

        XCTAssertFalse(contents.contains("let supportedScanCategories"))
        XCTAssertFalse(contents.contains("let scanCategoryCompletionValues"))
        XCTAssertFalse(contents.contains("func defaultScanDetectors"))
        XCTAssertTrue(contents.contains("ScanCategory."))
    }

    func testTemplateKindHelpUsesEnumCases() throws {
        let file = URL(fileURLWithPath: "Sources/UpdateBarCLI/CLIDocumentCommands.swift")
        let contents = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(contents.contains("enum TemplateKind: String, CaseIterable, ExpressibleByArgument"))
        XCTAssertTrue(contents.contains("TemplateKind.helpDescription"))
        XCTAssertFalse(contents.contains("Template kind: github_release, npm, brew"))
    }

    private func swiftSourceFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            XCTFail("Could not enumerate \(root.path)")
            return []
        }

        return try enumerator.compactMap { entry in
            guard let url = entry as? URL, url.pathExtension == "swift" else {
                return nil
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }.sorted { $0.path < $1.path }
    }
}
