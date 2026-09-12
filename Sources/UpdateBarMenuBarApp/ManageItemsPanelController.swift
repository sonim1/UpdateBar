#if os(macOS)
    import AppKit
    import SwiftUI
    import UpdateBarCore
    import UpdateBarMenuBar

    @MainActor
    final class ItemsDashboardStore: ObservableObject {
        @Published private(set) var model = MenuBarPopoverModel()
        @Published private(set) var selection = ManageItemsSelectionModel()
        @Published var detailItemID: String?
        @Published private(set) var mutationError: String?

        let supportsStopping: Bool
        private let service: any MenuBarServicing
        private let onChanged: () -> Void
        private let actions: MenuBarPopoverActions
        private let presentationModel = ManageItemsModel()
        private var mutationGate = ManageItemsMutationGate()
        private var pendingEnabled: [String: Bool] = [:]

        var onError: (Error) -> Void = { _ in }

        init(
            service: any MenuBarServicing,
            onChanged: @escaping () -> Void,
            actions: MenuBarPopoverActions,
            supportsStopping: Bool = true
        ) {
            self.service = service
            self.onChanged = onChanged
            self.actions = actions
            self.supportsStopping = supportsStopping
        }

        var sections: [ManageItemsSection] {
            presentationModel.sections(from: model, query: selection.query)
        }

        var primaryAction: ManageItemsPrimaryAction {
            presentationModel.primaryAction(
                from: model, query: selection.query, selectedIDs: selection.selectedIDs
            )
        }

        var detailItem: StatusItem? {
            guard let detailItemID else { return nil }
            return model.item(for: detailItemID)
        }

        func apply(_ incoming: MenuBarPopoverModel) {
            guard mutationGate.accepts(incoming.state.allItems) else { return }
            pendingEnabled.removeAll()
            model.update(
                state: incoming.state,
                approvals: incoming.approvals,
                progress: incoming.progress,
                activeActionTitle: incoming.activeActionTitle,
                isUpdateAction: incoming.isUpdateAction,
                isRefreshing: incoming.isRefreshing,
                stopRequested: incoming.stopRequested,
                notice: incoming.notice,
                errorMessage: incoming.errorMessage
            )
            let visibleIDs = Set(
                presentationModel.sections(from: model, query: selection.query)
                    .flatMap { $0.items.map(\.id) }
            )
            selection.reconcile(with: model, visibleIDs: visibleIDs)
            if detailItem == nil { detailItemID = nil }
        }

        func setQuery(_ query: String) {
            guard !model.isBusy else { return }
            selection.setQuery(query)
            objectWillChange.send()
        }

        func toggleSelection(_ item: StatusItem) {
            guard !model.isBusy, !mutationGate.isPending else { return }
            selection.toggle(item: item, in: model)
            objectWillChange.send()
        }

        func clearSelection() {
            selection.clear()
            objectWillChange.send()
        }

        func showDetails(_ item: StatusItem) {
            detailItemID = item.id
        }

        func closeDetails() {
            detailItemID = nil
        }

        func check() {
            guard !model.isBusy, !mutationGate.isPending else { return }
            actions.check()
        }

        func update() {
            guard !model.isBusy, !mutationGate.isPending else { return }
            let ids = primaryAction.ids
            guard !ids.isEmpty else { return }
            actions.update(ids)
        }

        func retryFailed() {
            guard !model.isBusy, !mutationGate.isPending else { return }
            let ids = model.retryIDs
            guard !ids.isEmpty else { return }
            actions.retry(ids)
        }

        func stop() {
            guard supportsStopping, model.isUpdating, !model.stopRequested else { return }
            actions.stop()
        }

        func setAcknowledged(_ acknowledged: Bool, id: String, field: String) {
            model.setAcknowledged(acknowledged, id: id, field: field)
        }

        func setApproval(id: String, field: String) {
            guard let reviewed = model.reviewedApproval(id: id, field: field) else { return }
            model.setAcknowledged(false, id: id, field: field)
            actions.setApproval(id, reviewed, !reviewed.approved)
        }

        func setEnabled(id: String, enabled: Bool) {
            guard !model.isBusy, !mutationGate.isPending,
                model.item(for: id) != nil
            else { return }
            mutationError = nil
            mutationGate.begin(id: id, enabled: enabled)
            pendingEnabled[id] = enabled
            objectWillChange.send()
            DispatchQueue.global(qos: .userInitiated).async { [service, weak self] in
                do {
                    try service.setEnabled(id: id, enabled: enabled)
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.onChanged()
                    }
                } catch {
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.mutationGate.cancel()
                        self.pendingEnabled[id] = nil
                        self.mutationError = SecretRedactor.redact(String(describing: error))
                        self.onError(error)
                        self.objectWillChange.send()
                    }
                }
            }
        }

        func isMutationPending(id: String) -> Bool {
            mutationGate.isPending(id: id)
        }

        func displayedEnabledState(for item: StatusItem) -> Bool {
            pendingEnabled[item.id] ?? (item.status != .disabled)
        }

        func statusText(for item: StatusItem) -> String {
            presentationModel.statusText(for: item, in: model)
        }

        func phase(for item: StatusItem) -> MenuBarPopoverItemPhase {
            presentationModel.phase(for: item, in: model)
        }
    }

    @MainActor
    final class ManageItemsViewController: NSViewController {
        let store: ItemsDashboardStore
        let hostingController: NSHostingController<ItemsDashboardView>

        var onError: (Error) -> Void {
            get { store.onError }
            set { store.onError = newValue }
        }

        init(
            service: any MenuBarServicing,
            onChanged: @escaping () -> Void,
            actions: MenuBarPopoverActions,
            supportsStopping: Bool = true
        ) {
            let store = ItemsDashboardStore(
                service: service, onChanged: onChanged, actions: actions,
                supportsStopping: supportsStopping
            )
            self.store = store
            self.hostingController = NSHostingController(rootView: ItemsDashboardView(store: store))
            hostingController.sizingOptions = []
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func loadView() {
            view = hostingController.view
        }

        func apply(model: MenuBarPopoverModel) {
            _ = view
            store.apply(model)
        }
    }
#endif
