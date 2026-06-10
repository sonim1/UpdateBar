import Foundation

public struct StateStore {
    private let paths: AppPaths
    private let fileManager: FileManager

    public init(paths: AppPaths = AppPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func load(now: Date = Date()) throws -> State {
        try ensureHome()
        if !fileManager.fileExists(atPath: paths.stateFile.path) {
            let state = State(schemaVersion: 1, generatedAt: now, items: [:])
            try save(state)
            return state
        }
        do {
            let data = try Data(contentsOf: paths.stateFile)
            return try JSONDecoder.updateBar.decode(State.self, from: data)
        } catch {
            throw StoreError.corruptFile(path: paths.stateFile.path, reason: String(describing: error))
        }
    }

    public func save(_ state: State) throws {
        try ensureHome()
        do {
            let data = try JSONEncoder.updateBar.encode(state)
            try AtomicFileWriter.write(data, to: paths.stateFile, fileManager: fileManager)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.writeFailed(path: paths.stateFile.path, reason: String(describing: error))
        }
    }

    public func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        try FileLock(
            url: paths.homeDirectory.appendingPathComponent("state.lock"),
            fileManager: fileManager
        ).withExclusiveLock(body)
    }

    private func ensureHome() throws {
        try fileManager.createDirectory(at: paths.homeDirectory, withIntermediateDirectories: true)
    }
}
