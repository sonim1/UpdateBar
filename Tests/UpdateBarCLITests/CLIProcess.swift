import Foundation

struct CLIProcess {
    static func run(
        _ arguments: [String],
        home: URL,
        stdin input: String? = nil,
        environment overrides: [String: String?] = [:]
    ) throws -> Result {
        let process = Process()
        process.executableURL = try updatebarBinary()
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["UPDATEBAR_HOME"] = home.path
        for (key, value) in overrides {
            environment[key] = value
        }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin

        try process.run()
        if let input {
            stdin.fileHandleForWriting.write(Data(input.utf8))
        }
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()

        return Result(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    static func runAndInterrupt(
        _ arguments: [String],
        home: URL,
        after delay: TimeInterval,
        environment overrides: [String: String?] = [:]
    ) throws -> Result {
        let process = Process()
        process.executableURL = try updatebarBinary()
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["UPDATEBAR_HOME"] = home.path
        for (key, value) in overrides {
            environment[key] = value
        }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin

        try process.run()
        try stdin.fileHandleForWriting.close()
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            process.interrupt()
        }
        process.waitUntilExit()

        return Result(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private static func updatebarBinary() throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let build = root.appendingPathComponent(".build")
        let candidates = [
            build.appendingPathComponent("debug/updatebar"),
            build.appendingPathComponent("arm64-apple-macosx/debug/updatebar"),
            build.appendingPathComponent("x86_64-apple-macosx/debug/updatebar")
        ]
        if let candidate = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return candidate
        }
        guard let enumerator = FileManager.default.enumerator(at: build, includingPropertiesForKeys: nil) else {
            throw Error.binaryNotFound
        }
        for case let url as URL in enumerator where url.lastPathComponent == "updatebar" {
            if url.path.contains(".dSYM") { continue }
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        throw Error.binaryNotFound
    }

    struct Result {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    enum Error: Swift.Error {
        case binaryNotFound
    }
}

func makeTemporaryHome(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
