import Foundation

public enum AddRecipeOutcome: String, Codable, Equatable {
    case added
    case replaced
}

public struct RegistryService {
    private let manifestStore: ManifestStore
    private let stateStore: StateStore
    private let config: Config
    private let httpClient: HTTPClient
    private let commandRunner: CommandRunning
    private let now: () -> Date
    private let githubToken: String?
    private let userHomeDirectory: URL

    public init(
        manifestStore: ManifestStore = ManifestStore(),
        stateStore: StateStore = StateStore(),
        config: Config = .default,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        commandRunner: CommandRunning = CommandExecutor(),
        now: @escaping () -> Date = { Date() },
        githubToken: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.manifestStore = manifestStore
        self.stateStore = stateStore
        self.config = config
        self.httpClient = httpClient
        self.commandRunner = commandRunner
        self.now = now
        self.githubToken = githubToken
        self.userHomeDirectory = UserPathExpander.homeDirectory(environment: environment)
    }

    public func check(
        ids: [String] = [],
        force: Bool = false,
        onEvent: ((CheckProgressEvent) throws -> Void)? = nil
    ) throws -> [CheckResult] {
        let manifest = try manifestStore.loadExistingOrEmpty(now: now())
        try validate(manifest)

        let selected = try selectedRecipes(from: manifest, ids: ids)
        if selected.isEmpty {
            return []
        }

        return try stateStore.withExclusiveLock {
            let checkDate = now()
            var state = try stateStore.load(now: checkDate)
            var results: [CheckResult] = []

            func appendResult(for recipe: Recipe, state itemState: ItemState) throws {
                let result = self.result(for: recipe, state: itemState)
                results.append(result)
                try onEvent?(CheckProgressEvent(
                    phase: .itemFinished,
                    id: recipe.id,
                    name: recipe.name,
                    result: result
                ))
            }

            for recipe in selected {
                try onEvent?(CheckProgressEvent(
                    phase: .itemStarted,
                    id: recipe.id,
                    name: recipe.name
                ))
                let existing = state.items[recipe.id]

                if !recipe.enabled {
                    let itemState = ItemState(
                        current: existing?.current,
                        latest: existing?.latest,
                        status: .disabled,
                        lastChecked: checkDate,
                        error: nil,
                        backoffUntil: nil
                    )
                    state.items[recipe.id] = itemState
                    try appendResult(for: recipe, state: itemState)
                    continue
                }

                if recipe.pin != nil {
                    let itemState = ItemState(
                        current: existing?.current,
                        latest: existing?.latest,
                        status: .pinned,
                        lastChecked: checkDate,
                        error: nil,
                        backoffUntil: nil
                    )
                    state.items[recipe.id] = itemState
                    try appendResult(for: recipe, state: itemState)
                    continue
                }

                if !TrustPolicy.isCheckApproved(recipe) {
                    let itemState = ItemState(
                        current: existing?.current,
                        latest: existing?.latest,
                        status: .untrusted,
                        lastChecked: checkDate,
                        error: "commands are not approved",
                        backoffUntil: nil
                    )
                    state.items[recipe.id] = itemState
                    try appendResult(for: recipe, state: itemState)
                    continue
                }

                if !force, let existing, isFresh(existing, now: checkDate) {
                    try appendResult(for: recipe, state: existing)
                    continue
                }

                var observedCurrent = existing?.current
                var observedLatest = existing?.latest
                do {
                    let current = try currentVersion(for: recipe)
                    observedCurrent = current
                    let latest = try latestVersion(for: recipe)
                    observedLatest = latest
                    let status = try VersionComparator.status(
                        current: current,
                        latest: latest,
                        scheme: recipe.versionScheme
                    )
                    let itemState = ItemState(
                        current: current,
                        latest: latest,
                        status: status,
                        lastChecked: checkDate,
                        error: nil,
                        backoffUntil: nil
                    )
                    state.items[recipe.id] = itemState
                    try appendResult(for: recipe, state: itemState)
                } catch let error as ExecutionError where error.isCancellation {
                    throw error
                } catch {
                    let itemState = ItemState(
                        current: observedCurrent,
                        latest: observedLatest,
                        status: .error,
                        lastChecked: checkDate,
                        error: SecretRedactor.redact(String(describing: error)),
                        backoffUntil: nil
                    )
                    state.items[recipe.id] = itemState
                    try appendResult(for: recipe, state: itemState)
                }
            }

            state.generatedAt = checkDate
            try stateStore.save(state)
            return results
        }
    }

    public func pin(id: String, version: String? = nil) throws -> Recipe {
        try manifestStore.withExclusiveLock {
            var manifest = try manifestStore.loadExistingOrEmpty(now: now())
            try validate(manifest)
            guard var recipe = manifest.item(id: id) else {
                throw RegistryError.itemNotFound(id)
            }
            let pinVersion: String
            if let version {
                pinVersion = version
            } else {
                let state = try stateStore.loadExistingOrEmpty(now: now())
                guard let current = state.items[id]?.current else {
                    throw RegistryError.missingCurrentVersion(id)
                }
                pinVersion = current
            }
            recipe.pin = pinVersion
            manifest = manifest.replacing(item: recipe)
            manifest.provenance.updatedAt = now()
            try saveValid(manifest)
            return recipe
        }
    }

    public func unpin(id: String) throws -> Recipe {
        try manifestStore.withExclusiveLock {
            var manifest = try manifestStore.loadExistingOrEmpty(now: now())
            guard var recipe = manifest.item(id: id) else {
                throw RegistryError.itemNotFound(id)
            }
            recipe.pin = nil
            manifest = manifest.replacing(item: recipe)
            manifest.provenance.updatedAt = now()
            try saveValid(manifest)
            return recipe
        }
    }

    public func setEnabled(id: String, enabled: Bool) throws -> Recipe {
        try manifestStore.withExclusiveLock {
            var manifest = try manifestStore.loadExistingOrEmpty(now: now())
            guard var recipe = manifest.item(id: id) else {
                throw RegistryError.itemNotFound(id)
            }
            recipe.enabled = enabled
            manifest = manifest.replacing(item: recipe)
            manifest.provenance.updatedAt = now()
            try saveValid(manifest)
            return recipe
        }
    }

    public func approve(id: String, field: String? = nil) throws -> Recipe {
        try manifestStore.withExclusiveLock {
            var manifest = try manifestStore.loadExistingOrEmpty(now: now())
            try validate(manifest)
            guard var recipe = manifest.item(id: id) else {
                throw RegistryError.itemNotFound(id)
            }
            let fingerprints = recipe.commandFingerprints()
            if let field {
                guard let fingerprint = fingerprints[field] else {
                    throw RegistryError.commandFieldNotFound(field)
                }
                recipe.trust.approvedCommands[field] = fingerprint
                recipe.trust.level = .trusted
            } else {
                TrustPolicy.approveAllCommands(in: &recipe)
            }
            manifest = manifest.replacing(item: recipe)
            manifest.provenance.updatedAt = now()
            try saveValid(manifest)
            return recipe
        }
    }

    public func approvals(id: String) throws -> [ApprovalStatus] {
        let manifest = try manifestStore.loadExistingOrEmpty(now: now())
        try validate(manifest)
        guard let recipe = manifest.item(id: id) else {
            throw RegistryError.itemNotFound(id)
        }
        let commandTexts = recipe.commandTexts()
        let commandCwds = recipe.commandWorkingDirectories()
        return recipe.commandFingerprints()
            .map { field, fingerprint in
                ApprovalStatus(
                    field: field,
                    approved: recipe.trust.level == .trusted
                        && recipe.trust.approvedCommands[field] == fingerprint,
                    fingerprint: fingerprint,
                    command: commandTexts[field] ?? "",
                    cwd: commandCwds[field]
                )
            }
            .sorted { $0.field < $1.field }
    }

    public func recipe(id: String) throws -> Recipe {
        let manifest = try manifestStore.loadExistingOrEmpty(now: now())
        try validate(manifest)
        guard let recipe = manifest.item(id: id) else {
            throw RegistryError.itemNotFound(id)
        }
        return recipe
    }

    public func revokeApproval(id: String, field: String) throws -> Recipe {
        try manifestStore.withExclusiveLock {
            var manifest = try manifestStore.loadExistingOrEmpty(now: now())
            guard var recipe = manifest.item(id: id) else {
                throw RegistryError.itemNotFound(id)
            }
            guard recipe.commandFingerprints()[field] != nil else {
                throw RegistryError.commandFieldNotFound(field)
            }
            recipe.trust.approvedCommands.removeValue(forKey: field)
            if recipe.trust.approvedCommands.isEmpty {
                recipe.trust.level = .untrusted
            }
            manifest = manifest.replacing(item: recipe)
            manifest.provenance.updatedAt = now()
            try saveValid(manifest)
            return recipe
        }
    }

    public func remove(id: String) throws {
        try manifestStore.withExclusiveLock {
            var manifest = try manifestStore.loadExistingOrEmpty(now: now())
            guard manifest.item(id: id) != nil else {
                throw RegistryError.itemNotFound(id)
            }
            manifest = manifest.removing(id: id)
            manifest.provenance.updatedAt = now()
            try saveValid(manifest)
        }

        try stateStore.withExclusiveLock {
            let removalDate = now()
            var state = try stateStore.loadExistingOrEmpty(now: removalDate)
            guard state.items.removeValue(forKey: id) != nil else {
                return
            }
            state.generatedAt = removalDate
            try stateStore.save(state)
        }
    }

    public func exportManifest() throws -> Manifest {
        let manifest = try manifestStore.loadExistingOrEmpty(now: now())
        try validate(manifest)
        return manifest
    }

    public func addRecipe(_ recipe: Recipe, replace: Bool) throws -> AddRecipeOutcome {
        let validationDate = now()
        let incoming = Manifest(
            schemaVersion: 1,
            items: [recipe],
            provenance: Provenance(createdBy: "updatebar", createdAt: validationDate, updatedAt: validationDate)
        )
        try validate(incoming)
        return try manifestStore.withExclusiveLock {
            let mutationDate = now()
            var manifest = try manifestStore.loadExistingOrEmpty(now: mutationDate)
            let outcome: AddRecipeOutcome = manifest.item(id: recipe.id) == nil ? .added : .replaced
            if outcome == .replaced, !replace {
                throw RegistryError.duplicateItem(recipe.id)
            }
            manifest = manifest.replacing(item: recipe)
            manifest.provenance.updatedAt = mutationDate
            try saveValid(manifest)
            return outcome
        }
    }

    public func importManifest(_ incoming: Manifest, replace: Bool) throws -> ImportSummary {
        try validate(incoming)
        return try manifestStore.withExclusiveLock {
            let mutationDate = now()
            var manifest = try manifestStore.loadExistingOrEmpty(now: mutationDate)
            var added: [String] = []
            var replaced: [String] = []

            for incomingItem in incoming.items {
                let item = TrustPolicy.untrustedCopy(incomingItem)
                if manifest.item(id: item.id) != nil {
                    guard replace else {
                        throw RegistryError.duplicateItem(item.id)
                    }
                    manifest = manifest.replacing(item: item)
                    replaced.append(item.id)
                } else {
                    manifest = manifest.replacing(item: item)
                    added.append(item.id)
                }
            }

            manifest.provenance.updatedAt = mutationDate
            try saveValid(manifest)
            return ImportSummary(added: added, replaced: replaced)
        }
    }

    private func saveValid(_ manifest: Manifest) throws {
        try validate(manifest)
        try manifestStore.save(manifest)
    }

    private func validate(_ manifest: Manifest) throws {
        let data = try JSONEncoder.updateBar.encode(manifest)
        let result = try ManifestValidator.validate(data: data)
        if !result.isValid {
            throw RegistryError.invalidManifest(result.errors)
        }
    }

    private func selectedRecipes(from manifest: Manifest, ids: [String]) throws -> [Recipe] {
        if ids.isEmpty {
            return manifest.items
        }
        return try ids.map { id in
            guard let item = manifest.item(id: id) else {
                throw RegistryError.itemNotFound(id)
            }
            return item
        }
    }

    private func isFresh(_ state: ItemState, now: Date) -> Bool {
        guard let lastChecked = state.lastChecked else { return false }
        return now.timeIntervalSince(lastChecked) < TimeInterval(config.refresh.interval.seconds)
    }

    private func currentVersion(for recipe: Recipe) throws -> String {
        switch recipe.check {
        case let .command(command):
            let result = try commandRunner.run(
                ShellCommand(command: command, cwd: nil),
                policy: ExecutionPolicy(timeout: 60, maxOutputBytes: 128 * 1024)
            )
            guard result.exitCode == 0 else {
                throw RegistryError.commandFailed("check.cmd exited \(result.exitCode): \(result.stderr)")
            }
            return try VersionParser.extract(
                from: "\(result.stdout)\n\(result.stderr)",
                using: recipe.versionParse
            )
        case let .file(path):
            let resolvedPath = expandedPath(path)
            guard FileManager.default.isReadableFile(atPath: resolvedPath) else {
                throw RegistryError.checkFileNotReadable(resolvedPath)
            }
            let data: Data
            do {
                data = try Data(contentsOf: URL(fileURLWithPath: resolvedPath))
            } catch {
                throw RegistryError.checkFileNotReadable(resolvedPath)
            }
            return try VersionParser.extract(from: String(decoding: data, as: UTF8.self), using: recipe.versionParse)
        }
    }

    private func latestVersion(for recipe: Recipe) throws -> String {
        let context = LatestContext(
            httpClient: httpClient,
            commandRunner: commandRunner,
            githubToken: githubToken,
            requireHTTPSSource: config.security.requireHTTPSSource
        )
        return try latestStrategy(for: recipe.latest.strategy).latest(for: recipe, context: context)
    }

    private func latestStrategy(for kind: LatestStrategyKind) -> any LatestStrategy {
        switch kind {
        case .gitTags:
            GitLatestStrategy(mode: .tags)
        case .gitHead:
            GitLatestStrategy(mode: .head)
        case .npmRegistry:
            NPMRegistryLatestStrategy()
        case .githubRelease:
            GitHubReleaseLatestStrategy()
        case .brew:
            BrewLatestStrategy()
        case .httpRegex:
            HTTPLatestStrategy()
        case .cmd:
            CommandLatestStrategy()
        }
    }

    private func result(for recipe: Recipe, state: ItemState) -> CheckResult {
        CheckResult(
            id: recipe.id,
            name: recipe.name,
            current: state.current,
            latest: state.latest,
            status: state.status,
            lastChecked: state.lastChecked,
            error: state.error
        )
    }

    private func expandedPath(_ path: String) -> String {
        UserPathExpander.expandTilde(in: path, homeDirectory: userHomeDirectory)
    }
}

public enum RegistryError: Error, CustomStringConvertible, Equatable {
    case itemNotFound(String)
    case missingCurrentVersion(String)
    case duplicateItem(String)
    case invalidManifest([String])
    case commandFailed(String)
    case commandFieldNotFound(String)
    case checkFileNotReadable(String)

    public var description: String {
        switch self {
        case let .itemNotFound(id):
            return "\(redacted(id)): item not found"
        case let .missingCurrentVersion(id):
            return "\(redacted(id)): current version is unavailable"
        case let .duplicateItem(id):
            return "\(redacted(id)): duplicate item; pass --replace to overwrite"
        case let .invalidManifest(errors):
            return "manifest invalid: \(errors.map(redacted).joined(separator: "; "))"
        case let .commandFailed(message):
            return redacted(message)
        case let .commandFieldNotFound(field):
            return "\(redacted(field)): command field not found"
        case let .checkFileNotReadable(path):
            return "check.file not readable: \(redacted(path))"
        }
    }

    private func redacted(_ text: String) -> String {
        SecretRedactor.redact(text)
    }
}

public struct ImportSummary: Codable, Equatable {
    public var added: [String]
    public var replaced: [String]

    public init(added: [String], replaced: [String]) {
        self.added = added
        self.replaced = replaced
    }
}
