import ArgumentParser
import Foundation
import UpdateBarCore

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Scan installed local tools and register selected recipes."
    )

    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    @Flag(name: .long, help: "Overwrite existing items with matching ids.")
    var replace = false

    @Option(name: .long, help: "Comma-separated candidate ids, numbers, or all.")
    var select: String?

    @Option(name: .long, help: .hidden)
    var detectors: String?

    @Option(name: .long, help: "Filter by category: ai-agent, package-manager, runtime-sdk, shell-utility, cloud-devops, library, codex-skill, or mcp-server.")
    var category: String?

    func run() throws {
        let categoryFilter = try parseCategoryFilter(category)
        let selectedDetectors = try parseDetectors(categoryFilter: categoryFilter)
        let report = try filteredReport(
            detectors: selectedDetectors,
            categoryFilter: categoryFilter
        )
        let selectedIDs = try parseSelection(from: report)

        do {
            let summary = try InitService().register(
                candidates: report.candidates,
                selectedIDs: selectedIDs,
                replace: replace
            )
            try output(InitPayload(summary: summary, errors: []))
        } catch let error as InitServiceError {
            try output(
                InitPayload(
                    added: [],
                    replaced: [],
                    skipped: [],
                    errors: [sanitizedErrorMessage(for: error)]
                )
            )
            throw ExitCode.failure
        }
    }

    private func filteredReport(
        detectors: [ScanDetector],
        categoryFilter: String?
    ) throws -> ScanReport {
        var report = try ScanService().scan(detectors: detectors)
        if let category = categoryFilter {
            report.candidates = report.candidates.filter { $0.category == category }
        }
        return report
    }

    private func parseDetectors(categoryFilter: String?) throws -> [ScanDetector] {
        try parseScanDetectors(detectors, categoryFilter: categoryFilter)
    }

    private func parseSelection(from report: ScanReport) throws -> [String] {
        if let select {
            let values = parseSelectionTokens(select)
            guard !values.isEmpty else {
                throw ValidationError("select: expected at least one candidate id")
            }
            let importable = importableCandidates(from: report)
            if values.count == 1, values[0] == "all" {
                guard !importable.isEmpty else {
                    throw noImportableCandidatesError(for: report)
                }
                return importable.map(\.id)
            }
            return try parseSelectionValues(values, candidates: importable)
        }

        if json {
            throw ValidationError("init --json requires --select")
        }

        let importable = importableCandidates(from: report)
        guard !importable.isEmpty else {
            throw noImportableCandidatesError(for: report)
        }
        printImportable(importable)
        let prompt = "Select items to add (numbers, ids, or all): "
        writeStderr(prompt, addNewline: false)
        guard let line = readLine(),
            !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw selectionRequiredError()
        }
        return try parseInteractiveSelection(line, candidates: importable)
    }

    private func importableCandidates(from report: ScanReport) -> [ScanCandidate] {
        report.candidates.filter {
            $0.capability == .full && $0.recipe != nil
        }
    }

    private func noImportableCandidatesError(for report: ScanReport) -> ValidationError {
        if report.candidates.isEmpty {
            return ValidationError(
                "No importable candidates found. "
                    + "Check that the tool is installed and ensure any category filter is not too strict."
            )
        }

        return ValidationError(
            "No importable candidates found. "
                + "Detected candidates are review-only and cannot be imported yet."
        )
    }

    private func parseInteractiveSelection(
        _ line: String,
        candidates: [ScanCandidate]
    ) throws -> [String] {
        let values = parseSelectionTokens(line)
        guard !values.isEmpty else {
            throw selectionRequiredError()
        }
        return try parseSelectionValues(values, candidates: candidates)
    }

    private func selectionRequiredError() -> ValidationError {
        ValidationError(
            "selection required; enter numbers, ids, or all, or pass --select all for headless use"
        )
    }

    private func parseSelectionValues(
        _ values: [String],
        candidates: [ScanCandidate]
    ) throws -> [String] {
        if values.count == 1 && values[0].lowercased() == "all" {
            return candidates.map(\.id)
        }
        return try unique(values).map { value in
            if let index = Int(value) {
                guard index >= 1, index <= candidates.count else {
                    throw ValidationError("\(value): selection out of range")
                }
                return candidates[index - 1].id
            }
            return value
        }
    }

    private func parseSelectionTokens(_ value: String) -> [String] {
        parseList(value)
    }

    private func printImportable(_ candidates: [ScanCandidate]) {
        print("Found \(candidates.count) importable candidate(s)")
        print("")
        print("Recommended")
        for (index, candidate) in candidates.enumerated() {
            let version = candidate.installedVersion.map { " \($0)" } ?? ""
            let name = "[\(index + 1)] \(candidate.name)\(version)"
            let fields = [
                name,
                candidate.category,
                candidate.detector.rawValue,
                candidate.id,
            ]
            print(fields.joined(separator: "\t"))
        }
        print("")
    }

    private func output(_ payload: InitPayload) throws {
        if json {
            try printJSON(payload)
        } else if payload.ok {
            let message = [
                "added \(payload.added.count)",
                "replaced \(payload.replaced.count)",
                "skipped \(payload.skipped.count)",
            ].joined(separator: ", ")
            print(message)
            if !payload.skipped.isEmpty {
                print("Skipped: \(payload.skipped.joined(separator: ", "))")
                print("Pass --replace to overwrite skipped item(s).")
            }
            printApprovalAndCheckNextSteps(for: payload.added + payload.replaced)
        } else {
            for error in payload.errors {
                writeStderr(error)
            }
        }
    }
}
