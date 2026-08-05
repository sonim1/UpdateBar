import Foundation

/// Cooperative "finish what is running, start nothing new" flag.
///
/// Distinct from `CancellationToken`: cancelling kills the running process and
/// can leave a package half-installed, while stopping only drains the queue.
public final class UpdateStopSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    public init() {}

    public var isStopRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    public func requestStop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}
