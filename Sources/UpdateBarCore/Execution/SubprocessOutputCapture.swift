import Foundation

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

package final class SubprocessOutputCapture: @unchecked Sendable {
    private let stdout: FileHandle
    private let stderr: FileHandle
    private let stdoutData: LockedOutputData
    private let stderrData: LockedOutputData
    private let readersFinished = DispatchGroup()
    private let stopReaders = ReaderStopSignal()

    package init(stdout: FileHandle, stderr: FileHandle, maxOutputBytes: Int) throws {
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutData = LockedOutputData(maxBytes: maxOutputBytes)
        self.stderrData = LockedOutputData(maxBytes: maxOutputBytes)
        try Self.configureNonBlocking(stdout)
        try Self.configureNonBlocking(stderr)
    }

    package func start() {
        startReading(stdout, into: stdoutData)
        startReading(stderr, into: stderrData)
    }

    package func finish(timeout: TimeInterval) {
        stopReaders.requestStop()
        if readersFinished.wait(timeout: .now() + timeout) == .success {
            return
        }
        stopReaders.forceStop()
        _ = readersFinished.wait(timeout: .now() + 1.0)
    }

    package var capturedStdout: String {
        String(decoding: stdoutData.data(), as: UTF8.self)
    }

    package var capturedStderr: String {
        String(decoding: stderrData.data(), as: UTF8.self)
    }

    private func startReading(_ handle: FileHandle, into output: LockedOutputData) {
        readersFinished.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            Self.drain(handle, into: output, stopReaders: stopReaders)
            readersFinished.leave()
        }
    }

    private static func configureNonBlocking(_ handle: FileHandle) throws {
        let fd = handle.fileDescriptor
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else {
            throw ExecutionError.launchFailed("failed to inspect output pipe flags")
        }
        guard fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw ExecutionError.launchFailed("failed to configure output pipe")
        }
    }

    private static func drain(
        _ handle: FileHandle,
        into output: LockedOutputData,
        stopReaders: ReaderStopSignal
    ) {
        defer { handle.closeFile() }
        let fd = handle.fileDescriptor
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !stopReaders.isForced {
            let count = buffer.withUnsafeMutableBufferPointer { pointer in
                read(fd, pointer.baseAddress, pointer.count)
            }

            if count > 0 {
                output.append(Data(buffer.prefix(count)))
                continue
            }
            if count == 0 {
                break
            }
            if errno == EINTR {
                continue
            }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                if stopReaders.isRequested {
                    break
                }
                Thread.sleep(forTimeInterval: 0.005)
                continue
            }
            break
        }
    }
}

private final class LockedOutputData: @unchecked Sendable {
    private let lock = NSLock()
    private let maxBytes: Int
    private var storage = Data()

    init(maxBytes: Int) {
        self.maxBytes = max(0, maxBytes)
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let remaining = maxBytes - storage.count
        if remaining > 0 {
            storage.append(data.prefix(remaining))
        }
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class ReaderStopSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var requested = false
    private var forced = false

    var isRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }

    var isForced: Bool {
        lock.lock()
        defer { lock.unlock() }
        return forced
    }

    func requestStop() {
        lock.lock()
        requested = true
        lock.unlock()
    }

    func forceStop() {
        lock.lock()
        forced = true
        lock.unlock()
    }
}
