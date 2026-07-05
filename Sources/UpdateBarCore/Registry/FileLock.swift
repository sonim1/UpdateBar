import Foundation

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

struct FileLock {
    private let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            throw StoreError.writeFailed(path: url.path, reason: "failed to open lock file")
        }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else {
            throw StoreError.writeFailed(path: url.path, reason: "failed to acquire lock")
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}
