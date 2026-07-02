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
        let manifest = refresh
            ? try manifestStore.load()
            : try manifestStore.loadExistingOrEmpty(now: now)
        let state: State

        if refresh {
            let config = try configStore.load()
            state = try stateStore.withExclusiveLock {
                let lockedState = try stateStore.load(now: now)
                let refreshed = markStaleItemsChecking(
                    manifest: manifest,
                    state: lockedState,
                    config: config,
                    now: now
                )
                try stateStore.save(refreshed)
                return refreshed
            }
        } else {
            state = try stateStore.loadExistingOrEmpty(now: now)
        }

        return StatusSnapshot.from(manifest: manifest, state: state, now: now)
    }

    private func markStaleItemsChecking(
        manifest: Manifest,
        state: State,
        config: Config,
        now: Date
    ) -> State {
        var copy = state
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
