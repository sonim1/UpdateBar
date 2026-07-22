# Agent-Friendly Command Field Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe field-specific editing for `check.cmd`, `latest.cmd`, and `update.cmd`, including non-interactive file/stdin input and JSON output for external AI agents.

**Architecture:** Extend the existing `edit` command rather than creating a second mutation command. Keep field resolution and input normalization inside the CLI edit boundary, reuse the existing recipe/manifest validators and fingerprint invalidation, and add small workflow helpers for human next-step guidance. Machine-readable check and approval payloads remain unchanged.

**Tech Stack:** Swift 5.9+, swift-argument-parser, Foundation, XCTest, existing UpdateBarCore manifest/trust services.

---

## File Map

- Modify `Sources/UpdateBarCLI/CLIEditCommand.swift`: parse field/input/JSON options, edit one command field, preserve whole-recipe editor behavior, validate, save, and report changes.
- Modify `Sources/UpdateBarCLI/CLIPayloads.swift`: add the stable redacted JSON payload for field edits.
- Modify `Sources/UpdateBarCLI/CLIWorkflowSupport.swift`: format `updatebar edit <id> --field <field>` next-step commands.
- Modify `Sources/UpdateBarCLI/CLICheckCommand.swift`: suggest edits only for blocked fields used by checking.
- Modify `Sources/UpdateBarCLI/CLIManageCommands.swift`: pair each unapproved field with edit and approve next steps.
- Modify `Sources/UpdateBarCore/Security/TrustPolicy.swift`: expose the ordered set of unapproved command fields required by check.
- Modify `Sources/UpdateBarCLI/CLIAddCommand.swift`: expose the existing agent-safe add command in root help.
- Modify `Sources/UpdateBarCLI/CLIDocumentCommands.swift`: document the non-interactive agent edit loop.
- Modify `README.md` and `docs/cli.md`: document human and agent-facing syntax.
- Modify `Tests/UpdateBarCLITests/EditCommandTests.swift`: cover editor, file, stdin, JSON, validation, no-op, and approval invalidation behavior.
- Modify `Tests/UpdateBarCLITests/CheckCommandTests.swift`: cover check-specific edit suggestions.
- Modify `Tests/UpdateBarCLITests/ManageItemCommandTests.swift`: cover approval-screen edit suggestions.
- Modify `Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift` and `Tests/UpdateBarCLITests/GuideTemplateCommandTests.swift`: cover help and agent-guide discoverability.
- Modify `Tests/UpdateBarCoreTests/TrustPolicyTests.swift`: cover ordered check-required approval fields.

### Task 1: Field-Specific Edit Input, Persistence, and JSON

**Files:**
- Modify: `Tests/UpdateBarCLITests/EditCommandTests.swift`
- Modify: `Sources/UpdateBarCLI/CLIEditCommand.swift`
- Modify: `Sources/UpdateBarCLI/CLIPayloads.swift`

- [ ] **Step 1: Write failing field-edit tests**

Add focused tests to `EditCommandTests` using a fresh temporary home per mutation. The tests must prove all three fields can be replaced, stdin JSON is clean, an editor-added newline is removed, and fingerprint invalidation is retained:

```swift
func testEditCommandFieldsFromFiles() throws {
    let cases: [(String, String, (Recipe) -> String?)] = [
        ("check.cmd", "printf 'tool 2.0.0'", {
            if case .command(let command) = $0.check { return command }
            return nil
        }),
        ("latest.cmd", "printf 'tool 2.1.0'", { $0.latest.cmd }),
        ("update.cmd", "printf upgraded", { $0.update.cmd }),
    ]

    for (field, command, value) in cases {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-field-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let input = home.appendingPathComponent("command.txt")
        try Data("\(command)\n".utf8).write(to: input)

        let result = try CLIProcess.run(
            ["edit", "tool", "--field", field, "--from", input.path], home: home)
        let stored = try XCTUnwrap(ManifestStore(paths: paths).load().item(id: "tool"))

        XCTAssertEqual(result.exitCode, 0, field)
        XCTAssertEqual(value(stored), command, field)
        XCTAssertNil(stored.trust.approvedCommands[field], field)
        XCTAssertTrue(result.stdout.contains("edited tool \(field)"), field)
        XCTAssertTrue(result.stdout.contains("updatebar approvals tool"), field)
    }
}

func testEditFieldFromStdinReturnsRedactedJSON() throws {
    let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-field-tests")
    let paths = AppPaths(homeDirectory: home)
    try saveManifest(paths: paths)

    let result = try CLIProcess.run(
        ["edit", "tool", "--field", "check.cmd", "--from", "-", "--json"],
        home: home,
        stdin: "printf 'tool 3.0.0'\n"
    )
    let payload = try JSONDecoder.updateBar.decode(
        EditResponse.self, from: Data(result.stdout.utf8))

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.stderr, "")
    XCTAssertTrue(payload.ok)
    XCTAssertEqual(payload.id, "tool")
    XCTAssertEqual(payload.field, "check.cmd")
    XCTAssertTrue(payload.changed)
    XCTAssertEqual(payload.item.check, .command("printf 'tool 3.0.0'"))
}

func testEditFieldEditorReceivesOnlyCommandText() throws {
    let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-field-tests")
    let paths = AppPaths(homeDirectory: home)
    try saveManifest(paths: paths)
    let editor = try editorScript(
        home: home,
        body: #"test "$(cat "$1")" = "printf updated" && printf 'printf changed\n' > "$1""#)

    let result = try CLIProcess.run(
        ["edit", "tool", "--field", "update.cmd"],
        home: home,
        environment: ["EDITOR": editor.path]
    )
    let stored = try XCTUnwrap(ManifestStore(paths: paths).load().item(id: "tool"))

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(stored.update.cmd, "printf changed")
}
```

Add this test-only response type at the bottom of the test file:

```swift
private struct EditResponse: Decodable {
    var ok: Bool
    var id: String
    var field: String
    var changed: Bool
    var item: Recipe
}
```

- [ ] **Step 2: Write failing validation and no-op tests**

Add tests for mode combinations, absent fields, invalid UTF-8, empty input, validation failure, and unchanged input:

```swift
func testEditFieldRejectsInvalidModesWithoutMutation() throws {
    let cases = [
        ["edit", "tool", "--from", "-"],
        ["edit", "tool", "--json"],
        ["edit", "tool", "--field", "install.cmd", "--from", "-"],
    ]

    for arguments in cases {
        let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-field-tests")
        let paths = AppPaths(homeDirectory: home)
        try saveManifest(paths: paths)
        let before = try Data(contentsOf: paths.manifestFile)

        let result = try CLIProcess.run(arguments, home: home, stdin: "printf changed")

        XCTAssertEqual(result.exitCode, 1, arguments.joined(separator: " "))
        XCTAssertEqual(try Data(contentsOf: paths.manifestFile), before)
    }
}

func testEditFieldRejectsAbsentLatestCommandAndInvalidUTF8() throws {
    let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-field-tests")
    let paths = AppPaths(homeDirectory: home)
    var item = recipe()
    item.latest = LatestSpec(strategy: .brew, cmd: nil, pattern: nil)
    try ManifestStore(paths: paths).save(
        Manifest(
            schemaVersion: 1,
            items: [item],
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)))
    let invalid = home.appendingPathComponent("invalid-command")
    try Data([0xFF]).write(to: invalid)

    let missing = try CLIProcess.run(
        ["edit", "tool", "--field", "latest.cmd", "--from", "-"],
        home: home,
        stdin: "printf latest")
    let malformed = try CLIProcess.run(
        ["edit", "tool", "--field", "update.cmd", "--from", invalid.path], home: home)

    XCTAssertEqual(missing.exitCode, 1)
    XCTAssertTrue(missing.stderr.contains("latest.cmd: recipe has no command field"))
    XCTAssertEqual(malformed.exitCode, 1)
    XCTAssertTrue(malformed.stderr.contains("command input must be valid UTF-8"))
}

func testEditFieldUnchangedInputDoesNotRewriteManifest() throws {
    let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-field-tests")
    let paths = AppPaths(homeDirectory: home)
    try saveManifest(paths: paths)
    let before = try Data(contentsOf: paths.manifestFile)

    let result = try CLIProcess.run(
        ["edit", "tool", "--field", "update.cmd", "--from", "-", "--json"],
        home: home,
        stdin: "printf updated\n")
    let payload = try JSONDecoder.updateBar.decode(
        EditResponse.self, from: Data(result.stdout.utf8))

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertFalse(payload.changed)
    XCTAssertEqual(try Data(contentsOf: paths.manifestFile), before)
}
```

Add these concrete whitespace and secret-boundary tests:

```swift
func testEditFieldRejectsWhitespaceOnlyCommand() throws {
    let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-field-tests")
    let paths = AppPaths(homeDirectory: home)
    try saveManifest(paths: paths)
    let before = try Data(contentsOf: paths.manifestFile)

    let result = try CLIProcess.run(
        ["edit", "tool", "--field", "check.cmd", "--from", "-"],
        home: home,
        stdin: "  \n")

    XCTAssertEqual(result.exitCode, 1)
    XCTAssertTrue(result.stderr.contains("check.cmd: command must not be empty"))
    XCTAssertEqual(try Data(contentsOf: paths.manifestFile), before)
}

func testEditFieldRejectsAndRedactsLiteralSecret() throws {
    let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-field-tests")
    let paths = AppPaths(homeDirectory: home)
    try saveManifest(paths: paths)
    let before = try Data(contentsOf: paths.manifestFile)
    let secret = "sk-or-v1-secret-value"

    let result = try CLIProcess.run(
        ["edit", "tool", "--field", "update.cmd", "--from", "-", "--json"],
        home: home,
        stdin: "OPENROUTER_API_KEY=\(secret) tool update")
    let combined = result.stdout + result.stderr

    XCTAssertEqual(result.exitCode, 1)
    XCTAssertEqual(result.stderr, "")
    XCTAssertFalse(combined.contains(secret))
    XCTAssertEqual(try Data(contentsOf: paths.manifestFile), before)
}

func testEditFieldUnreadableInputAndEditorFailureDoNotMutate() throws {
    let home = try makeTemporaryHome(prefix: "updatebar-cli-edit-field-tests")
    let paths = AppPaths(homeDirectory: home)
    try saveManifest(paths: paths)
    let before = try Data(contentsOf: paths.manifestFile)

    let unreadable = try CLIProcess.run(
        [
            "edit", "tool", "--field", "update.cmd", "--from",
            home.appendingPathComponent("missing-command.txt").path,
        ],
        home: home)
    let editor = try editorScript(home: home, body: "exit 7")
    let failedEditor = try CLIProcess.run(
        ["edit", "tool", "--field", "update.cmd"],
        home: home,
        environment: ["EDITOR": editor.path])

    XCTAssertEqual(unreadable.exitCode, 1)
    XCTAssertTrue(unreadable.stderr.contains("input file could not be read"))
    XCTAssertEqual(failedEditor.exitCode, 1)
    XCTAssertTrue(failedEditor.stderr.contains("editor exited 7"))
    XCTAssertEqual(try Data(contentsOf: paths.manifestFile), before)
}
```

- [ ] **Step 3: Run the edit tests to verify the new behavior fails**

Run:

```bash
rtk swift test --filter EditCommandTests
```

Expected: FAIL because `edit` does not recognize `--field`, `--from`, or `--json`, and `EditResponse` receives no payload.

- [ ] **Step 4: Add the edit payload**

Add to `CLIPayloads.swift`, keeping redaction in the existing payload boundary:

```swift
struct EditPayload: Encodable {
    var ok: Bool
    var id: String
    var field: String
    var changed: Bool
    var item: Recipe
}

func redactedEditPayload(
    for recipe: Recipe,
    field: String,
    changed: Bool
) -> EditPayload {
    EditPayload(
        ok: true,
        id: SecretRedactor.redact(recipe.id),
        field: SecretRedactor.redact(field),
        changed: changed,
        item: redactedRecipe(recipe)
    )
}
```

- [ ] **Step 5: Implement field selection and input modes**

Add these options to `EditCommand`:

```swift
@Option(
    name: .long,
    help: "Edit check.cmd, latest.cmd, or update.cmd.",
    completion: .list(["check.cmd", "latest.cmd", "update.cmd"])
)
var field: String?

@Option(
    name: .long,
    help: ArgumentHelp("Read field command text from a file or '-' for stdin.", valueName: "file")
)
var from: String?

@Flag(name: .long, help: "Print machine-readable JSON; requires --field and --from.")
var json = false
```

Split `run()` into whole-recipe and field-specific paths. Validate combinations before opening an editor or reading stdin:

```swift
private func validateMode() throws {
    if from != nil, field == nil {
        throw ValidationError("edit --from requires --field")
    }
    if json, field == nil || from == nil {
        throw ValidationError("edit --json requires --field and --from")
    }
}
```

Implement exact field lookup and replacement without accepting arbitrary key paths:

```swift
private func commandText(field: String, in recipe: Recipe) throws -> String {
    switch field {
    case "check.cmd":
        guard case .command(let command) = recipe.check else {
            throw ValidationError("check.cmd: recipe has no command field")
        }
        return command
    case "latest.cmd":
        guard recipe.latest.strategy == .cmd, let command = recipe.latest.cmd else {
            throw ValidationError("latest.cmd: recipe has no command field")
        }
        return command
    case "update.cmd":
        return recipe.update.cmd
    default:
        throw RegistryError.commandFieldNotFound(field)
    }
}

private func replacingCommand(field: String, command: String, in recipe: Recipe) throws -> Recipe {
    var copy = recipe
    _ = try commandText(field: field, in: recipe)
    switch field {
    case "check.cmd":
        copy.check = .command(command)
    case "latest.cmd":
        copy.latest.cmd = command
    case "update.cmd":
        copy.update.cmd = command
    default:
        throw RegistryError.commandFieldNotFound(field)
    }
    return copy
}
```

Use existing `readInputData` for file/stdin input and the existing secure editor launcher for human input:

```swift
private func editedCommand(field: String, current: String) throws -> String {
    let data: Data
    if let from {
        data = try readInputData(from)
    } else {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("updatebar-edit-command-\(UUID().uuidString).txt")
        try Data(current.utf8).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        try runEditor(file: temp)
        data = try Data(contentsOf: temp)
    }
    guard let decoded = String(data: data, encoding: .utf8) else {
        throw ValidationError("command input must be valid UTF-8")
    }
    let command = removingOneFinalLineEnding(from: decoded)
    guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ValidationError("\(field): command must not be empty")
    }
    return command
}

private func removingOneFinalLineEnding(from value: String) -> String {
    if value.hasSuffix("\r\n") { return String(value.dropLast(2)) }
    if value.hasSuffix("\n") { return String(value.dropLast()) }
    return value
}
```

After `invalidateChangedApprovals` and `validateEditedRecipe`, save only when the edited recipe differs from the original. Preserve the current whole-recipe output; field mode uses this output branch:

```swift
private func outputFieldEdit(recipe: Recipe, field: String, changed: Bool) throws {
    if json {
        try printJSON(redactedEditPayload(for: recipe, field: field, changed: changed))
        return
    }
    let verb = changed ? "edited" : "unchanged"
    writeStdout("\(verb) \(SecretRedactor.redact(recipe.id)) \(field)")
    printApprovalNextSteps(for: [recipe.id])
}
```

- [ ] **Step 6: Run focused edit tests**

Run:

```bash
rtk swift test --filter EditCommandTests
```

Expected: PASS with all existing whole-recipe editor tests and new field-edit tests green.

- [ ] **Step 7: Commit field editing**

```bash
rtk git add Sources/UpdateBarCLI/CLIEditCommand.swift Sources/UpdateBarCLI/CLIPayloads.swift Tests/UpdateBarCLITests/EditCommandTests.swift
rtk git commit -m "feat: add command field editing"
```

### Task 2: Check and Approval Edit Guidance

**Files:**
- Modify: `Tests/UpdateBarCoreTests/TrustPolicyTests.swift`
- Modify: `Tests/UpdateBarCLITests/CheckCommandTests.swift`
- Modify: `Tests/UpdateBarCLITests/ManageItemCommandTests.swift`
- Modify: `Sources/UpdateBarCore/Security/TrustPolicy.swift`
- Modify: `Sources/UpdateBarCLI/CLIWorkflowSupport.swift`
- Modify: `Sources/UpdateBarCLI/CLICheckCommand.swift`
- Modify: `Sources/UpdateBarCLI/CLIManageCommands.swift`

- [ ] **Step 1: Write failing trust-policy and workflow tests**

Add core tests proving that only shell fields required by check are returned in stable order:

```swift
func testUnapprovedCheckCommandFieldsAreOrderedAndExcludeUpdate() throws {
    var recipe = try loadRecipe()
    recipe.latest = LatestSpec(strategy: .cmd, cmd: "tool latest", pattern: nil)
    recipe.trust.level = .untrusted
    recipe.trust.approvedCommands = [:]

    XCTAssertEqual(
        TrustPolicy.unapprovedCheckCommandFields(recipe),
        ["check.cmd", "latest.cmd"])

    recipe.check = .file(path: "/tmp/version")
    XCTAssertEqual(TrustPolicy.unapprovedCheckCommandFields(recipe), ["latest.cmd"])

    recipe.latest = LatestSpec(strategy: .brew, cmd: nil, pattern: nil)
    XCTAssertEqual(TrustPolicy.unapprovedCheckCommandFields(recipe), [])
}
```

Extend `testCheckHumanUntrustedPrintsApprovalNextSteps` with:

```swift
XCTAssertTrue(result.stdout.contains("updatebar edit fixture-tool --field check.cmd"))
XCTAssertTrue(result.stdout.contains("updatebar edit fixture-tool --field latest.cmd"))
XCTAssertFalse(result.stdout.contains("updatebar edit fixture-tool --field update.cmd"))
```

Add the check-file/built-in-latest case that expects no edit suggestion:

```swift
func testCheckHumanUntrustedWithoutCheckCommandsDoesNotSuggestFieldEdit() throws {
    let home = try temporaryDirectory()
    let paths = AppPaths(homeDirectory: home)
    let versionFile = home.appendingPathComponent("version.txt")
    try Data("fixture-tool 1.0.0\n".utf8).write(to: versionFile)
    var recipe = fixtureRecipe()
    recipe.check = .file(path: versionFile.path)
    recipe.latest = LatestSpec(strategy: .brew, cmd: nil, pattern: nil)
    recipe.source = Source(kind: .brew, ref: "fixture-tool", branch: nil)
    recipe.trust.level = .untrusted
    recipe.trust.approvedCommands = [:]
    try ManifestStore(paths: paths).save(manifest(items: [recipe]))

    let result = try CLIProcess.run(["check", "fixture-tool"], home: home)

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.stdout.contains("updatebar approvals fixture-tool"))
    XCTAssertFalse(result.stdout.contains("updatebar edit fixture-tool --field"))
}
```

Extend `testApproveListAndRevokeCommandFields` with:

```swift
XCTAssertTrue(list.stdout.contains("updatebar edit tool --field check.cmd"))
XCTAssertTrue(list.stdout.contains("updatebar edit tool --field latest.cmd"))
XCTAssertFalse(list.stdout.contains("updatebar edit tool --field update.cmd"))
```

The update field is already approved in this fixture. Add a fresh fully-unapproved approvals case that proves all three edit commands appear:

```swift
func testApprovalsSuggestsEditingEveryUnapprovedCommandField() throws {
    let home = try makeTemporaryHome(prefix: "updatebar-cli-manage-tests")
    let paths = AppPaths(homeDirectory: home)
    var item = recipe()
    item.trust.level = .untrusted
    item.trust.approvedCommands = [:]
    try ManifestStore(paths: paths).save(
        Manifest(
            schemaVersion: 1,
            items: [item],
            provenance: Provenance(createdBy: "test", createdAt: now, updatedAt: now)))

    let result = try CLIProcess.run(["approvals", "tool"], home: home)

    XCTAssertEqual(result.exitCode, 0)
    for field in ["check.cmd", "latest.cmd", "update.cmd"] {
        XCTAssertTrue(result.stdout.contains("updatebar edit tool --field \(field)"), field)
        XCTAssertTrue(result.stdout.contains("updatebar approve tool --field \(field)"), field)
    }
}
```

- [ ] **Step 2: Run focused tests to verify failure**

Run:

```bash
rtk swift test --filter TrustPolicyTests
rtk swift test --filter CheckCommandTests
rtk swift test --filter ManageItemCommandTests
```

Expected: FAIL because no field-edit next-step helper or check-required field query exists.

- [ ] **Step 3: Add ordered check-required field logic**

Add to `TrustPolicy`:

```swift
public static func unapprovedCheckCommandFields(_ recipe: Recipe) -> [String] {
    var fields: [String] = []
    if case .command = recipe.check, !isApproved(recipe, field: "check.cmd") {
        fields.append("check.cmd")
    }
    if recipe.latest.strategy == .cmd, !isApproved(recipe, field: "latest.cmd") {
        fields.append("latest.cmd")
    }
    return fields
}
```

Keep `isCheckApproved` unchanged so this addition cannot weaken the trust boundary.

- [ ] **Step 4: Add the edit command formatter and human guidance**

Add to `CLIWorkflowSupport.swift`:

```swift
func editFieldCommand(for id: String, field: String) -> String {
    "updatebar edit \(displayID(id)) --field \(field)"
}
```

In `CheckCommand.printHuman`, build the existing approval commands first and append edit commands only for blocked recipes:

```swift
var nextCommands = approvalCommands(
    for: blocked.map(\.id) + updateApprovalNeeded.map(\.id))
for result in blocked {
    guard let recipe = manifest.item(id: result.id) else { continue }
    nextCommands.append(
        contentsOf: TrustPolicy.unapprovedCheckCommandFields(recipe).map {
            editFieldCommand(for: recipe.id, field: $0)
        })
}
printNextCommands(unique(nextCommands))
```

In `ApprovalsCommand`, pair edit and approve actions for each unapproved row:

```swift
printNextCommands(
    unapprovedRows.flatMap { row in
        [
            editFieldCommand(for: id, field: row.field),
            approveFieldCommand(for: id, field: row.field),
        ]
    }
)
```

- [ ] **Step 5: Run focused trust and workflow tests**

Run:

```bash
rtk swift test --filter TrustPolicyTests
rtk swift test --filter CheckCommandTests
rtk swift test --filter ManageItemCommandTests
```

Expected: PASS. Existing JSON assertions remain unchanged because the guidance is human-only.

- [ ] **Step 6: Commit workflow guidance**

```bash
rtk git add Sources/UpdateBarCore/Security/TrustPolicy.swift Sources/UpdateBarCLI/CLIWorkflowSupport.swift Sources/UpdateBarCLI/CLICheckCommand.swift Sources/UpdateBarCLI/CLIManageCommands.swift Tests/UpdateBarCoreTests/TrustPolicyTests.swift Tests/UpdateBarCLITests/CheckCommandTests.swift Tests/UpdateBarCLITests/ManageItemCommandTests.swift
rtk git commit -m "feat: suggest command field edits"
```

### Task 3: CLI and Agent Discoverability

**Files:**
- Modify: `Sources/UpdateBarCLI/CLIAddCommand.swift`
- Modify: `Sources/UpdateBarCLI/CLIEditCommand.swift`
- Modify: `Sources/UpdateBarCLI/CLIDocumentCommands.swift`
- Modify: `README.md`
- Modify: `docs/cli.md`
- Modify: `Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift`
- Modify: `Tests/UpdateBarCLITests/GuideTemplateCommandTests.swift`

- [ ] **Step 1: Write failing help and guide tests**

Update the root help contract so `add` and `edit` are visible and described while the remaining support/advanced commands stay hidden:

```swift
for command in ["init", "scan", "add", "check", "status", "update", "approvals", "edit"] {
    XCTAssertTrue(helpShowsCommand(command, in: helpLines), "missing \(command)")
    XCTAssertTrue(helpHasDescription(for: command, in: helpLines), "missing description: \(command)")
}
```

Remove `add` and `edit` from the hidden-command arrays in `testRootHelpShowsPrimaryWorkflowCommandsOnly` and add `edit` options to the help-description table:

```swift
"edit": ["--field", "--from", "--json"]
```

Extend `testGuideAgentPrintsSafeAgentWorkflow`:

```swift
XCTAssertTrue(result.stdout.contains("updatebar edit <id> --field check.cmd --from"))
XCTAssertTrue(result.stdout.contains("updatebar approvals <id> --json"))
XCTAssertTrue(result.stdout.contains("Editing does not approve commands"))
```

- [ ] **Step 2: Run documentation tests to verify failure**

Run:

```bash
rtk swift test --filter DocumentationSnapshotTests
rtk swift test --filter GuideTemplateCommandTests
```

Expected: FAIL because add/edit are hidden and the agent guide omits modification.

- [ ] **Step 3: Expose add/edit and update the generated CLI guidance source**

Remove `shouldDisplay: false` from `AddCommand.configuration` and
`EditCommand.configuration`. Extend the safe workflow in
`CLIDocumentCommands.swift` immediately after command review:

```text
7. To correct a command without a TTY, write the exact command to a file and run:
   updatebar edit <id> --field check.cmd --from command.txt --json.
   Editing does not approve commands; review again with updatebar approvals <id> --json.
8. Do not approve commands silently.
```

Renumber later steps and retain the explicit per-field approval examples.

- [ ] **Step 4: Update README and CLI reference**

Add this agent modification example after the existing agent-authored add flow in `README.md`:

```bash
updatebar approvals demo-tool --json
updatebar edit demo-tool --field check.cmd --from check-command.txt --json
updatebar approvals demo-tool --json
```

State directly that editing invalidates affected approvals and never approves a command.

Change the edit signature and description in `docs/cli.md` to:

```markdown
### `updatebar edit <id> [--field <field>] [--from <file|->] [--json]`

Without `--field`, opens `$VISUAL`, `$EDITOR`, or `vi` with the complete recipe
JSON. With `--field`, edits `check.cmd`, `latest.cmd`, or `update.cmd`; `--from`
reads exact command text from a file or stdin. Non-interactive JSON mode requires
both `--field` and `--from`. Every changed command is validated and its stale
approval is invalidated; editing never approves or executes it.
```

Add `add` and `edit` to the documented primary workflow/authoring command list so root help and docs describe the same visible surface.

- [ ] **Step 5: Run help and guide tests**

Run:

```bash
rtk swift test --filter DocumentationSnapshotTests
rtk swift test --filter GuideTemplateCommandTests
```

Expected: PASS with add/edit visible, field options documented, and the agent loop present.

- [ ] **Step 6: Commit discoverability changes**

```bash
rtk git add Sources/UpdateBarCLI/CLIAddCommand.swift Sources/UpdateBarCLI/CLIEditCommand.swift Sources/UpdateBarCLI/CLIDocumentCommands.swift README.md docs/cli.md Tests/UpdateBarCLITests/DocumentationSnapshotTests.swift Tests/UpdateBarCLITests/GuideTemplateCommandTests.swift
rtk git commit -m "docs: expose agent command editing workflow"
```

### Task 4: Regression and Quality Verification

**Files:**
- Verify all files changed by Tasks 1-3.

- [ ] **Step 1: Run the complete CLI and core tests**

Run:

```bash
rtk swift test
```

Expected: PASS with zero failures.

- [ ] **Step 2: Run format and diff checks**

Run:

```bash
rtk swift-format lint --strict --recursive Sources Tests Package.swift
rtk git diff --check HEAD~3..HEAD
rtk git status --short
```

Expected: format lint and diff check pass. Status contains only the user's pre-existing untracked compact-approval design/plan files and this implementation plan if it has not been committed separately.

- [ ] **Step 3: Run the repository quality gate**

Run:

```bash
rtk test bash Scripts/quality-gate.sh
```

Expected: PASS, including CLI tests, Swift formatting, builds, scripts, TUI checks, and packaging smoke tests.

- [ ] **Step 4: Inspect the final task diff**

Run:

```bash
rtk git log -4 --oneline
rtk git diff HEAD~3..HEAD --stat
rtk git status --short
```

Expected: exactly three implementation commits after the design commit; no unrelated tracked files changed and no user-owned untracked files staged.
