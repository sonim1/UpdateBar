import Foundation
import UpdateBarCore

struct InitPayload: Encodable {
    var ok: Bool
    var added: [String]
    var replaced: [String]
    var skipped: [String]
    var errors: [String]

    init(summary: InitSummary, errors: [String]) {
        self.ok = errors.isEmpty
        self.added = summary.added
        self.replaced = summary.replaced
        self.skipped = summary.skipped
        self.errors = errors
    }

    init(added: [String], replaced: [String], skipped: [String], errors: [String]) {
        self.ok = errors.isEmpty
        self.added = added
        self.replaced = replaced
        self.skipped = skipped
        self.errors = errors
    }
}

struct BackgroundInstallPayload: Encodable {
    var ok: Bool
    var installed: Bool
    var path: String
}

struct BackgroundStatusPayload: Encodable {
    var ok: Bool
    var installed: Bool
    var path: String
    var label: String
}

struct BackgroundUninstallPayload: Encodable {
    var ok: Bool
    var removed: Bool
    var path: String
}

struct ValidationPayload: Encodable {
    var ok: Bool
    var valid: Bool
    var errors: [String]
    var explanations: [ValidationExplanation]?
}

struct ValidationExplanation: Encodable {
    var error: String
    var hint: String

    init(error: String) {
        self.error = error
        if error.contains("version_parse.jq") {
            hint = "Use version_parse.regex. jq is not part of the executable recipe contract."
        } else if error.contains("version_parse.regex")
            && error.contains("expected exactly one capture group")
        {
            hint = "Use version_parse.regex with exactly one capture group around the version."
        } else {
            hint = "Fix the field shown in the error path and run validate again."
        }
    }
}

struct ConfigSetPayload: Encodable {
    var ok: Bool
    var key: String
    var value: String
}

struct ConfigValuePayload: Encodable {
    var key: String
    var value: String
}

struct ConfigDumpPayload: Encodable {
    var refresh: Refresh
    var security: Security

    init(config: Config) {
        refresh = Refresh(interval: config.refresh.interval.description)
        security = Security(requireHTTPSSource: config.security.requireHTTPSSource)
    }

    struct Refresh: Encodable {
        var interval: String
    }

    struct Security: Encodable {
        var requireHTTPSSource: Bool

        enum CodingKeys: String, CodingKey {
            case requireHTTPSSource = "require_https_source"
        }
    }
}

struct ItemMutationPayload: Encodable {
    var ok: Bool
    var id: String
    var item: Recipe
}

struct ApprovalMutationPayload: Encodable {
    var ok: Bool
    var id: String
    var field: String?
    var item: Recipe
}

struct RemovePayload: Encodable {
    var ok: Bool
    var id: String
    var removed: Bool
}

struct ImportPayload: Encodable {
    var ok: Bool
    var added: [String]
    var replaced: [String]
    var errors: [String]

    init(summary: ImportSummary, errors: [String]) {
        self.ok = errors.isEmpty
        self.added = summary.added
        self.replaced = summary.replaced
        self.errors = errors
    }

    init(added: [String], replaced: [String], errors: [String]) {
        self.ok = errors.isEmpty
        self.added = added
        self.replaced = replaced
        self.errors = errors
    }
}

struct AddPayload: Encodable {
    var ok: Bool
    var valid: Bool
    var recipe: Recipe?
    var errors: [String]
    var outcome: AddRecipeOutcome?

    init(valid: Bool, recipe: Recipe?, errors: [String], outcome: AddRecipeOutcome? = nil) {
        self.ok = valid
        self.valid = valid
        self.recipe = recipe
        self.errors = errors
        self.outcome = outcome
    }
}
