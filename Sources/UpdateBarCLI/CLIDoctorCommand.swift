import ArgumentParser
import Foundation
import UpdateBarCore

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check local UpdateBar installation and data files.",
        shouldDisplay: false
    )

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    func run() throws {
        let paths = AppPaths()
        let checks = [
            checkHome(paths),
            checkConfig(paths),
            checkManifest(paths),
            checkState(paths),
        ]
        let payload = DoctorPayload(
            ok: checks.allSatisfy(\.ok),
            home: paths.homeDirectory.path,
            checks: checks
        )

        if json {
            try printJSON(payload)
        } else {
            printHuman(payload)
        }

        if !payload.ok {
            throw ExitCode.failure
        }
    }

    private func printHuman(_ payload: DoctorPayload) {
        writeStdout("STATUS\tCHECK\tPATH\tMESSAGE")
        for check in payload.checks {
            writeStdout(
                [
                    check.ok ? "OK" : "FAIL",
                    check.name,
                    check.path ?? "-",
                    check.message,
                ].joined(separator: "\t"))
        }
    }

    private func checkHome(_ paths: AppPaths) -> DoctorCheckPayload {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(
            atPath: paths.homeDirectory.path,
            isDirectory: &isDirectory
        )
        if exists && !isDirectory.boolValue {
            return DoctorCheckPayload(
                name: "home",
                ok: false,
                path: paths.homeDirectory.path,
                message: "path exists but is not a directory"
            )
        }
        return DoctorCheckPayload(
            name: "home",
            ok: true,
            path: paths.homeDirectory.path,
            message: exists ? "directory exists" : "directory will be created when needed"
        )
    }

    private func checkConfig(_ paths: AppPaths) -> DoctorCheckPayload {
        checkFile(name: "config", path: paths.configFile.path) {
            _ = try ConfigStore(paths: paths).loadExistingOrDefault()
        }
    }

    private func checkManifest(_ paths: AppPaths) -> DoctorCheckPayload {
        checkFile(name: "manifest", path: paths.manifestFile.path) {
            _ = try ManifestStore(paths: paths).loadExistingOrEmpty()
        }
    }

    private func checkState(_ paths: AppPaths) -> DoctorCheckPayload {
        checkFile(name: "state", path: paths.stateFile.path) {
            _ = try StateStore(paths: paths).loadExistingOrEmpty()
        }
    }

    private func checkFile(
        name: String,
        path: String,
        load: () throws -> Void
    ) -> DoctorCheckPayload {
        do {
            try load()
            let exists = FileManager.default.fileExists(atPath: path)
            return DoctorCheckPayload(
                name: name,
                ok: true,
                path: path,
                message: exists ? "readable" : "not created yet"
            )
        } catch {
            return DoctorCheckPayload(
                name: name,
                ok: false,
                path: path,
                message: sanitizedErrorMessage(for: error)
            )
        }
    }
}
