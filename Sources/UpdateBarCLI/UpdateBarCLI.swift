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
        version: UpdateBarVersion.current,
        groupedSubcommands: [
            CommandGroup(name: "Setup", subcommands: [
                InitCommand.self,
                ScanCommand.self,
                AddCommand.self,
                ImportCommand.self,
                ExportCommand.self,
            ]),
            CommandGroup(name: "Check & Update", subcommands: [
                StatusCommand.self,
                CheckCommand.self,
                UpdateCommand.self,
                ListCommand.self,
            ]),
            CommandGroup(name: "Manage", subcommands: [
                ApprovalCommand.self,
                ApprovalsCommand.self,
                RevokeCommand.self,
                PinCommand.self,
                UnpinCommand.self,
                EnableCommand.self,
                DisableCommand.self,
                RemoveCommand.self,
                EditCommand.self,
            ]),
            CommandGroup(name: "System", subcommands: [
                ConfigCommand.self,
                BackgroundCommand.self,
                VersionCommand.self,
            ]),
            CommandGroup(name: "Support", subcommands: [
                GuideCommand.self,
                TUICommand.self,
                SchemaCommand.self,
                TemplateCommand.self,
                ValidateCommand.self,
            ]),
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
            if error is ExitCode {
                let exitCode = UpdateBar.exitCode(for: error)
                terminate(processExitCode(for: exitCode))
            }
            let exitCode = UpdateBar.exitCode(for: error)
            if CommandLine.arguments.contains("--json") || CommandLine.arguments.contains("--json-stream"),
                !JSONOutputTracker.shared.didWrite
            {
                writeJSONError(error, code: exitCode)
                terminate(processExitCode(for: exitCode))
            }
            let message = sanitizedErrorMessage(for: error)
            if !message.isEmpty {
                writeStderr(message)
            }
            terminate(processExitCode(for: exitCode))
        }
    }

    private static func writeJSONError(_ error: Error, code exitCode: ExitCode) {
        let message = sanitizedErrorMessage(for: error)
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
        if exitCode == .validationFailure {
            return "usage_error"
        }
        if error is ValidationError {
            return "usage_error"
        }
        if error is ConfigError {
            return "config_error"
        }
        if error is RegistryError {
            return "registry_error"
        }
        if error is DecodingError {
            return "decode_error"
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
    static let configuration = CommandConfiguration(commandName: "version", shouldDisplay: false)

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

struct TUICommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tui",
        abstract: "Launch the Ink terminal UI if installed."
    )

    func run() throws {
        let process = Process()
        let executable = try resolveTUICommand()
        process.executableURL = URL(fileURLWithPath: executable)
        process.environment = makeTUIEnvironment()
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()

        let exitCode = Int32(process.terminationStatus)
        if exitCode != 0 {
            throw ExitCode(exitCode)
        }
    }

    private func resolveTUICommand() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        if let resolved = commandFromPath(name: "updatebar-tui", environment: environment) {
            return resolved
        }
        throw ValidationError("Could not locate updatebar-tui on PATH.")
    }

    private func makeTUIEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["UPDATEBAR_BIN"] = resolveCurrentUpdateBarBinary()
        return environment
    }

    private func resolveCurrentUpdateBarBinary() -> String {
        let fallback = explicitExecutablePath(CommandLine.arguments.first) ?? "updatebar"
        return environmentValueOrDefault(
            ProcessInfo.processInfo.environment["UPDATEBAR_BIN"],
            fallback
        )
    }

    private func environmentValueOrDefault(_ value: String?, _ fallback: String) -> String {
        guard let value, !value.isEmpty else {
            return fallback
        }
        return value
    }

    private func explicitExecutablePath(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        guard FileManager.default.isExecutableFile(atPath: value) else {
            return nil
        }
        return value
    }

    private func commandFromPath(name: String, environment: [String: String]) -> String? {
        let pathValue = environment["PATH"] ?? ""
        let pathEntries = pathValue.split(separator: ":").map(String.init)
        for path in pathEntries {
            if path.isEmpty { continue }
            let candidate = URL(fileURLWithPath: path).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

struct ScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan installed local tools without modifying UpdateBar state."
    )

    @Flag(name: .long)
    var json = false

    @Option(name: .long, help: "Comma-separated detectors: brew,npm_global,known.")
    var detectors: String?

    @Option(name: .long, help: "Filter by category, such as ai-agent or cloud-devops.")
    var category: String?

    func run() throws {
        let selectedDetectors = try parseDetectors()
        let service = ScanService()
        var report = try service.scan(detectors: selectedDetectors)
        if let category {
            let normalized = normalizeCategory(category)
            report.candidates = report.candidates.filter { $0.category == normalized }
        }

        if json {
            try printJSON(report)
        } else {
            printHuman(report)
        }
    }

    private func parseDetectors() throws -> [ScanDetector] {
        try parseScanDetectors(detectors)
    }

    private func printHuman(_ report: ScanReport) {
        print("Found \(report.candidates.count) candidate(s)")
        print("")
        let recommended = report.candidates.filter { $0.capability == .full }
        let needsReview = report.candidates.filter { $0.capability != .full }
        let nextIndex = printSection("Recommended", candidates: recommended, startIndex: 1)
        _ = printSection("Needs Review", candidates: needsReview, startIndex: nextIndex)
        printNextStep(recommended)
        if !report.errors.isEmpty {
            print("")
            print("Errors")
            for error in report.errors {
                print("- \(error.detector.rawValue): \(error.message)")
            }
        }
    }

    private func printSection(
        _ title: String,
        candidates: [ScanCandidate],
        startIndex: Int
    ) -> Int {
        guard !candidates.isEmpty else { return startIndex }
        print(title)
        for (index, candidate) in candidates.enumerated() {
            let version = candidate.installedVersion.map { " \($0)" } ?? ""
            let name = "[\(startIndex + index)] \(candidate.name)\(version)"
            let fields = [
                name,
                candidate.id,
                candidate.category,
                candidate.detector.rawValue,
                candidate.capability.rawValue,
            ]
            print(fields.joined(separator: "\t"))
        }
        print("")
        return startIndex + candidates.count
    }

    private func printNextStep(_ candidates: [ScanCandidate]) {
        let ids = candidates.compactMap { candidate in
            candidate.recipe == nil ? nil : candidate.id
        }
        guard !ids.isEmpty else { return }
        print("Next")
        print("updatebar init")
        print("updatebar init --select \(ids.joined(separator: ","))")
        print("")
    }
}

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Scan installed local tools and register selected recipes."
    )

    @Flag(name: .long)
    var json = false

    @Flag(name: .long)
    var replace = false

    @Option(name: .long, help: "Comma-separated scan candidate ids.")
    var select: String?

    @Option(name: .long, help: "Comma-separated detectors: brew,npm_global,known.")
    var detectors: String?

    @Option(name: .long, help: "Filter by category, such as ai-agent or cloud-devops.")
    var category: String?

    func run() throws {
        let selectedDetectors = try parseDetectors()
        let report = try filteredReport(detectors: selectedDetectors)
        let selectedIDs = try parseSelection(from: report)

        do {
            let summary = try InitService().register(
                candidates: report.candidates,
                selectedIDs: selectedIDs,
                replace: replace
            )
            try output(InitPayload(summary: summary, errors: []))
        } catch let error as InitServiceError {
            try output(
                InitPayload(
                    added: [],
                    replaced: [],
                    skipped: [],
                    errors: [sanitizedErrorMessage(for: error)]
                )
            )
            throw ExitCode.failure
        }
    }

    private func filteredReport(detectors: [ScanDetector]) throws -> ScanReport {
        var report = try ScanService().scan(detectors: detectors)
        if let category {
            let normalized = normalizeCategory(category)
            report.candidates = report.candidates.filter { $0.category == normalized }
        }
        return report
    }

    private func parseDetectors() throws -> [ScanDetector] {
        try parseScanDetectors(detectors)
    }

    private func parseSelection(from report: ScanReport) throws -> [String] {
        if let select {
            let values = parseSelectionTokens(select)
            guard !values.isEmpty else {
                throw ValidationError("select: expected at least one candidate id")
            }
            if values.count == 1, values[0] == "all" {
                return report.candidates.filter {
                    $0.capability == .full && $0.recipe != nil
                }.map(\.id)
            }
            return values
        }

        if json {
            throw ValidationError("init --json requires --select")
        }

        let importable = report.candidates.filter {
            $0.capability == .full && $0.recipe != nil
        }
        printImportable(importable)
        let prompt = "Select items to add (numbers, ids, or all): "
        writeStderr(prompt, addNewline: false)
        guard let line = readLine(),
            !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ValidationError("selection required")
        }
        return try parseInteractiveSelection(line, candidates: importable)
    }

    private func parseInteractiveSelection(
        _ line: String,
        candidates: [ScanCandidate]
    ) throws -> [String] {
        let values = parseSelectionTokens(line)
        guard !values.isEmpty else {
            throw ValidationError("selection required")
        }
        if values.count == 1 && values[0].lowercased() == "all" {
            return candidates.map(\.id)
        }
        return try unique(values).map { value in
            if let index = Int(value) {
                guard index >= 1, index <= candidates.count else {
                    throw ValidationError("\(value): selection out of range")
                }
                return candidates[index - 1].id
            }
            return value
        }
    }

    private func parseSelectionTokens(_ value: String) -> [String] {
        parseList(value)
    }

    private func printImportable(_ candidates: [ScanCandidate]) {
        print("Found \(candidates.count) importable candidate(s)")
        print("")
        print("Recommended")
        for (index, candidate) in candidates.enumerated() {
            let version = candidate.installedVersion.map { " \($0)" } ?? ""
            let name = "[\(index + 1)] \(candidate.name)\(version)"
            let fields = [
                name,
                candidate.category,
                candidate.detector.rawValue,
                candidate.id,
            ]
            print(fields.joined(separator: "\t"))
        }
        print("")
    }

    private func output(_ payload: InitPayload) throws {
        if json {
            try printJSON(payload)
        } else if payload.ok {
            let message = [
                "added \(payload.added.count)",
                "replaced \(payload.replaced.count)",
                "skipped \(payload.skipped.count)",
            ].joined(separator: ", ")
            print(message)
        } else {
            for error in payload.errors {
                writeStderr(error)
            }
        }
    }
}

private func parseScanDetectors(_ value: String?) throws -> [ScanDetector] {
    guard let value, !value.isEmpty else {
        return ScanDetector.allCases
    }
    let values = parseList(value)
    guard !values.isEmpty else {
        throw ValidationError("detectors: expected brew, npm_global, or known")
    }
    var seen = Set<String>()
    var detectors: [ScanDetector] = []
    for detector in values where seen.insert(detector).inserted {
        guard let parsed = ScanDetector(rawValue: detector) else {
            throw ValidationError(
                "\(detector): unknown detector; expected brew, npm_global, or known")
        }
        detectors.append(parsed)
    }
    return detectors
}

private func ensureJSONModeCompatibility(json: Bool, jsonStream: Bool) throws {
    guard !(json && jsonStream) else {
        throw ValidationError("--json and --json-stream cannot be combined")
    }
}

private func withCancellationToken<T>(
    _ body: (CancellationToken) throws -> T
) throws -> T {
    let cancellationToken = CancellationToken()
    let signalHandler = SignalCancellationHandler(token: cancellationToken)
    defer { signalHandler.cancel() }
    return try body(cancellationToken)
}

private func readYes(_ prompt: String) -> Bool {
    writePrompt(prompt)
    return readLine() == "yes"
}

private func requireYes(prompt: String, cancelMessage: String, interactive: Bool = true) throws {
    guard interactive else {
        throw ValidationError(cancelMessage)
    }
    guard readYes(prompt) else {
        throw ValidationError(cancelMessage)
    }
}

private func parseList(_ raw: String, separators: CharacterSet = .whitespaceAndComma) -> [String] {
    raw
        .components(separatedBy: separators)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
}

private extension CharacterSet {
    static let whitespaceAndComma: CharacterSet = {
        CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines)
    }()
}

private func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var results: [String] = []
    for value in values where seen.insert(value).inserted {
        results.append(value)
    }
    return results
}

private func normalizeCategory(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private struct InitPayload: Encodable {
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
    static let configuration = CommandConfiguration(commandName: "validate", shouldDisplay: false)

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
                writeStderr(error)
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

private func sanitizedErrorMessage(for error: Error) -> String {
    let rawMessage = UpdateBar.fullMessage(for: error).isEmpty
        ? String(describing: error)
        : UpdateBar.fullMessage(for: error)
    let normalizedMessage = rawMessage.hasPrefix("Error: ") ? String(rawMessage.dropFirst("Error: ".count)) : rawMessage
    return SecretRedactor.redact(normalizedMessage)
}

private func writeStderr(_ message: String, addNewline: Bool = true) {
    let value = addNewline ? "\(message)\n" : message
    FileHandle.standardError.write(Data(SecretRedactor.redact(value).utf8))
}

private func writePrompt(_ prompt: String, trailingSpace: Bool = true) {
    writeStderr(prompt + (trailingSpace ? " " : ""), addNewline: false)
}

private struct JSONLWriter {
    let runID: String

    init(runID: String = UUID().uuidString) {
        self.runID = runID
    }

    func write(_ event: MachineEvent) throws {
        var event = event
        if event.runId == nil {
            event.runId = runID
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(event)
        JSONOutputTracker.shared.markDidWrite()
        print(String(decoding: data, as: UTF8.self))
    }
}

private final class SignalCancellationHandler {
    private var sources: [DispatchSourceSignal] = []

    init(token: CancellationToken) {
        for signalNumber in [SIGINT, SIGTERM] {
            Self.ignore(signalNumber)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
            source.setEventHandler {
                token.cancel()
            }
            source.resume()
            sources.append(source)
        }
    }

    func cancel() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
    }

    private static func ignore(_ signalNumber: Int32) {
#if os(Linux)
        Glibc.signal(signalNumber, SIG_IGN)
#else
        Darwin.signal(signalNumber, SIG_IGN)
#endif
    }
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
        shouldDisplay: false,
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
    static let configuration = CommandConfiguration(commandName: "schema", shouldDisplay: false)

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
        shouldDisplay: false,
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
    var jsonStream = false

    @Flag(name: .long)
    var force = false

    @Flag(name: .long)
    var exitZeroOnOutdated = false

    func run() throws {
        try ensureJSONModeCompatibility(json: json, jsonStream: jsonStream)
        let config = try ConfigStore().load()
        let results: [CheckResult] = try withCancellationToken { cancellationToken in
            let service = RegistryService(
                config: config,
                commandRunner: CommandExecutor(cancellationToken: cancellationToken),
                githubToken: ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
                    ?? ProcessInfo.processInfo.environment["GH_TOKEN"]
            )

            if jsonStream {
                try runJSONStream(service: service)
                return []
            }

            return try service.check(ids: ids, force: force)
        }

        if jsonStream {
            return
        }

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

    private func runJSONStream(service: RegistryService) throws {
        let writer = JSONLWriter()
        try writer.write(MachineEvent(
            event: .started,
            operation: .check,
            timestamp: Date()
        ))

        let results: [CheckResult]
        do {
            results = try service.check(ids: ids, force: force) { event in
                switch event.phase {
                case .itemStarted:
                    try writer.write(MachineEvent(
                        event: .itemStarted,
                        operation: .check,
                        timestamp: Date(),
                        itemId: event.id,
                        message: event.name
                    ))
                case .itemFinished:
                    try writer.write(MachineEvent(
                        event: .itemFinished,
                        operation: .check,
                        timestamp: Date(),
                        itemId: event.id,
                        checkResult: event.result
                    ))
                }
            }
        } catch let error as ExecutionError where error.isCancellation {
            try writer.write(MachineEvent(
                event: .cancelled,
                operation: .check,
                timestamp: Date(),
                error: sanitizedErrorMessage(for: error)
            ))
            throw ExitCode(2)
        } catch {
            try writer.write(MachineEvent(
                event: .failed,
                operation: .check,
                timestamp: Date(),
                error: sanitizedErrorMessage(for: error)
            ))
            throw error
        }

        let report = CheckReport(results: results)
        try writer.write(MachineEvent(
            event: .finished,
            operation: .check,
            timestamp: Date(),
            checkResults: report.results,
            checkSummary: report.summary
        ))

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
        let snapshot = try StatusService().snapshot(refresh: refresh)
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

    @Flag(name: .long)
    var jsonStream = false

    func run() throws {
        guard all || !ids.isEmpty else {
            throw ValidationError("provide item ids or --all")
        }
        try ensureJSONModeCompatibility(json: json, jsonStream: jsonStream)

        let config = try ConfigStore().load()
        let results: [UpdateResult] = try withCancellationToken { cancellationToken in
            let runner = UpdateRunner(
                config: config,
                commandRunner: CommandExecutor(cancellationToken: cancellationToken),
                githubToken: ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
                    ?? ProcessInfo.processInfo.environment["GH_TOKEN"],
                confirm: confirmUpdate
            )

            if jsonStream {
                try runJSONStream(runner: runner)
                return []
            }

            return try runner.update(ids: ids, all: all, assumeYes: yes)
        }

        if jsonStream {
            return
        }

        if json {
            try printJSON(results)
        } else {
            for result in results {
                print("\(result.id)\t\(result.outcome.rawValue)")
            }
        }

        try enforceExitCodes(results)
    }

    private func runJSONStream(runner: UpdateRunner) throws {
        let writer = JSONLWriter()
        try writer.write(MachineEvent(
            event: .started,
            operation: .update,
            timestamp: Date()
        ))

        var results: [UpdateResult] = []
        do {
            let plan = try runner.plan(ids: ids, all: all)
            try writer.write(MachineEvent(
                event: .log,
                operation: .update,
                timestamp: Date(),
                message: "planned \(plan.count) item(s)",
                level: .info
            ))

            for item in plan {
                try writer.write(MachineEvent(
                    event: .itemStarted,
                    operation: .update,
                    timestamp: Date(),
                    itemId: item.id,
                    message: item.name
                ))
                let itemResults = try runner.update(ids: [item.id], all: false, assumeYes: yes)
                let result = itemResults.first ?? UpdateResult(
                    id: item.id,
                    name: item.name,
                    outcome: .missing,
                    current: item.current,
                    latest: item.latest,
                    error: "missing update result",
                    commandFingerprint: item.commandFingerprint
                )
                results.append(result)
                try writer.write(MachineEvent(
                    event: .itemFinished,
                    operation: .update,
                    timestamp: Date(),
                    itemId: result.id,
                    result: result
                ))
                if result.outcome == .cancelled {
                    break
                }
            }
        } catch {
            try writer.write(MachineEvent(
                event: .failed,
                operation: .update,
                timestamp: Date(),
                error: sanitizedErrorMessage(for: error)
            ))
            throw error
        }

        let report = UpdateReport(results: results)
        if results.contains(where: { $0.outcome == .cancelled }) {
            try writer.write(MachineEvent(
                event: .cancelled,
                operation: .update,
                timestamp: Date(),
                summary: report.summary,
                error: "cancelled"
            ))
        }
        try writer.write(MachineEvent(
            event: .finished,
            operation: .update,
            timestamp: Date(),
            results: report.results,
            summary: report.summary
        ))

        try enforceExitCodes(results)
    }

    private func enforceExitCodes(_ results: [UpdateResult]) throws {
        if results.contains(where: { $0.outcome.isHardFailure }) {
            throw ExitCode(2)
        }
        if results.contains(where: { $0.outcome == .skippedUntrusted }) {
            throw ExitCode(3)
        }
    }

    private func confirmUpdate(_ item: UpdatePlanItem) -> Bool {
        if json || jsonStream {
            return false
        }
        return readYes("Update \(item.id)? Type yes to continue:")
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
            try requireYes(
                prompt: "Remove \(id)? Type yes to continue:",
                cancelMessage: "remove cancelled",
                interactive: !json
            )
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
        let rows = try RegistryService().approvals(id: id)
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
                    writeStderr(error)
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
                try printJSON(ImportPayload(
                    added: [],
                    replaced: [],
                    errors: [sanitizedErrorMessage(for: error)]
                ))
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
                try output(AddPayload(
                    valid: false,
                    recipe: prepared,
                    errors: [sanitizedErrorMessage(for: error)]
                ))
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
            try requireYes(
                prompt: "Trust and approve these commands? Type yes to continue:",
                cancelMessage: "command approval cancelled",
                interactive: !json
            )
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
                writeStderr(error)
            }
        }
    }

    private func printCommands(_ recipe: Recipe) {
        guard !json else {
            return
        }
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
            writeStderr("\(field): \(command)")
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
        writePrompt(label)
        guard let line = readLine(), !line.isEmpty else {
            throw ValidationError("\(label): required")
        }
        return line
    }

    private func optionalPrompt(_ label: String) -> String? {
        writePrompt(label)
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
