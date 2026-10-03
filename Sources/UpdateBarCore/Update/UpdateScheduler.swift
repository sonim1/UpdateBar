import Foundation

/// Runs work items with bounded concurrency while guaranteeing that two items
/// sharing a lane never run at the same time. A global barrier lane also
/// excludes every other lane while it is executing.
///
/// `@unchecked Sendable` because every mutable field is protected by
/// `condition`. The
/// stored `work` closure is invoked from worker threads by design.
final class UpdateScheduler<Payload, Output>: @unchecked Sendable {
    struct Item {
        let index: Int
        let lane: String
        let payload: Payload
    }

    private let condition = NSCondition()
    private let stopSignal: UpdateStopSignal?
    private let onStart: ((Payload) throws -> Void)?
    private let onFinish: ((Output) throws -> Void)?
    private let shouldStopAfter: ((Output) -> Bool)?
    private let work: (Payload) throws -> Output

    private var pending: [Item]
    private var busyLanes: Set<String> = []
    private var outputs: [Int: Output] = [:]
    private var thrown: Error?
    private var drained = false

    init(
        items: [Item],
        stopSignal: UpdateStopSignal?,
        onStart: ((Payload) throws -> Void)?,
        onFinish: ((Output) throws -> Void)?,
        shouldStopAfter: ((Output) -> Bool)?,
        work: @escaping (Payload) throws -> Output
    ) {
        self.pending = items
        self.stopSignal = stopSignal
        self.onStart = onStart
        self.onFinish = onFinish
        self.shouldStopAfter = shouldStopAfter
        self.work = work
    }

    /// Blocks until every started item finishes. Items that were never started
    /// are absent from the result.
    func run(maxConcurrent: Int) throws -> [Int: Output] {
        let workerCount = min(max(1, maxConcurrent), max(1, pending.count))
        guard !pending.isEmpty else { return [:] }

        let group = DispatchGroup()
        for _ in 0..<workerCount {
            DispatchQueue.global(qos: .userInitiated).async(group: group) { [self] in
                drainLoop()
            }
        }
        group.wait()

        if let thrown { throw thrown }
        return outputs
    }

    private func drainLoop() {
        while let item = claimNextItem() {
            do {
                try start(item)
                let output = try work(item.payload)
                complete(item, output: output)
            } catch {
                fail(item, error: error)
            }
        }
    }

    /// Idle workers wait for busy lanes to finish so a barrier does not
    /// permanently reduce the worker pool to one thread.
    private func claimNextItem() -> Item? {
        condition.lock()
        defer { condition.unlock() }
        while !pending.isEmpty {
            if drained || thrown != nil { return nil }
            if stopSignal?.isStopRequested == true {
                drained = true
                return nil
            }
            if let position = pending.firstIndex(where: canClaim) {
                let item = pending.remove(at: position)
                busyLanes.insert(item.lane)
                return item
            }
            condition.wait()
        }
        return nil
    }

    private func start(_ item: Item) throws {
        condition.lock()
        defer { condition.unlock() }
        try onStart?(item.payload)
    }

    private func canClaim(_ item: Item) -> Bool {
        if item.lane == UpdateLane.globalBarrierKey {
            return busyLanes.isEmpty
        }
        return !busyLanes.contains(item.lane)
            && !busyLanes.contains(UpdateLane.globalBarrierKey)
    }

    private func complete(_ item: Item, output: Output) {
        condition.lock()
        defer { condition.unlock() }
        busyLanes.remove(item.lane)
        outputs[item.index] = output
        if shouldStopAfter?(output) == true {
            drained = true
        }
        do {
            try onFinish?(output)
        } catch {
            if thrown == nil { thrown = error }
        }
        condition.broadcast()
    }

    private func fail(_ item: Item, error: Error) {
        condition.lock()
        defer { condition.unlock() }
        busyLanes.remove(item.lane)
        if thrown == nil { thrown = error }
        condition.broadcast()
    }
}
