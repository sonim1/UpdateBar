import Foundation

/// Runs work items with bounded concurrency while guaranteeing that two items
/// sharing a lane never run at the same time.
///
/// `@unchecked Sendable` because every mutable field is only touched inside
/// `queue`, the same discipline `ProcessRunner` and `LockedData` use. The
/// stored `work` closure is invoked from worker threads by design.
final class UpdateScheduler<Payload, Output>: @unchecked Sendable {
    struct Item {
        let index: Int
        let lane: String
        let payload: Payload
    }

    private let queue = DispatchQueue(label: "com.updatebar.update-scheduler")
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
                try queue.sync { try onStart?(item.payload) }
                let output = try work(item.payload)
                complete(item, output: output)
            } catch {
                fail(item, error: error)
            }
        }
    }

    /// Marks a lane busy and hands back the item, or returns nil when this
    /// worker has nothing left it is allowed to start.
    private func claimNextItem() -> Item? {
        queue.sync {
            if drained || thrown != nil { return nil }
            if stopSignal?.isStopRequested == true {
                drained = true
                return nil
            }
            guard
                let position = pending.firstIndex(where: { !busyLanes.contains($0.lane) })
            else {
                return nil
            }
            let item = pending.remove(at: position)
            busyLanes.insert(item.lane)
            return item
        }
    }

    private func complete(_ item: Item, output: Output) {
        queue.sync {
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
        }
    }

    private func fail(_ item: Item, error: Error) {
        queue.sync {
            busyLanes.remove(item.lane)
            if thrown == nil { thrown = error }
        }
    }
}
