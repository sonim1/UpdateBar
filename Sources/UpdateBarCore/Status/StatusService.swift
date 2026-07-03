import Foundation

public struct StatusService {
    private let manifestStore: ManifestStore
    private let stateStore: StateStore
    private let configStore: ConfigStore
    private let now: () -> Date

    public init(
        manifestStore: ManifestStore = ManifestStore(),
        stateStore: StateStore = StateStore(),
        configStore: ConfigStore = ConfigStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.manifestStore = manifestStore
        self.stateStore = stateStore
        self.configStore = configStore
        self.now = now
    }

    public func snapshot(refresh: Bool = false) throws -> StatusSnapshot {
        let now = now()
        let manifest = try manifestStore.loadExistingOrEmpty(now: now)
        let state: State

        if refresh {
            try validate(manifest)
            if manifest.items.isEmpty {
                state = try stateStore.loadExistingOrEmpty(now: now)
                return StatusSnapshot.from(manifest: manifest, state: state, now: now)
            }

            let config = try configStore.loadExistingOrDefault()
            state = try stateStore.withExclusiveLock {
                let lockedState = try stateStore.loadExistingOrEmpty(now: now)
                let refreshed = markStaleItemsChecking(
                    manifest: manifest,
                    state: lockedState,
                    config: config,
                    now: now
                )
                if refreshed != lockedState {
                    try stateStore.save(refreshed)
                }
                return refreshed
            }
        } else {
            state = try stateStore.loadExistingOrEmpty(now: now)
        }

        return StatusSnapshot.from(manifest: manifest, state: state, now: now)
    }

    private func validate(_ manifest: Manifest) throws {
        let data = try JSONEncoder.updateBar.encode(manifest)
        let result = try ManifestValidator.validate(data: data)
        if !result.isValid {
            throw RegistryError.invalidManifest(result.errors)
        }
    }

    private func markStaleItemsChecking(
        manifest: Manifest,
        state: State,
        config: Config,
        now: Date
    ) -> State {
        var copy = state
        var changed = false
        for recipe in manifest.items {
            guard recipe.enabled, recipe.pin == nil, TrustPolicy.isCheckApproved(recipe) else {
                continue
            }
            let existing = copy.items[recipe.id]
            if let lastChecked = existing?.lastChecked,
                now.timeIntervalSince(lastChecked) < TimeInterval(config.refresh.interval.seconds)
            {
                continue
            }
            let refreshed = ItemState(
                current: existing?.current,
                latest: existing?.latest,
                status: .checking,
                lastChecked: existing?.lastChecked,
                error: nil,
                backoffUntil: nil
            )
            if existing != refreshed {
                copy.items[recipe.id] = refreshed
                changed = true
            }
        }
        if changed {
            copy.generatedAt = now
        }
        return copy
    }
}
