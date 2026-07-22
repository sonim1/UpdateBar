import Foundation
import UpdateBarCore

public struct MenuBarStateChangeMonitor {
    private let urls: [URL]
    private let fileManager: FileManager
    private var previous: [FileStamp]

    public init(paths: AppPaths = AppPaths(), fileManager: FileManager = .default) {
        self.urls = [
            paths.manifestFile,
            paths.stateFile,
            paths.configFile,
            paths.historyFile,
        ]
        self.fileManager = fileManager
        self.previous = Self.stamps(for: urls, fileManager: fileManager)
    }

    public mutating func poll() -> Bool {
        let current = Self.stamps(for: urls, fileManager: fileManager)
        guard current != previous else { return false }
        previous = current
        return true
    }

    private static func stamps(for urls: [URL], fileManager: FileManager) -> [FileStamp] {
        urls.map { url in
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
                return FileStamp()
            }
            return FileStamp(
                modificationDate: attributes[.modificationDate] as? Date,
                size: (attributes[.size] as? NSNumber)?.uint64Value,
                fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
            )
        }
    }
}

private struct FileStamp: Equatable {
    var modificationDate: Date?
    var size: UInt64?
    var fileNumber: UInt64?
}
