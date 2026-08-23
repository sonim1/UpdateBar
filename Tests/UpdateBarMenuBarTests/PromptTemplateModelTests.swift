import UpdateBarMenuBar
import XCTest

final class PromptTemplateModelTests: XCTestCase {
    func testCatalogExposesSixTemplatesInTaskOrder() {
        XCTAssertEqual(
            PromptTemplateCatalog.templates.map(\.id),
            [
                .inspectCLI,
                .checkUpdates,
                .addItem,
                .reviewApprove,
                .updateApproved,
                .diagnose,
            ]
        )
        XCTAssertEqual(
            Set(PromptTemplateCatalog.templates.map(\.category)),
            Set(PromptTemplateCategory.allCases)
        )
        XCTAssertTrue(PromptTemplateCatalog.templates.allSatisfy { !$0.title.isEmpty })
        XCTAssertTrue(PromptTemplateCatalog.templates.allSatisfy { !$0.boundary.isEmpty })
    }

    func testInspectCLIPromptStaysReadOnlyAndUsesOptionalContext() throws {
        let template = try template(.inspectCLI)

        let generic = template.prompt(values: [:])
        XCTAssertTrue(generic.contains("updatebar --help"))
        XCTAssertTrue(generic.contains("updatebar guide agent"))
        XCTAssertTrue(generic.contains("Do not modify"))

        let focused = template.prompt(values: [
            .focus: " approval commands ",
            .output: " concise bullets ",
        ])
        XCTAssertTrue(focused.contains("approval commands"))
        XCTAssertTrue(focused.contains("concise bullets"))
    }

    func testCheckUpdatesPromptUsesPlaceholderForWhitespaceAndSubstitutesItem() throws {
        let template = try template(.checkUpdates)

        let generic = template.prompt(values: [.itemName: "   "])
        XCTAssertTrue(generic.contains("[ITEM_ID_OR_ALL]"))
        XCTAssertTrue(generic.contains("Do not install or update anything"))

        let focused = template.prompt(values: [.itemName: "ripgrep"])
        XCTAssertTrue(focused.contains("ripgrep"))
        XCTAssertFalse(focused.contains("[ITEM_ID_OR_ALL]"))
    }

    func testAddItemPromptSubstitutesValuesAndRequiresConfirmation() throws {
        let template = try template(.addItem)

        let generic = template.prompt(values: [:])
        XCTAssertTrue(generic.contains("[ITEM_NAME]"))
        XCTAssertTrue(generic.contains("[SOURCE]"))
        XCTAssertTrue(generic.contains("wait for my explicit confirmation"))

        let filled = template.prompt(values: [
            .itemName: " ripgrep ",
            .source: " BurntSushi/ripgrep ",
        ])
        XCTAssertTrue(filled.contains("ripgrep"))
        XCTAssertTrue(filled.contains("BurntSushi/ripgrep"))
        XCTAssertFalse(filled.contains("[ITEM_NAME]"))
        XCTAssertFalse(filled.contains("[SOURCE]"))
        XCTAssertTrue(filled.contains("verify the saved item"))
    }

    func testApprovalPromptRequiresExactFieldReviewAndNoSilentApproval() throws {
        let template = try template(.reviewApprove)
        let prompt = template.prompt(values: [
            .itemName: "ripgrep",
            .commandField: "update.cmd",
        ])

        XCTAssertTrue(prompt.contains("updatebar approvals ripgrep --json"))
        XCTAssertTrue(prompt.contains("update.cmd"))
        XCTAssertTrue(prompt.contains("Do not approve anything silently"))
        XCTAssertTrue(prompt.contains("separate explicit confirmation"))
    }

    func testUpdatePromptPreservesApprovalBoundary() throws {
        let template = try template(.updateApproved)
        let prompt = template.prompt(values: [
            .itemName: "ripgrep",
            .scope: "one item",
        ])

        XCTAssertTrue(prompt.contains("already approved and outdated"))
        XCTAssertTrue(prompt.contains("Do not bypass approval checks"))
        XCTAssertTrue(prompt.contains("wait for my explicit confirmation"))
        XCTAssertTrue(prompt.contains("verify the result"))
    }

    func testDiagnosePromptStartsReadOnlyAndRequestsSecretRedaction() throws {
        let template = try template(.diagnose)
        let prompt = template.prompt(values: [
            .symptom: "check exits with code 1",
            .itemName: "ripgrep",
        ])

        XCTAssertTrue(prompt.contains("updatebar doctor"))
        XCTAssertTrue(prompt.contains("Begin with read-only diagnosis"))
        XCTAssertTrue(prompt.contains("Redact secrets"))
        XCTAssertTrue(prompt.contains("Do not change configuration"))
        XCTAssertTrue(prompt.contains("check exits with code 1"))
    }

    private func template(_ id: PromptTemplateID) throws -> PromptTemplateDefinition {
        try XCTUnwrap(PromptTemplateCatalog.template(id: id))
    }
}
