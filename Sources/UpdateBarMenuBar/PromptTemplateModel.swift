import Foundation

public enum PromptTemplateCategory: String, CaseIterable, Sendable {
    case discover
    case configure
    case operate

    public var title: String {
        rawValue.capitalized
    }
}

public enum PromptTemplateID: String, CaseIterable, Sendable {
    case inspectCLI
    case checkUpdates
    case addItem
    case reviewApprove
    case updateApproved
    case diagnose
}

public enum PromptTemplateFieldKey: String, Sendable {
    case focus
    case output
    case itemName
    case source
    case commandField
    case scope
    case symptom
}

public struct PromptTemplateField: Equatable, Sendable {
    public let key: PromptTemplateFieldKey
    public let label: String
    public let placeholder: String

    public init(key: PromptTemplateFieldKey, label: String, placeholder: String) {
        self.key = key
        self.label = label
        self.placeholder = placeholder
    }
}

public struct PromptTemplateDefinition: Equatable, Sendable {
    public let id: PromptTemplateID
    public let category: PromptTemplateCategory
    public let title: String
    public let systemImageName: String
    public let summary: String
    public let boundary: String
    public let fields: [PromptTemplateField]

    public init(
        id: PromptTemplateID,
        category: PromptTemplateCategory,
        title: String,
        systemImageName: String,
        summary: String,
        boundary: String,
        fields: [PromptTemplateField]
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.systemImageName = systemImageName
        self.summary = summary
        self.boundary = boundary
        self.fields = fields
    }

    public func prompt(values: [PromptTemplateFieldKey: String]) -> String {
        switch id {
        case .inspectCLI:
            let focus = value(.focus, in: values, fallback: "the complete CLI surface")
            let output = value(.output, in: values, fallback: "a concise structured summary")
            return """
                Inspect the installed UpdateBar CLI without changing any UpdateBar or system state.

                1. Run `updatebar --version`, `updatebar --help`, and `updatebar guide agent`.
                2. Focus on \(focus).
                3. Explain the supported commands, machine-readable output, exit codes, and approval boundaries.
                4. Return \(output), including the exact read-only commands you ran.

                Do not modify configuration, recipes, approvals, or installed tools.
                """
        case .checkUpdates:
            let item = value(.itemName, in: values, fallback: "[ITEM_ID_OR_ALL]")
            let output = value(.output, in: values, fallback: "JSON-backed summary")
            return """
                Use the installed UpdateBar CLI to check update status for \(item).

                1. Inspect `updatebar check --help` and read saved state with `updatebar status --json`.
                2. Run the appropriate `updatebar check` command for \(item) using JSON output.
                3. Treat exit code 10 as "outdated items found," not as an execution failure.
                4. Report current version, latest version, item status, and any approval requirement as a \(output).

                Do not install or update anything, change configuration, or approve commands.
                """
        case .addItem:
            let item = value(.itemName, in: values, fallback: "[ITEM_NAME]")
            let source = value(.source, in: values, fallback: "[SOURCE]")
            return """
                Use the installed UpdateBar CLI to prepare adding \(item) from \(source).

                1. Read `updatebar guide agent`, `updatebar guide recipe`, and `updatebar schema` first.
                2. Generate the smallest valid recipe for this source and validate it with `updatebar validate`.
                3. Run `updatebar add --from <recipe-file> --dry-run --json` and explain every command field and trust implication.
                4. Show the exact non-dry-run command and wait for my explicit confirmation before adding anything.
                5. After confirmation, add the recipe as untrusted, then verify the saved item with `updatebar status --json`.

                Do not approve command fields automatically. Redact secrets from all output.
                """
        case .reviewApprove:
            let item = value(.itemName, in: values, fallback: "[ITEM_ID]")
            let field = value(
                .commandField,
                in: values,
                fallback: "[ALL_UNAPPROVED_FIELDS]"
            )
            return """
                Review UpdateBar command approval for \(item), focusing on \(field).

                1. Run `updatebar approvals \(item) --json` and inspect every exact command, working directory, fingerprint, and approval state.
                2. Explain what each requested field does, why it is needed, and its security risk.
                3. Show the exact `updatebar approve \(item) --field <field> --json` command for each field under review.
                4. Get separate explicit confirmation before each approval command, then verify with `updatebar approvals \(item) --json`.

                Do not approve anything silently, approve unrelated fields, or treat one confirmation as approval for every field.
                """
        case .updateApproved:
            let item = value(.itemName, in: values, fallback: "[ITEM_ID_OR_ALL]")
            let scope = value(.scope, in: values, fallback: "the requested item scope")
            return """
                Use the installed UpdateBar CLI to update \(item), limited to \(scope).

                1. Read `updatebar update --help`, then use `updatebar status --json` to confirm every target is already approved and outdated.
                2. Exclude current, disabled, pinned, untrusted, or approval-blocked items.
                3. Show the exact update command and targets, then wait for my explicit confirmation before execution.
                4. After confirmation, run the update with non-interactive JSON output and verify the result with `updatebar status --json`.

                Do not bypass approval checks, edit recipes, broaden the requested scope, or approve commands as part of this task. Summarize successes, skips, and failures separately.
                """
        case .diagnose:
            let symptom = value(.symptom, in: values, fallback: "[SYMPTOM_OR_ERROR]")
            let item = value(.itemName, in: values, fallback: "[ITEM_ID_IF_RELEVANT]")
            return """
                Diagnose this UpdateBar problem: \(symptom). Relevant item: \(item).

                Begin with read-only diagnosis. Inspect help, then run `updatebar doctor --json`, `updatebar status --json`, and only the relevant read-only history or approval commands.
                Explain the likely root cause, cite the evidence, and propose the smallest recovery command.

                Redact secrets, tokens, private paths, and sensitive environment values from all output. Do not change configuration, recipes, approvals, or installed tools unless I explicitly approve the exact proposed mutation.
                """
        }
    }

    private func value(
        _ key: PromptTemplateFieldKey,
        in values: [PromptTemplateFieldKey: String],
        fallback: String
    ) -> String {
        guard let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return fallback }
        return value
    }
}

public enum PromptTemplateCatalog {
    public static let templates: [PromptTemplateDefinition] = [
        PromptTemplateDefinition(
            id: .inspectCLI,
            category: .discover,
            title: "Inspect the CLI",
            systemImageName: "terminal",
            summary: "Read-only command and contract overview",
            boundary: "No mutations allowed",
            fields: [
                PromptTemplateField(
                    key: .focus,
                    label: "Focus area",
                    placeholder: "Optional"
                ),
                PromptTemplateField(
                    key: .output,
                    label: "Output preference",
                    placeholder: "Optional"
                ),
            ]
        ),
        PromptTemplateDefinition(
            id: .checkUpdates,
            category: .discover,
            title: "Check updates",
            systemImageName: "arrow.clockwise",
            summary: "Read-only status and version check",
            boundary: "Runs checks only",
            fields: [
                PromptTemplateField(
                    key: .itemName,
                    label: "Item ID",
                    placeholder: "All registered items"
                ),
                PromptTemplateField(
                    key: .output,
                    label: "Output preference",
                    placeholder: "Optional"
                ),
            ]
        ),
        PromptTemplateDefinition(
            id: .addItem,
            category: .configure,
            title: "Add an item",
            systemImageName: "plus",
            summary: "Build, validate, and preview a recipe",
            boundary: "Confirmation required",
            fields: [
                PromptTemplateField(
                    key: .itemName,
                    label: "Item name",
                    placeholder: "Required in final prompt"
                ),
                PromptTemplateField(
                    key: .source,
                    label: "Source URL or package",
                    placeholder: "Required in final prompt"
                ),
            ]
        ),
        PromptTemplateDefinition(
            id: .reviewApprove,
            category: .configure,
            title: "Review & approve",
            systemImageName: "checkmark.shield",
            summary: "Review exact command fields before trust",
            boundary: "Never auto-approves",
            fields: [
                PromptTemplateField(
                    key: .itemName,
                    label: "Item ID",
                    placeholder: "Required in final prompt"
                ),
                PromptTemplateField(
                    key: .commandField,
                    label: "Command field",
                    placeholder: "Optional"
                ),
            ]
        ),
        PromptTemplateDefinition(
            id: .updateApproved,
            category: .operate,
            title: "Update approved items",
            systemImageName: "arrow.down.circle",
            summary: "Run only eligible approved updates",
            boundary: "Confirmation required",
            fields: [
                PromptTemplateField(
                    key: .itemName,
                    label: "Item ID",
                    placeholder: "All approved outdated items"
                ),
                PromptTemplateField(
                    key: .scope,
                    label: "Scope preference",
                    placeholder: "Optional"
                ),
            ]
        ),
        PromptTemplateDefinition(
            id: .diagnose,
            category: .operate,
            title: "Diagnose issues",
            systemImageName: "wrench.and.screwdriver",
            summary: "Read-only diagnosis with redacted output",
            boundary: "Read-only diagnosis",
            fields: [
                PromptTemplateField(
                    key: .symptom,
                    label: "Symptom or error",
                    placeholder: "Required in final prompt"
                ),
                PromptTemplateField(
                    key: .itemName,
                    label: "Item ID",
                    placeholder: "Optional"
                ),
            ]
        ),
    ]

    public static func template(id: PromptTemplateID) -> PromptTemplateDefinition? {
        templates.first { $0.id == id }
    }
}
