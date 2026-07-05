import Foundation

public struct ManifestStore {
    private let paths: AppPaths
    private let fileManager: FileManager

    public init(paths: AppPaths = AppPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func load() throws -> Manifest {
        try ensureHome()
        if !fileManager.fileExists(atPath: paths.manifestFile.path) {
            let manifest = emptyManifest(now: Date())
            try save(manifest)
            return manifest
        }
        return try readExistingManifest()
    }

    public func loadExistingOrEmpty(now: Date = Date()) throws -> Manifest {
        if !fileManager.fileExists(atPath: paths.manifestFile.path) {
            try AppHomeDirectory.ensureIfExists(paths.homeDirectory, fileManager: fileManager)
            return emptyManifest(now: now)
        }
        try ensureHome()
        return try readExistingManifest()
    }

    private func readExistingManifest() throws -> Manifest {
        do {
            let data = try Data(contentsOf: paths.manifestFile)
            return try JSONDecoder.updateBar.decode(Manifest.self, from: data)
        } catch {
            throw StoreError.corruptFile(
                path: paths.manifestFile.path, reason: storeErrorReason(for: error))
        }
    }

    public func save(_ manifest: Manifest) throws {
        try ensureHome()
        do {
            let data = try JSONEncoder.updateBar.encode(manifest)
            try AtomicFileWriter.write(data, to: paths.manifestFile, fileManager: fileManager)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.writeFailed(
                path: paths.manifestFile.path, reason: String(describing: error))
        }
    }

    public func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        try ensureHome()
        return try FileLock(
            url: paths.homeDirectory.appendingPathComponent("manifest.lock"),
            fileManager: fileManager
        ).withExclusiveLock(body)
    }

    private func ensureHome() throws {
        try AppHomeDirectory.ensure(paths.homeDirectory, fileManager: fileManager)
    }

    private func emptyManifest(now: Date) -> Manifest {
        Manifest(
            schemaVersion: 1,
            items: [],
            provenance: Provenance(createdBy: "updatebar", createdAt: now, updatedAt: now)
        )
    }
}
