import ArgumentParser
import Foundation
import UpdateBarCore

struct GuideCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "guide",
        abstract: "Print guides for automation and recipe authoring.",
        shouldDisplay: false,
        subcommands: [Agent.self, Recipe.self]
    )

    struct Agent: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "agent",
            abstract: "Print the safe automation workflow."
        )

        func run() throws {
            writeStdout(
                """
                UpdateBar agent guide
                =====================

                UpdateBar tracks tools using recipe JSON.
                Recipes may contain shell commands. Treat those commands as sensitive.

                Safe workflow:
                1. Inspect contract: updatebar schema and updatebar guide recipe.
                2. Start from a template: updatebar template recipe --kind npm --id my-tool --source my-tool.
                3. Validate: updatebar validate recipe.json --json --explain.
                4. Dry-run add: updatebar add --from recipe.json --dry-run --json.
                5. Add untrusted: updatebar add --from recipe.json --json.
                6. Show every command field with updatebar approvals <id> --json.
                7. Do not approve commands silently.
                8. After user confirmation, approve exact fields:
                   Repeat approval for each command field the user accepts.
                   Common fields: check.cmd, latest.cmd, update.cmd.
                   updatebar approve <id> --field check.cmd --json.
                   updatebar approve <id> --field latest.cmd --json.
                   updatebar approve <id> --field update.cmd --json.
                9. Verify with updatebar check <id> --json and updatebar status --json.

                Exit codes:
                0 success
                1 usage/config/validation error
                2 partial update failure
                3 update blocked on command approval
                10 outdated items exist for check/status

                Never store provider/API secrets in recipes.
                """
            )
        }
    }

    struct Recipe: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "recipe",
            abstract: "Print recipe authoring guidance."
        )

        func run() throws {
            writeStdout(
                """
                Recipe authoring
                ================

                Required fields:
                id, name, category, source, version_scheme, check, latest,
                version_parse.regex, update, trust.

                Defaults: enabled=true, update.requires_write=true

                Rules:
                - use version_parse.regex with exactly one capture group
                - check.file reads local file content and parses it with version_parse.regex
                - latest.strategy cmd and all update commands require explicit approval
                - imported recipes should stay untrusted until a user reviews commands
                - Literal API keys and token values are rejected; reference environment variables instead

                Start with:
                updatebar schema
                updatebar template recipe --kind npm --id my-tool --source my-tool
                updatebar validate recipe.json --json --explain
                """
            )
        }
    }
}

struct SchemaCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Print the recipe JSON schema.",
        shouldDisplay: false
    )

    func run() throws {
        writeStdout(Self.recipeSchema)
    }

    private static let recipeSchema = """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "UpdateBar manifest",
      "type": "object",
      "required": ["schema_version", "items", "provenance"],
      "properties": {
        "schema_version": { "const": 1 },
        "items": {
          "type": "array",
          "items": { "$ref": "#/$defs/recipe" }
        },
        "provenance": {
          "type": "object",
          "required": ["created_by", "created_at", "updated_at"],
          "properties": {
            "created_by": { "type": "string", "minLength": 1 },
            "created_at": { "type": "string", "format": "date-time" },
            "updated_at": { "type": "string", "format": "date-time" }
          }
        }
      },
      "$defs": {
        "recipe": {
          "type": "object",
          "required": ["id", "name", "category", "source", "version_scheme", "check", "latest", "version_parse", "update", "trust"],
          "properties": {
            "id": { "type": "string", "pattern": "^[a-z0-9][a-z0-9._-]*$" },
            "name": { "type": "string", "minLength": 1 },
            "category": { "type": "string", "minLength": 1 },
            "path": { "type": ["string", "null"] },
            "source": {
              "type": "object",
              "required": ["kind", "ref"],
              "properties": {
                "kind": { "enum": ["git", "npm", "github_release", "brew", "http", "custom"] },
                "ref": { "type": "string", "minLength": 1 },
                "branch": { "type": ["string", "null"] }
              }
            },
            "version_scheme": { "enum": ["semver", "commit", "calver", "opaque"] },
            "check": {
              "type": "object",
              "oneOf": [
                { "required": ["cmd"] },
                { "required": ["file"] }
              ],
              "properties": {
                "cmd": { "type": "string", "minLength": 1 },
                "file": { "type": "string", "minLength": 1 }
              }
            },
            "latest": {
              "type": "object",
              "required": ["strategy"],
              "properties": {
                "strategy": { "enum": ["git_tags", "git_head", "npm_registry", "github_release", "brew", "http_regex", "cmd"] },
                "cmd": { "type": ["string", "null"] },
                "pattern": { "type": ["string", "null"] }
              }
            },
            "version_parse": {
              "type": "object",
              "required": ["regex"],
              "properties": {
                "regex": { "type": "string", "minLength": 1 }
              },
              "additionalProperties": false
            },
            "update": {
              "type": "object",
              "required": ["cmd"],
              "properties": {
                "cmd": { "type": "string", "minLength": 1 },
                "requires_write": { "type": "boolean", "default": true },
                "cwd": { "type": ["string", "null"] }
              }
            },
            "pin": { "type": ["string", "null"] },
            "enabled": { "type": "boolean", "default": true },
            "trust": {
              "type": "object",
              "required": ["level", "approved_commands"],
              "properties": {
                "level": { "enum": ["trusted", "untrusted"] },
                "approved_commands": {
                  "type": "object",
                  "propertyNames": {
                    "enum": ["check.cmd", "latest.cmd", "update.cmd"]
                  },
                  "additionalProperties": {
                    "type": "string",
                    "minLength": 71,
                    "maxLength": 71,
                    "pattern": "^sha256:[a-f0-9]{64}$"
                  }
                }
              }
            }
          }
        }
      }
    }
    """
}

struct TemplateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "template",
        abstract: "Print recipe or manifest JSON templates.",
        shouldDisplay: false,
        subcommands: [RecipeTemplate.self, ManifestTemplate.self]
    )

    struct RecipeTemplate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "recipe",
            abstract: "Print a single recipe JSON template."
        )

        @Option(name: .long, help: "Template kind: github_release, npm, brew, git_tags, http_regex, or custom_command.")
        var kind: TemplateKind

        @Option(name: .long, help: "Recipe id to use in the template.")
        var id: String?

        @Option(name: .long, help: "Display name to use in the template.")
        var name: String?

        @Option(name: .long, help: "Source reference to use in the template.")
        var source: String?

        func run() throws {
            try validateTemplateOverrides(id: id, name: name, source: source)
            try printJSON(kind.recipe(id: id, name: name, sourceRef: source))
        }
    }

    struct ManifestTemplate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "manifest",
            abstract: "Print a manifest JSON template with one recipe."
        )

        @Option(name: .long, help: "Template kind: github_release, npm, brew, git_tags, http_regex, or custom_command.")
        var kind: TemplateKind

        @Option(name: .long, help: "Recipe id to use in the template.")
        var id: String?

        @Option(name: .long, help: "Display name to use in the template.")
        var name: String?

        @Option(name: .long, help: "Source reference to use in the template.")
        var source: String?

        func run() throws {
            try validateTemplateOverrides(id: id, name: name, source: source)
            let now = Date()
            let manifest = Manifest(
                schemaVersion: 1,
                items: [kind.recipe(id: id, name: name, sourceRef: source)],
                provenance: Provenance(createdBy: "updatebar", createdAt: now, updatedAt: now)
            )
            try printJSON(manifest)
        }
    }
}

private func validateTemplateOverrides(id: String?, name: String?, source: String?) throws {
    let values = [id, name, source].compactMap(\.self)
    guard values.allSatisfy({ SecretRedactor.redact($0) == $0 }) else {
        throw ValidationError("template override must not contain literal secrets")
    }
    if let id, !isValidTemplateID(id) {
        throw ValidationError("template --id must match ^[a-z0-9][a-z0-9._-]*$")
    }
}

private func isValidTemplateID(_ id: String) -> Bool {
    guard let first = id.unicodeScalars.first,
          isLowercaseLetterOrDigit(first)
    else {
        return false
    }
    return id.unicodeScalars.allSatisfy { scalar in
        isLowercaseLetterOrDigit(scalar) || scalar == "." || scalar == "_" || scalar == "-"
    }
}

private func isLowercaseLetterOrDigit(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 48...57, 97...122:
        return true
    default:
        return false
    }
}

enum TemplateKind: String, ExpressibleByArgument {
    case githubRelease = "github_release"
    case npm
    case brew
    case gitTags = "git_tags"
    case httpRegex = "http_regex"
    case customCommand = "custom_command"

    func recipe(
        id requestedID: String? = nil,
        name requestedName: String? = nil,
        sourceRef requestedSourceRef: String? = nil
    ) -> Recipe {
        switch self {
        case .githubRelease:
            return base(
                id: requestedID ?? "example-github-tool",
                name: requestedName,
                source: Source(kind: .githubRelease, ref: requestedSourceRef ?? "owner/repo", branch: nil),
                latest: LatestSpec(strategy: .githubRelease, cmd: nil, pattern: nil),
                update: "brew upgrade \(ShellQuote.single(requestedID ?? "example-github-tool"))"
            )
        case .npm:
            let package = requestedSourceRef ?? requestedID ?? "example-npm-tool"
            return base(
                id: requestedID ?? "example-npm-tool",
                name: requestedName,
                source: Source(kind: .npm, ref: package, branch: nil),
                latest: LatestSpec(strategy: .npmRegistry, cmd: nil, pattern: nil),
                update: "npm install -g \(ShellQuote.single(package))@latest"
            )
        case .brew:
            let formula = requestedSourceRef ?? requestedID ?? "example-brew-tool"
            return base(
                id: requestedID ?? "example-brew-tool",
                name: requestedName,
                source: Source(kind: .brew, ref: formula, branch: nil),
                latest: LatestSpec(strategy: .brew, cmd: nil, pattern: nil),
                update: "brew upgrade \(ShellQuote.single(formula))"
            )
        case .gitTags:
            return base(
                id: requestedID ?? "example-git-tool",
                name: requestedName,
                source: Source(kind: .git, ref: requestedSourceRef ?? "https://github.com/owner/repo.git", branch: nil),
                latest: LatestSpec(strategy: .gitTags, cmd: nil, pattern: nil),
                update: "git -C /path/to/repo pull --ff-only"
            )
        case .httpRegex:
            return base(
                id: requestedID ?? "example-http-tool",
                name: requestedName,
                source: Source(kind: .http, ref: requestedSourceRef ?? "https://example.com/releases", branch: nil),
                latest: LatestSpec(
                    strategy: .httpRegex,
                    cmd: nil,
                    pattern: #"version">([0-9]+\.[0-9]+\.[0-9]+)<"#
                ),
                update: "brew upgrade \(ShellQuote.single(requestedID ?? "example-http-tool"))"
            )
        case .customCommand:
            return base(
                id: requestedID ?? "example-command-tool",
                name: requestedName,
                source: Source(kind: .custom, ref: requestedSourceRef ?? requestedID ?? "example-command-tool", branch: nil),
                latest: LatestSpec(strategy: .cmd, cmd: "\(requestedID ?? "example-tool") --latest-version", pattern: nil),
                update: "\(requestedID ?? "example-tool") self-update"
            )
        }
    }

    private func base(id: String, name: String?, source: Source, latest: LatestSpec, update: String) -> Recipe {
        Recipe(
            id: id,
            name: name ?? id.replacingOccurrences(of: "-", with: " ").capitalized,
            category: "devtools",
            path: nil,
            source: source,
            versionScheme: .semver,
            check: .command("\(id) --version"),
            latest: latest,
            versionParse: .regex("([0-9]+\\.[0-9]+\\.[0-9]+)"),
            update: UpdateSpec(cmd: update, cwd: nil),
            pin: nil,
            enabled: true,
            trust: Trust(level: .untrusted, approvedCommands: [:])
        )
    }
}
