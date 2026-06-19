import ArgumentParser
import Foundation
import UpdateBarCore
#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct UpdateBar: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "updatebar",
        abstract: "Track and update arbitrary registered tools.",
        subcommands: [
            AddCommand.self,
            ApprovalCommand.self,
            ApprovalsCommand.self,
            BackgroundCommand.self,
            CheckCommand.self,
            ConfigCommand.self,
            DisableCommand.self,
            EditCommand.self,
            EnableCommand.self,
            ExportCommand.self,
            GuideCommand.self,
            ImportCommand.self,
            ListCommand.self,
            PinCommand.self,
            RemoveCommand.self,
            RevokeCommand.self,
            SchemaCommand.self,
            StatusCommand.self,
            TemplateCommand.self,
            UnpinCommand.self,
            UpdateCommand.self,
            ValidateCommand.self,
            VersionCommand.self
        ]
    )
}

@main
enum UpdateBarMain {
    static func main() {
        do {
            var command = try UpdateBar.parseAsRoot()
            try command.run()
        } catch {
            let exitCode = UpdateBar.exitCode(for: error)
            if CommandLine.arguments.contains("--json"), !JSONOutputTracker.shared.didWrite {
                writeJSONError(error, code: exitCode)
                terminate(processExitCode(for: exitCode))
            }
            if exitCode == .validationFailure {
                let message = UpdateBar.fullMessage(for: error)
                if !message.isEmpty {
                    FileHandle.standardError.write(Data((message + "\n").utf8))
                }
                terminate(1)
            }
            UpdateBar.exit(withError: error)
        }
    }

    private static func writeJSONError(_ error: Error, code exitCode: ExitCode) {
        let message = UpdateBar.fullMessage(for: error).isEmpty
            ? String(describing: error)
            : UpdateBar.fullMessage(for: error)
        let payload = ErrorEnvelope(
            ok: false,
            code: errorCode(for: error, exitCode: exitCode),
            errors: [message]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(payload) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static func errorCode(for error: Error, exitCode: ExitCode) -> String {
        if error is ConfigError {
            return "config_error"
        }
        if error is RegistryError {
            return "registry_error"
        }
        if error is ValidationError {
            return "validation_error"
        }
        if error is DecodingError {
            return "decode_error"
        }
        if exitCode == .validationFailure {
            return "usage_error"
        }
        return "runtime_error"
    }

    private static func processExitCode(for exitCode: ExitCode) -> Int32 {
        exitCode == .validationFailure ? 1 : exitCode.rawValue
    }

    private static func terminate(_ code: Int32) -> Never {
#if os(Linux)
        Glibc.exit(code)
#else
        Darwin.exit(code)
#endif
    }
}

private struct ErrorEnvelope: Encodable {
    var ok: Bool
    var code: String
    var errors: [String]
}

struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "version")

    @Flag(name: .long)
    var json = false

    func run() throws {
        let payload = VersionPayload(version: UpdateBarVersion.current)
        if json {
            try printJSON(payload)
        } else {
            print(payload.version)
        }
    }
}

private struct VersionPayload: Encodable {
    var version: String
}

struct BackgroundCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "background",
        abstract: "Manage the opt-in background check LaunchAgent.",
        subcommands: [Install.self, Status.self, Uninstall.self]
    )

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "install")

        @Flag(name: .long)
        var yes = false

        @Flag(name: .long)
        var json = false

        @Option(name: .long)
        var intervalSeconds = 3600

        func run() throws {
#if os(macOS)
            guard yes else {
                throw ValidationError("background install requires --yes")
            }
            guard intervalSeconds > 0 else {
                throw ValidationError("interval-seconds must be greater than 0")
            }

            let manager = BackgroundLaunchAgentManager()
            let url = try manager.install(intervalSeconds: intervalSeconds)
            let payload = BackgroundInstallPayload(ok: true, installed: true, path: url.path)
            if json {
                try printJSON(payload)
            } else {
                print("installed \(url.path)")
            }
#else
            throw ValidationError("background helper is only supported on macOS")
#endif
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "status")

        @Flag(name: .long)
        var json = false

        func run() throws {
#if os(macOS)
            let manager = BackgroundLaunchAgentManager()
            let payload = BackgroundStatusPayload(
                ok: true,
                installed: manager.isInstalled,
                path: manager.plistURL.path,
                label: BackgroundLaunchAgentManager.label
            )
            if json {
                try printJSON(payload)
            } else {
                print(payload.installed ? "installed" : "not installed")
            }
#else
            throw ValidationError("background helper is only supported on macOS")
#endif
        }
    }

    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "uninstall")

        @Flag(name: .long)
        var json = false

        func run() throws {
#if os(macOS)
            let manager = BackgroundLaunchAgentManager()
            let removed = try manager.uninstall()
            let payload = BackgroundUninstallPayload(ok: true, removed: removed, path: manager.plistURL.path)
            if json {
                try printJSON(payload)
            } else {
                print(removed ? "uninstalled" : "not installed")
            }
#else
            throw ValidationError("background helper is only supported on macOS")
#endif
        }
    }
}

private struct BackgroundLaunchAgentManager {
    static let label = "com.updatebar.check"

    private let environment: [String: String]
    private let fileManager: FileManager

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.fileManager = fileManager
    }

    var plistURL: URL {
        userHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.label).plist", isDirectory: false)
    }

    var isInstalled: Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    func install(intervalSeconds: Int) throws -> URL {
        let directory = plistURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let plist = BackgroundLaunchAgentPlist(
            label: Self.label,
            programArguments: [
                executablePath,
                "check",
                "--exit-zero-on-outdated"
            ],
            startInterval: intervalSeconds,
            runAtLoad: true,
            environmentVariables: ["UPDATEBAR_HOME": AppPaths(environment: environment).homeDirectory.path]
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(plist)
        try data.write(to: plistURL, options: [.atomic])
        return plistURL
    }

    func uninstall() throws -> Bool {
        guard isInstalled else {
            return false
        }
        try fileManager.removeItem(at: plistURL)
        return true
    }

    private var userHome: URL {
        if let home = environment["HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    private var executablePath: String {
        let argument = CommandLine.arguments[0]
        if argument.hasPrefix("/") {
            return URL(fileURLWithPath: argument).standardizedFileURL.path
        }
        if argument.contains("/") {
            return URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent(argument).standardizedFileURL.path
        }
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(argument)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate.standardizedFileURL.path
            }
        }
        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent(argument).standardizedFileURL.path
    }
}

private struct BackgroundLaunchAgentPlist: Encodable {
    var label: String
    var programArguments: [String]
    var startInterval: Int
    var runAtLoad: Bool
    var environmentVariables: [String: String]

    enum CodingKeys: String, CodingKey {
        case label = "Label"
        case programArguments = "ProgramArguments"
        case startInterval = "StartInterval"
        case runAtLoad = "RunAtLoad"
        case environmentVariables = "EnvironmentVariables"
    }
}

private struct BackgroundInstallPayload: Encodable {
    var ok: Bool
    var installed: Bool
    var path: String
}

private struct BackgroundStatusPayload: Encodable {
    var ok: Bool
    var installed: Bool
    var path: String
    var label: String
}

private struct BackgroundUninstallPayload: Encodable {
    var ok: Bool
    var removed: Bool
    var path: String
}

struct ValidateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "validate")

    @Argument(help: "Manifest file to validate.")
    var file: String

    @Flag(name: .long)
    var json = false

    @Flag(name: .long)
    var explain = false

    func run() throws {
        let data = try readInputData(file)
        let result = try validateRecipeDocument(data)
        if json {
            try printJSON(ValidationPayload(
                ok: result.isValid,
                valid: result.isValid,
                errors: result.errors,
                explanations: explain ? result.errors.map(ValidationExplanation.init(error:)) : nil
            ))
        } else if result.isValid {
            print("valid")
        } else {
            for error in result.errors {
                FileHandle.standardError.write(Data((error + "\n").utf8))
            }
        }
        if !result.isValid {
            throw ExitCode.failure
        }
    }

    private func validateRecipeDocument(_ data: Data) throws -> ValidationResult {
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["schema_version"] != nil || object["items"] != nil
        {
            return try ManifestValidator.validate(data: data)
        }
        let recipe = try JSONDecoder.updateBar.decode(Recipe.self, from: data)
        let manifest = Manifest(
            schemaVersion: 1,
            items: [recipe],
            provenance: Provenance(createdBy: "updatebar", createdAt: Date(), updatedAt: Date())
        )
        return try ManifestValidator.validate(data: JSONEncoder.updateBar.encode(manifest))
    }
}

private struct ValidationPayload: Encodable {
    var ok: Bool
    var valid: Bool
    var errors: [String]
    var explanations: [ValidationExplanation]?
}

private struct ValidationExplanation: Encodable {
    var error: String
    var hint: String

    init(error: String) {
        self.error = error
        if error.contains("version_parse.jq") {
            hint = "Use version_parse.regex. jq is decoded by the schema but not executable yet."
        } else {
            hint = "Fix the field shown in the error path and run validate again."
        }
    }
}

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        subcommands: [Get.self, Set.self]
    )

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get")

        @Argument
        var key: String?

        @Flag(name: .long)
        var json = false

        func run() throws {
            let config = try ConfigStore().load()
            if let key {
                guard let value = config.get(key) else {
                    throw ValidationError("unknown config key: \(key)")
                }
                if json {
                    try printJSON(ConfigValuePayload(key: key, value: value))
                } else {
                    print(value)
                }
            } else if json {
                try printJSON(ConfigDumpPayload(config: config))
            } else {
                print(ConfigStore().renderForDisplay(config))
            }
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set")

        @Argument
        var key: String

        @Argument
        var value: String

        @Flag(name: .long)
        var json = false

        func run() throws {
            let store = ConfigStore()
            var config = try store.load()
            try config.set(key, value: value)
            try store.save(config)
            if json {
                try printJSON(ConfigSetPayload(ok: true, key: key, value: value))
            } else {
                print("updated \(key)")
            }
        }
    }
}

private struct ConfigSetPayload: Encodable {
    var ok: Bool
    var key: String
    var value: String
}

private struct ConfigValuePayload: Encodable {
    var key: String
    var value: String
}

private struct ConfigDumpPayload: Encodable {
    var refresh: Refresh
    var security: Security
    var notify: Notify

    init(config: Config) {
        refresh = Refresh(interval: config.refresh.interval.description, concurrency: config.refresh.concurrency)
        security = Security(
            allowImportExec: config.security.allowImportExec,
            requireHTTPSSource: config.security.requireHTTPSSource
        )
        notify = Notify(enabled: config.notify.enabled)
    }

    struct Refresh: Encodable {
        var interval: String
        var concurrency: Int
    }

    struct Security: Encodable {
        var allowImportExec: Bool
        var requireHTTPSSource: Bool

        enum CodingKeys: String, CodingKey {
            case allowImportExec = "allow_import_exec"
            case requireHTTPSSource = "require_https_source"
        }
    }

    struct Notify: Encodable {
        var enabled: Bool
    }
}

private struct ValidationError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

private func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    JSONOutputTracker.shared.markDidWrite()
    print(String(decoding: data, as: UTF8.self))
}

private final class JSONOutputTracker: @unchecked Sendable {
    static let shared = JSONOutputTracker()
    private let lock = NSLock()
    private var wrote = false

    var didWrite: Bool {
        lock.lock()
        defer { lock.unlock() }
        return wrote
    }

    func markDidWrite() {
        lock.lock()
        wrote = true
        lock.unlock()
    }
}

private func readInputData(_ path: String) throws -> Data {
    if path == "-" {
        return FileHandle.standardInput.readDataToEndOfFile()
    }
    return try Data(contentsOf: URL(fileURLWithPath: path))
}

struct GuideCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "guide",
        subcommands: [Agent.self, Recipe.self]
    )

    struct Agent: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "agent")

        func run() throws {
            print(
                """
                UpdateBar agent guide
                =====================

                UpdateBar tracks tools using recipe JSON.
                Recipes may contain shell commands. Treat those commands as sensitive.

                Safe workflow:
                1. Inspect contract: updatebar schema --json and updatebar guide recipe.
                2. Start from a template: updatebar template recipe --kind npm --id my-tool --source my-tool.
                3. Validate: updatebar validate recipe.json --json --explain.
                4. Dry-run add: updatebar add --from recipe.json --dry-run --json.
                5. Add untrusted: updatebar add --from recipe.json --json.
                6. Show every command field with updatebar approvals <id> --json.
                7. Do not approve commands silently.
                8. After user confirmation, approve exact fields:
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
        static let configuration = CommandConfiguration(commandName: "recipe")

        func run() throws {
            print(
                """
                Recipe authoring
                ================

                Required fields:
                id, name, category, source, version_scheme, check, latest,
                version_parse.regex, update, enabled, notify, trust.

                Rules:
                - use version_parse.regex with exactly one capture group
                - version_parse.jq is not supported yet
                - check.file reads local file content and parses it with version_parse.regex
                - latest.strategy cmd and all update commands require explicit approval
                - imported recipes should stay untrusted until a user reviews commands

                Start with:
                updatebar schema --json
                updatebar template recipe --kind npm --id my-tool --source my-tool
                updatebar validate recipe.json --json --explain
                """
            )
        }
    }
}

struct SchemaCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "schema")

    @Flag(name: .long)
    var json = false

    func run() throws {
        print(Self.recipeSchema)
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
        "provenance": { "type": "object" }
      },
      "$defs": {
        "recipe": {
          "type": "object",
          "required": ["id", "name", "category", "source", "version_scheme", "check", "latest", "version_parse", "update", "enabled", "notify", "trust"],
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
                { "required": ["file", "query"] }
              ],
              "properties": {
                "cmd": { "type": "string", "minLength": 1 },
                "file": { "type": "string", "minLength": 1 },
                "query": { "type": "string", "minLength": 1 }
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
                "cwd": { "type": ["string", "null"] }
              }
            },
            "pin": { "type": ["string", "null"] },
            "enabled": { "type": "boolean" },
            "notify": { "type": "boolean" },
            "trust": {
              "type": "object",
              "required": ["level", "approved_commands"],
              "properties": {
                "level": { "enum": ["trusted", "untrusted", "elevated"] },
                "approved_commands": { "type": "object", "additionalProperties": { "type": "string" } }
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
        subcommands: [RecipeTemplate.self, ManifestTemplate.self]
    )

    struct RecipeTemplate: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "recipe")

        @Option(name: .long)
        var kind: TemplateKind

        @Option(name: .long)
        var id: String?

        @Option(name: .long)
        var name: String?

        @Option(name: .long)
        var source: String?

        func run() throws {
            try printJSON(kind.recipe(id: id, name: name, sourceRef: source))
        }
    }

    struct ManifestTemplate: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "manifest")

        @Option(name: .long)
        var kind: TemplateKind

        @Option(name: .long)
        var id: String?

        @Option(name: .long)
        var name: String?

        @Option(name: .long)
        var source: String?

        func run() throws {
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

enum TemplateKind: String, ExpressibleByArgument {
    case githubRelease = "github_release"
    case npm
    case brew
    case gitTags = "git_tags"
    case httpRegex = "http_regex"
    case customCommand = "custom_command"

    func recipe(id requestedID: String? = nil, name requestedName: String? = nil, sourceRef requestedSourceRef: String? = nil) -> Recipe {
        switch self {
        case .githubRelease:
            return base(
                id: requestedID ?? "example-github-tool",
                name: requestedName,
                source: Source(kind: .githubRelease, ref: requestedSourceRef ?? "owner/repo", branch: nil),
                latest: LatestSpec(strategy: .githubRelease, cmd: nil, pattern: nil),
                update: "brew upgrade \(requestedID ?? "example-github-tool")"
            )
        case .npm:
            return base(
                id: requestedID ?? "example-npm-tool",
                name: requestedName,
                source: Source(kind: .npm, ref: requestedSourceRef ?? requestedID ?? "example-npm-tool", branch: nil),
                latest: LatestSpec(strategy: .npmRegistry, cmd: nil, pattern: nil),
                update: "npm install -g \(requestedSourceRef ?? requestedID ?? "example-npm-tool")@latest"
            )
        case .brew:
            return base(
                id: requestedID ?? "example-brew-tool",
                name: requestedName,
                source: Source(kind: .brew, ref: requestedSourceRef ?? requestedID ?? "example-brew-tool", branch: nil),
                latest: LatestSpec(strategy: .brew, cmd: nil, pattern: nil),
                update: "brew upgrade \(requestedSourceRef ?? requestedID ?? "example-brew-tool")"
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
                update: "brew upgrade \(requestedID ?? "example-http-tool")"
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
            notify: true,
            trust: Trust(level: .untrusted, approvedCommands: [:])
        )
    }
}

struct CheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "check")

    @Argument(help: "Item ids to check. Checks every registered item when omitted.")
    var ids: [String] = []

    @Flag(name: .long)
    var json = false

    @Flag(name: .long)
    var force = false

    @Flag(name: .long)
    var exitZeroOnOutdated = false

    func run() throws {
        let config = try ConfigStore().load()
        let service = RegistryService(
            config: config,
            githubToken: ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
                ?? ProcessInfo.processInfo.environment["GH_TOKEN"]
        )
        let results = try service.check(ids: ids, force: force)

        if json {
            try printJSON(results)
        } else {
            for result in results {
                print("\(result.id)\t\(result.status.rawValue)")
            }
        }

        if !exitZeroOnOutdated, results.contains(where: { $0.status == .outdated }) {
            throw ExitCode(10)
        }
    }
}

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status")

    @Flag(name: .long)
    var json = false

    @Flag(name: .long)
    var refresh = false

    @Flag(name: .long)
    var exitZeroOnOutdated = false

    func run() throws {
        let now = Date()
        let manifest = try ManifestStore().load()
        let stateStore = StateStore()
        var state = try stateStore.load(now: now)

        if refresh {
            let config = try ConfigStore().load()
            state = try stateStore.withExclusiveLock {
                let lockedState = try stateStore.load(now: now)
                let refreshed = markStaleItemsChecking(manifest: manifest, state: lockedState, config: config, now: now)
                try stateStore.save(refreshed)
                return refreshed
            }
        }

        let snapshot = StatusSnapshot.from(manifest: manifest, state: state, now: now)
        if json {
            try printJSON(snapshot)
        } else {
            for item in snapshot.items {
                print("\(item.id)\t\(item.status.rawValue)")
            }
        }

        if !exitZeroOnOutdated, snapshot.summary.outdated > 0 {
            throw ExitCode(10)
        }
    }

    private func markStaleItemsChecking(
        manifest: Manifest,
        state: State,
        config: Config,
        now: Date
    ) -> State {
        var copy = state
        for recipe in manifest.items {
            guard recipe.enabled, recipe.pin == nil, recipe.trust.level == .trusted else {
                continue
            }
            let existing = copy.items[recipe.id]
            if let lastChecked = existing?.lastChecked,
                now.timeIntervalSince(lastChecked) < TimeInterval(config.refresh.interval.seconds)
            {
                continue
            }
            copy.items[recipe.id] = ItemState(
                current: existing?.current,
                latest: existing?.latest,
                status: .checking,
                lastChecked: existing?.lastChecked,
                error: nil,
                backoffUntil: nil
            )
        }
        copy.generatedAt = now
        return copy
    }
}

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list")

    @Flag(name: .long)
    var json = false

    func run() throws {
        let manifest = try ManifestStore().load()
        let items = manifest.items.sorted { lhs, rhs in
            lhs.name == rhs.name ? lhs.id < rhs.id : lhs.name < rhs.name
        }

        if json {
            try printJSON(items)
        } else {
            print("ID\tNAME\tCATEGORY\tENABLED\tPINNED\tTRUST")
            for item in items {
                print(
                    "\(item.id)\t\(item.name)\t\(item.category)\t\(item.enabled)\t\(item.pin != nil)\t\(item.trust.level.rawValue)"
                )
            }
        }
    }
}

struct UpdateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update")

    @Argument(help: "Item ids to update.")
    var ids: [String] = []

    @Flag(name: .long)
    var all = false

    @Flag(name: .long)
    var yes = false

    @Flag(name: .long)
    var json = false

    func run() throws {
        guard all || !ids.isEmpty else {
            throw ValidationError("provide item ids or --all")
        }

        let config = try ConfigStore().load()
        let runner = UpdateRunner(
            config: config,
            githubToken: ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
                ?? ProcessInfo.processInfo.environment["GH_TOKEN"],
            confirm: confirmUpdate
        )
        let results = try runner.update(ids: ids, all: all, assumeYes: yes)

        if json {
            try printJSON(results)
        } else {
            for result in results {
                print("\(result.id)\t\(result.outcome.rawValue)")
            }
        }

        if results.contains(where: { $0.outcome.isHardFailure }) {
            throw ExitCode(2)
        }
        if results.contains(where: { $0.outcome == .skippedUntrusted }) {
            throw ExitCode(3)
        }
    }

    private func confirmUpdate(_ item: UpdatePlanItem) -> Bool {
        FileHandle.standardError.write(Data("Update \(item.id)? Type yes to continue: ".utf8))
        return readLine() == "yes"
    }
}

private extension UpdateOutcome {
    var isHardFailure: Bool {
        switch self {
        case .failed, .missing, .cancelled:
            true
        case .updated, .skippedPinned, .skippedDisabled, .skippedUntrusted, .skippedNotOutdated:
            false
        }
    }
}

struct PinCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "pin")

    @Argument
    var id: String

    @Argument
    var version: String?

    @Flag(name: .long)
    var json = false

    func run() throws {
        let recipe = try RegistryService().pin(id: id, version: version)
        if json {
            try printJSON(ItemMutationPayload(ok: true, id: recipe.id, item: recipe))
        } else {
            print("pinned \(recipe.id) \(recipe.pin ?? "")")
        }
    }
}

struct UnpinCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "unpin")

    @Argument
    var id: String

    @Flag(name: .long)
    var json = false

    func run() throws {
        let recipe = try RegistryService().unpin(id: id)
        if json {
            try printJSON(ItemMutationPayload(ok: true, id: recipe.id, item: recipe))
        } else {
            print("unpinned \(recipe.id)")
        }
    }
}

struct EnableCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "enable")

    @Argument
    var id: String

    @Flag(name: .long)
    var json = false

    func run() throws {
        let recipe = try RegistryService().setEnabled(id: id, enabled: true)
        if json {
            try printJSON(ItemMutationPayload(ok: true, id: recipe.id, item: recipe))
        } else {
            print("enabled \(recipe.id)")
        }
    }
}

struct DisableCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "disable")

    @Argument
    var id: String

    @Flag(name: .long)
    var json = false

    func run() throws {
        let recipe = try RegistryService().setEnabled(id: id, enabled: false)
        if json {
            try printJSON(ItemMutationPayload(ok: true, id: recipe.id, item: recipe))
        } else {
            print("disabled \(recipe.id)")
        }
    }
}

struct RemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove")

    @Argument
    var id: String

    @Flag(name: .long)
    var yes = false

    @Flag(name: .long)
    var json = false

    func run() throws {
        if !yes {
            FileHandle.standardError.write(Data("Remove \(id)? Type yes to continue: ".utf8))
            guard readLine() == "yes" else {
                throw ValidationError("remove cancelled")
            }
        }
        try RegistryService().remove(id: id)
        if json {
            try printJSON(RemovePayload(ok: true, id: id, removed: true))
        } else {
            print("removed \(id)")
        }
    }
}

struct ApprovalCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "approve")

    @Argument
    var id: String

    @Option(name: .long)
    var field: String?

    @Flag(name: .long)
    var json = false

    func run() throws {
        let recipe = try RegistryService().approve(id: id, field: field)
        if json {
            try printJSON(ApprovalMutationPayload(ok: true, id: recipe.id, field: field, item: recipe))
        } else if let field {
            print("approved \(recipe.id) \(field)")
        } else {
            print("approved \(recipe.id) all")
        }
    }
}

struct ApprovalsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "approvals")

    @Argument
    var id: String

    @Flag(name: .long)
    var json = false

    func run() throws {
        let manifest = try ManifestStore().load()
        guard let recipe = manifest.item(id: id) else {
            throw RegistryError.itemNotFound(id)
        }
        let commandTexts = recipe.commandTexts()
        let commandCwds = recipe.commandWorkingDirectories()
        let rows = recipe.commandFingerprints()
            .map { field, fingerprint in
                ApprovalPayload(
                    field: field,
                    approved: recipe.trust.level == .trusted && recipe.trust.approvedCommands[field] == fingerprint,
                    fingerprint: fingerprint,
                    command: commandTexts[field] ?? "",
                    cwd: commandCwds[field]
                )
            }
            .sorted { $0.field < $1.field }
        if json {
            try printJSON(rows)
        } else {
            for row in rows {
                print("\(row.field)\t\(row.approved ? "approved" : "unapproved")")
            }
        }
    }
}

struct RevokeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "revoke")

    @Argument
    var id: String

    @Option(name: .long)
    var field: String

    @Flag(name: .long)
    var json = false

    func run() throws {
        let recipe = try RegistryService().revokeApproval(id: id, field: field)
        if json {
            try printJSON(ApprovalMutationPayload(ok: true, id: recipe.id, field: field, item: recipe))
        } else {
            print("revoked \(recipe.id) \(field)")
        }
    }
}

private struct ItemMutationPayload: Encodable {
    var ok: Bool
    var id: String
    var item: Recipe
}

private struct ApprovalMutationPayload: Encodable {
    var ok: Bool
    var id: String
    var field: String?
    var item: Recipe
}

private struct RemovePayload: Encodable {
    var ok: Bool
    var id: String
    var removed: Bool
}

private struct ApprovalPayload: Encodable {
    var field: String
    var approved: Bool
    var fingerprint: String
    var command: String
    var cwd: String?
}

struct ExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "export")

    @Argument
    var file: String?

    @Flag(name: .long)
    var json = false

    func run() throws {
        let manifest = try RegistryService().exportManifest()
        if json {
            try printJSON(manifest)
            return
        }
        guard let file else {
            throw ValidationError("provide an export file or --json")
        }
        try JSONEncoder.updateBar.encode(manifest).write(to: URL(fileURLWithPath: file))
        print("exported \(file)")
    }
}

struct ImportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "import")

    @Argument
    var file: String

    @Flag(name: .long)
    var replace = false

    @Flag(name: .long)
    var json = false

    func run() throws {
        let data = try readInputData(file)
        let validation = try ManifestValidator.validate(data: data)
        guard validation.isValid else {
            if json {
                try printJSON(ImportPayload(added: [], replaced: [], errors: validation.errors))
            } else {
                for error in validation.errors {
                    FileHandle.standardError.write(Data((error + "\n").utf8))
                }
            }
            throw ExitCode.failure
        }

        let manifest = try JSONDecoder.updateBar.decode(Manifest.self, from: data)
        do {
            let summary = try RegistryService().importManifest(manifest, replace: replace)
            if json {
                try printJSON(ImportPayload(summary: summary, errors: []))
            } else {
                print("imported \(summary.added.count + summary.replaced.count) item(s)")
            }
        } catch {
            if json {
                try printJSON(ImportPayload(added: [], replaced: [], errors: [String(describing: error)]))
            }
            throw error
        }
    }
}

private struct ImportPayload: Encodable {
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

struct AddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add")

    @Option(name: .long)
    var from: String?

    @Flag(name: .long)
    var manual = false

    @Flag(name: .long)
    var dryRun = false

    @Flag(name: .long)
    var json = false

    @Flag(name: .long)
    var trust = false

    @Flag(name: .long)
    var yes = false

    @Flag(name: .long)
    var replace = false

    func run() throws {
        guard manual || from != nil else {
            throw ValidationError("pass --from <recipe.json> or --manual")
        }

        let recipe = try loadManualRecipe()
        let validated = try validatedRecipe(recipe)
        let prepared = try prepareForSave(validated)

        if dryRun {
            try output(AddPayload(valid: true, recipe: prepared, errors: []))
            return
        }

        do {
            try RegistryService().addRecipe(prepared, replace: replace)
            try output(AddPayload(valid: true, recipe: prepared, errors: []))
        } catch {
            if json {
                try output(AddPayload(valid: false, recipe: prepared, errors: [String(describing: error)]))
            }
            throw error
        }
    }

    private func loadManualRecipe() throws -> Recipe {
        if let from {
            if from == "-" {
                let data = FileHandle.standardInput.readDataToEndOfFile()
                return try loadRecipe(data: data)
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: from))
            return try loadRecipe(data: data)
        }
        return try runWizard()
    }

    private func loadRecipe(data: Data) throws -> Recipe {
        if let manifest = try? JSONDecoder.updateBar.decode(Manifest.self, from: data) {
            let validation = try ManifestValidator.validate(data: data)
            guard validation.isValid else {
                throw ValidationError(validation.errors.joined(separator: "\n"))
            }
            guard manifest.items.count == 1, let recipe = manifest.items.first else {
                throw ValidationError("add requires exactly one recipe")
            }
            return recipe
        }

        let recipe = try JSONDecoder.updateBar.decode(Recipe.self, from: data)
        return try validatedRecipe(recipe)
    }

    private func validatedRecipe(_ recipe: Recipe) throws -> Recipe {
        let manifest = Manifest(
            schemaVersion: 1,
            items: [recipe],
            provenance: Provenance(createdBy: "updatebar", createdAt: Date(), updatedAt: Date())
        )
        let data = try JSONEncoder.updateBar.encode(manifest)
        let validation = try ManifestValidator.validate(data: data)
        guard validation.isValid else {
            throw ValidationError(validation.errors.joined(separator: "\n"))
        }
        return recipe
    }

    private func prepareForSave(_ recipe: Recipe) throws -> Recipe {
        var prepared = TrustPolicy.untrustedCopy(recipe)
        guard trust else {
            return prepared
        }
        printCommands(prepared)
        if !yes {
            FileHandle.standardError.write(Data("Trust and approve these commands? Type yes to continue: ".utf8))
            guard readLine() == "yes" else {
                throw ValidationError("command approval cancelled")
            }
        }
        TrustPolicy.approveAllCommands(in: &prepared)
        return prepared
    }

    private func output(_ payload: AddPayload) throws {
        if json {
            try printJSON(payload)
        } else if payload.valid, let recipe = payload.recipe {
            print("added \(recipe.id)")
        } else {
            for error in payload.errors {
                FileHandle.standardError.write(Data((error + "\n").utf8))
            }
        }
    }

    private func printCommands(_ recipe: Recipe) {
        for (field, _) in recipe.commandFingerprints().sorted(by: { $0.key < $1.key }) {
            let command: String
            switch field {
            case "check.cmd":
                if case let .command(cmd) = recipe.check { command = cmd } else { continue }
            case "latest.cmd":
                command = recipe.latest.cmd ?? ""
            case "update.cmd":
                command = recipe.update.cmd
            default:
                continue
            }
            FileHandle.standardError.write(Data("\(field): \(command)\n".utf8))
        }
    }

    private func runWizard() throws -> Recipe {
        let id = try prompt("id")
        let name = try prompt("name")
        let category = try prompt("category")
        let path = optionalPrompt("path")
        let sourceKindText = try prompt("source.kind")
        guard let sourceKind = SourceKind(rawValue: sourceKindText) else {
            throw ValidationError("source.kind: unsupported value \(sourceKindText)")
        }
        let sourceRef = try prompt("source.ref")
        let sourceBranch = optionalPrompt("source.branch")
        let schemeText = try prompt("version_scheme")
        guard let scheme = VersionScheme(rawValue: schemeText) else {
            throw ValidationError("version_scheme: unsupported value \(schemeText)")
        }
        let checkCommand = try prompt("check.cmd")
        let latestStrategyText = try prompt("latest.strategy")
        guard let latestStrategy = LatestStrategyKind(rawValue: latestStrategyText) else {
            throw ValidationError("latest.strategy: unsupported value \(latestStrategyText)")
        }
        let latestCommand = latestStrategy == .cmd ? try prompt("latest.cmd") : optionalPrompt("latest.cmd")
        let latestPattern = latestStrategy == .httpRegex ? try prompt("latest.pattern") : optionalPrompt("latest.pattern")
        let versionRegex = try prompt("version_parse.regex")
        let updateCommand = try prompt("update.cmd")
        let updateCWD = optionalPrompt("update.cwd")

        return Recipe(
            id: id,
            name: name,
            category: category,
            path: path,
            source: Source(kind: sourceKind, ref: sourceRef, branch: sourceBranch),
            versionScheme: scheme,
            check: .command(checkCommand),
            latest: LatestSpec(strategy: latestStrategy, cmd: latestCommand, pattern: latestPattern),
            versionParse: .regex(versionRegex),
            update: UpdateSpec(cmd: updateCommand, cwd: updateCWD),
            pin: nil,
            enabled: true,
            notify: true,
            trust: Trust(level: .untrusted, approvedCommands: [:])
        )
    }

    private func prompt(_ label: String) throws -> String {
        FileHandle.standardError.write(Data("\(label): ".utf8))
        guard let line = readLine(), !line.isEmpty else {
            throw ValidationError("\(label): required")
        }
        return line
    }

    private func optionalPrompt(_ label: String) -> String? {
        FileHandle.standardError.write(Data("\(label): ".utf8))
        guard let line = readLine(), !line.isEmpty else {
            return nil
        }
        return line
    }

}

private struct AddPayload: Encodable {
    var ok: Bool
    var valid: Bool
    var recipe: Recipe?
    var errors: [String]

    init(valid: Bool, recipe: Recipe?, errors: [String]) {
        self.ok = valid
        self.valid = valid
        self.recipe = recipe
        self.errors = errors
    }
}

struct EditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "edit")

    @Argument
    var id: String

    func run() throws {
        let store = ManifestStore()
        let manifest = try store.load()
        guard let original = manifest.item(id: id) else {
            throw RegistryError.itemNotFound(id)
        }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-edit-\(UUID().uuidString).json")
        try JSONEncoder.updateBar.encode(original).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        try runEditor(file: temp)
        let editedData = try Data(contentsOf: temp)
        var edited = try JSONDecoder.updateBar.decode(Recipe.self, from: editedData)
        guard edited.id == original.id else {
            throw ValidationError("id cannot be changed during edit")
        }
        try validateEditedRecipe(edited)
        edited = invalidateChangedApprovals(original: original, edited: edited)

        try store.withExclusiveLock {
            var latest = try store.load()
            guard latest.item(id: id) != nil else {
                throw RegistryError.itemNotFound(id)
            }
            latest = latest.replacing(item: edited)
            latest.provenance.updatedAt = Date()
            try store.save(latest)
        }
        print("edited \(id)")
    }

    private func runEditor(file: URL) throws {
        let environment = ProcessInfo.processInfo.environment
        let editor = environment["VISUAL"] ?? environment["EDITOR"] ?? "vi"
        let process = Process()
#if os(macOS)
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
#else
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
#endif
        process.arguments = ["-lc", "\(editor) \(shellEscape(file.path))"]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ValidationError("editor exited \(process.terminationStatus)")
        }
    }

    private func validateEditedRecipe(_ recipe: Recipe) throws {
        let manifest = Manifest(
            schemaVersion: 1,
            items: [recipe],
            provenance: Provenance(createdBy: "updatebar", createdAt: Date(), updatedAt: Date())
        )
        let validation = try ManifestValidator.validate(data: JSONEncoder.updateBar.encode(manifest))
        guard validation.isValid else {
            throw ValidationError(validation.errors.joined(separator: "\n"))
        }
    }

    private func invalidateChangedApprovals(original: Recipe, edited: Recipe) -> Recipe {
        let newFingerprints = edited.commandFingerprints()
        var copy = edited
        copy.trust.approvedCommands = edited.trust.approvedCommands.filter { field, approved in
            original.trust.approvedCommands[field] == approved && newFingerprints[field] == approved
        }
        return copy
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
