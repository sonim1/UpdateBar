import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

enum AtomicFileWriter {
    static func write(_ data: Data, to url: URL, fileManager: FileManager) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        )
        var shouldCleanUpTemp = true
        defer {
            if shouldCleanUpTemp {
                try? fileManager.removeItem(at: temp)
            }
        }
        try data.write(to: temp)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
        guard rename(temp.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        shouldCleanUpTemp = false
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
