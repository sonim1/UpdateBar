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
                CommandGroup(name: "System", subcommands: systemSubcommands),
            CommandGroup(name: "Support", subcommands: [
                GuideCommand.self,
                TUICommand.self,
                SchemaCommand.self,
                TemplateCommand.self,
                ValidateCommand.self,
            ]),
        ]
    )

    private static let systemSubcommands: [ParsableCommand.Type] = {
#if os(macOS)
        return [ConfigCommand.self, BackgroundCommand.self]
#else
        return [ConfigCommand.self]
#endif
    }()
}

@main
enum UpdateBarMain {
    static func main() {
        let arguments = Self.normalizeArguments(Array(CommandLine.arguments.dropFirst()))
        do {
            var command = try UpdateBar.parseAsRoot(arguments)
            try command.run()
        } catch {
            if error is ExitCode {
                let exitCode = UpdateBar.exitCode(for: error)
                terminate(processExitCode(for: exitCode))
            }
            let exitCode = UpdateBar.exitCode(for: error)
            if exitCode == .success {
                let message = sanitizedErrorMessage(for: error)
                if !message.isEmpty {
                    writeStdout(message)
                }
                terminate(0)
            }
            if requestedJSONOutput(arguments),
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

    private static func normalizeArguments(_ arguments: [String]) -> [String] {
        var normalized: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            let next: String? = index + 1 < arguments.count
                ? arguments[index + 1]
                : nil

            if let next,
               let normalizedPair = normalizeBooleanFlagValuePair(flag: argument, value: next)
            {
                normalized.append(contentsOf: normalizedPair)
                index += 2
                continue
            }

            if let action = normalizeBooleanAssignmentArgument(argument) {
                switch action {
                case .keep(let value):
                    normalized.append(value)
                case .drop:
                    break
                }
                index += 1
                continue
            }

            normalized.append(argument)
            index += 1
        }

        return normalized
    }

    private static func normalizeBooleanFlagValuePair(flag: String, value: String) -> [String]? {
        guard isBooleanFlag(flag),
              let boolValue = parseBooleanValue(value)
        else {
            return nil
        }

        return boolValue ? [flag] : []
    }

    private static func normalizeBooleanAssignmentArgument(_ argument: String) -> NormalizedArgument? {
        guard argument.hasPrefix("--"), let equalsRange = argument.firstIndex(of: "=") else {
            return nil
        }

        let key = String(argument[..<equalsRange])
        let value = String(argument[argument.index(after: equalsRange)...]).lowercased()

        switch key {
        case "--json", "--json-stream":
            if trueBooleanValues.contains(value) {
                return .keep(key)
            }
            if falseBooleanValues.contains(value) {
                return .drop
            }
            return .keep(argument)
        default:
            return .keep(argument)
        }
    }

    private enum NormalizedArgument {
        case keep(String)
        case drop
    }

    private static func isBooleanFlag(_ argument: String) -> Bool {
        jsonBooleanFlags.contains(argument)
    }

    private static func parseBooleanValue(_ value: String) -> Bool? {
        let normalized = value.lowercased()
        if trueBooleanValues.contains(normalized) {
            return true
        }
        if falseBooleanValues.contains(normalized) {
            return false
        }
        return nil
    }

    private static let jsonBooleanFlags: Set<String> = [
        "--json",
        "--json-stream"
    ]

    private static let trueBooleanValues: Set<String> = [
        "1",
        "true",
        "t",
        "yes",
        "on"
    ]

    private static let falseBooleanValues: Set<String> = [
        "0",
        "false",
        "f",
        "no",
        "off"
    ]

    private static func requestedJSONOutput(_ arguments: [String]) -> Bool {
        arguments.contains("--json") || arguments.contains("--json-stream")
            || arguments.contains(where: { $0.hasPrefix("--json=") || $0.hasPrefix("--json-stream=") })
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

struct TUICommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tui",
        abstract: "Launch the Ink terminal UI if installed.",
        shouldDisplay: false
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
        if let override = environment["UPDATEBAR_TUI"], !override.isEmpty {
            if explicitExecutablePath(override) != nil {
                return override
            }
            throw ValidationError("UPDATEBAR_TUI is not executable: \(override)")
        }
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
        return resolveExecutable(name, environment: environment)
    }
}

struct ScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan installed local tools without modifying UpdateBar state."
    )

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    @Option(name: .long, help: .hidden)
    var detectors: String?

    @Option(name: .long, help: "Filter by category: ai-agent, package-manager, runtime-sdk, shell-utility, cloud-devops, library, codex-skill, or mcp-server.")
    var category: String?

    func run() throws {
        let categoryFilter = try parseCategoryFilter(category)
        let selectedDetectors = try parseDetectors(categoryFilter: categoryFilter)
        let service = ScanService()
        var report = try service.scan(detectors: selectedDetectors)
        if let category = categoryFilter {
            report.candidates = report.candidates.filter { $0.category == category }
        }

        if json {
            try printJSON(report)
        } else {
            printHuman(report)
        }
    }

    private func parseDetectors(categoryFilter: String?) throws -> [ScanDetector] {
        try parseScanDetectors(detectors, categoryFilter: categoryFilter)
    }

    private func printHuman(_ report: ScanReport) {
        print("Found \(report.candidates.count) candidate(s)")
        print("")
        let recommended = report.candidates.filter { $0.capability == .full }
        let needsReview = report.candidates.filter { $0.capability != .full }
        let nextIndex = printSection("Recommended", candidates: recommended, startIndex: 1)
        _ = printSection("Needs Review", candidates: needsReview, startIndex: nextIndex)
        printReviewOnlyNote(recommended: recommended, needsReview: needsReview)
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
            let visibleFields = metadataSourceRef(for: candidate).map {
                fields + [$0]
            } ?? fields
            print(visibleFields.joined(separator: "\t"))
        }
        print("")
        return startIndex + candidates.count
    }

    private func printReviewOnlyNote(
        recommended: [ScanCandidate],
        needsReview: [ScanCandidate]
    ) {
        guard recommended.isEmpty, !needsReview.isEmpty else {
            return
        }
        print("Review-only candidates are not importable yet.")
        print("")
    }

    private func metadataSourceRef(for candidate: ScanCandidate) -> String? {
        guard candidate.capability != .full,
            let sourceRef = candidate.sourceRef,
            !sourceRef.isEmpty
        else {
            return nil
        }
        return sourceRef
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

struct BackgroundCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "background",
        abstract: "Manage the opt-in background check LaunchAgent.",
        shouldDisplay: false,
        subcommands: [Install.self, Status.self, Uninstall.self]
    )

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "install",
            abstract: "Install the background check LaunchAgent."
        )

        @Flag(name: .long, help: "Install without prompting for confirmation.")
        var yes = false

        @Flag(name: .long, help: "Print machine-readable JSON.")
        var json = false

        func run() throws {
#if os(macOS)
            guard yes else {
                throw ValidationError("background install requires --yes")
            }

            let manager = BackgroundLaunchAgentManager()
            let intervalSeconds = try ConfigStore().load().refresh.interval.seconds
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
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show background check LaunchAgent status."
        )

        @Flag(name: .long, help: "Print machine-readable JSON.")
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
        static let configuration = CommandConfiguration(
            commandName: "uninstall",
            abstract: "Remove the background check LaunchAgent."
        )

        @Flag(name: .long, help: "Print machine-readable JSON.")
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

struct ValidateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate a recipe or manifest document.",
        shouldDisplay: false
    )

    @Argument(help: "Manifest file to validate.")
    var file: String

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    @Flag(name: .long, help: "Include structured validation explanations in JSON output.")
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
        if try isManifestDocument(data) {
            return try ManifestValidator.validate(data: data)
        }
        return try RecipeValidator.validate(data: data)
    }
}

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Read or update UpdateBar configuration.",
        shouldDisplay: false,
        subcommands: [Get.self, Set.self]
    )

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Read one config value or all config."
        )

        @Argument(help: "Config key to read; omit to show all config.")
        var key: String?

        @Flag(name: .long, help: "Print machine-readable JSON.")
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
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Update one config value."
        )

        @Argument(help: "Config key to update.")
        var key: String

        @Argument(help: "Value to store.")
        var value: String

        @Flag(name: .long, help: "Print machine-readable JSON.")
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

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the latest stored status without running updates."
    )

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    @Flag(name: .long, help: .hidden)
    var refresh = false

    @Flag(name: .long, help: .hidden)
    var exitZeroOnOutdated = false

    func run() throws {
        let snapshot = try StatusService().snapshot(refresh: refresh)
        if json {
            try printJSON(snapshot)
        } else {
            printHuman(snapshot)
        }

        if !exitZeroOnOutdated, snapshot.summary.outdated > 0 {
            throw ExitCode(10)
        }
    }

    private func printHuman(_ snapshot: StatusSnapshot) {
        if snapshot.items.isEmpty {
            printEmptyRegistryNextStep()
            return
        }

        for item in snapshot.items {
            print("\(item.id)\t\(item.status.rawValue)")
        }

        let untrusted = snapshot.items.filter { $0.status == .untrusted }
        guard !untrusted.isEmpty else {
            return
        }

        printNextCommands(untrusted.flatMap { item in
            [
                "updatebar approvals \(item.id)",
                "updatebar check \(item.id)",
            ]
        })
    }
}

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List registered recipes.",
        shouldDisplay: false
    )

    @Flag(name: .long, help: "Print machine-readable JSON.")
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

struct ExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export registered recipes as a manifest.",
        shouldDisplay: false
    )

    @Argument(help: "Output file path; omit when using --json.")
    var file: String?

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    func run() throws {
        let manifest = try RegistryService().exportManifest()
        if json, file != nil {
            throw ValidationError("export --json does not accept a file argument.")
        }
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
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import recipes from a manifest file or stdin.",
        shouldDisplay: false
    )

    @Argument(help: "Manifest file path, or '-' for stdin.")
    var file: String

    @Flag(name: .long, help: "Overwrite existing items with matching ids.")
    var replace = false

    @Flag(name: .long, help: "Print machine-readable JSON.")
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
                printApprovalAndCheckNextSteps(for: summary.added + summary.replaced)
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
