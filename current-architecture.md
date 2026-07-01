# UpdateBar — Current Implementation Architecture

Status inspected from the current repo under `~/projects/UpdateBar` (current release includes optional macOS menu bar app).

Scope:

- CLI + optional macOS menu bar app
- macOS menu bar app supported (thin local wrapper around CLI status/actions)
- no bundled always-on daemon; optional LaunchAgent runs `check` only when installed by the user
- no built-in AI generation
- no provider auth storage

---

## 1. Package Shape

```text
UpdateBar
├── executable: updatebar
│   └── target: Sources/UpdateBarCLI
├── executable: updatebar-menubar
│   └── target: Sources/UpdateBarMenuBarApp
├── library: UpdateBarCore
│   └── target: Sources/UpdateBarCore
├── library: UpdateBarMenuBar
│   └── target: Sources/UpdateBarMenuBar
└── library: UpdateBarTestSupport
    └── target: Sources/UpdateBarTestSupport
```

Missing today:

- Sparkle integration
- recipe signing
- registry
- sync

---

## 2. High-Level Flow

```text
User / external agent
    |
    v
updatebar CLI
    |
    v
UpdateBarCore
    |
    +-- ConfigStore
    +-- ManifestStore
    +-- StateStore
    +-- RegistryService
    +-- UpdateRunner
    +-- Latest strategies
    +-- CommandExecutor
    +-- TrustPolicy
```

UpdateBar does not author commands. Humans or external agents write recipe JSON. UpdateBar validates, stores as untrusted by default, and runs only approved command fingerprints.

The menu bar app (`updatebar-menubar`) reads status and invokes user-triggered CLI actions internally. It never reads/writes manifest/state/config files directly.

---

## 3. Storage

Default home:

```text
~/.updatebar
```

Override:

```text
UPDATEBAR_HOME=/path/to/home
```

Files:

```text
manifest.json   recipe definitions and trust approvals
state.json      generated current/latest/status cache
config.toml     refresh/security/notify config
manifest.lock   cross-process manifest mutation lock
state.lock      cross-process state mutation lock
```

Stores use atomic writes. Mutating read-modify-write paths use file locks.

---

## 4. Current CLI Surface

```text
updatebar add
updatebar approve
updatebar approvals
updatebar background install
updatebar background status
updatebar background uninstall
updatebar check
updatebar config
updatebar disable
updatebar edit
updatebar enable
updatebar export
updatebar guide agent
updatebar guide recipe
updatebar import
updatebar list
updatebar pin
updatebar remove
updatebar revoke
updatebar schema
updatebar status
updatebar template manifest
updatebar template recipe
updatebar unpin
updatebar update
updatebar validate
updatebar version
```

Removed:

```text
updatebar auth
updatebar add --ai
updatebar add --provider
```

---

## 5. Recipe Lifecycle

```text
template/import/manual recipe
    |
    v
validate
    |
    v
add/import stores untrusted recipe
    |
    v
approvals shows command fields
    |
    v
approve stores exact command fingerprint
    |
    v
check/update may run approved command fields only
```

Supported recipe command fields:

```text
check.cmd
latest.cmd
update.cmd
```

Each field has its own fingerprint. Changing the command or `update.cwd` invalidates the affected approval.

---

## 6. Trust Model

A command can run only when:

```text
recipe.trust.level == trusted
AND
recipe.trust.approved_commands[field] == current fingerprint for that field
```

Partial approval note:

- approving one field currently sets `trust.level = trusted`
- unapproved fields still cannot run because each field checks its own fingerprint
- future UI should decide whether to expose a clearer `partially_trusted` state

---

## 7. Check Flow

```text
updatebar check [ids]
    |
    +-- load manifest
    +-- validate manifest
    +-- lock state
    +-- load state
    +-- for each selected item:
    |     +-- disabled -> status disabled
    |     +-- pinned -> status pinned
    |     +-- unapproved -> status untrusted
    |     +-- fresh cache -> reuse state
    |     +-- else run current/latest resolution
    +-- save state atomically
```

`check` may run shell/network depending on recipe strategy and trust.

---

## 8. Status Flow

```text
updatebar status --json
    |
    +-- load manifest
    +-- load state
    +-- build StatusSnapshot
    +-- print JSON
```

Rules:

- no shell
- no network
- future GUI contract
- `--refresh` only marks stale eligible items as `checking`

---

## 9. Update Flow

```text
updatebar update <id|--all>
    |
    +-- load manifest/state
    +-- plan candidates
    +-- skip pinned/disabled/untrusted/not-outdated
    +-- confirm unless --yes
    +-- run approved update.cmd
    +-- run forced check after success
    +-- mark state error after failure
```

`update` never approves commands.

---

## 10. Command Execution

Current executor:

```text
/bin/sh -c <command>
```

Environment:

- allowlist only
- no provider secrets
- no arbitrary inherited env

Execution policy:

- timeout
- output byte cap
- stdout/stderr capture
- redaction of known provider/GitHub token patterns

Important limitation:

```text
This is not a filesystem/network sandbox.
```

Current honest claim:

```text
approved + env-limited + timeout-capped + output-capped + redacted
```

---

## 11. Latest Strategies

Implemented:

```text
git_tags
git_head
npm_registry
github_release
brew
http_regex
cmd
```

`cmd` strategy is command-bearing and requires approval.

GitHub token support is environment-only through `GITHUB_TOKEN` or `GH_TOKEN`; there is no persistent provider credential store.

---

## 12. Agent-Friendly Surfaces

Implemented:

```text
updatebar guide agent
updatebar guide recipe
updatebar schema
updatebar template recipe --kind <kind> [--id <id>] [--source <ref>]
updatebar template manifest --kind <kind>
updatebar validate <manifest-or-recipe|-> --json
updatebar add --from <file|->
updatebar add --from <file> --dry-run --json
updatebar approvals <id> [--json]
updatebar approve <id> [--field <field>] [--json]
updatebar revoke <id> --field <field> [--json]
```

Target workflow:

```text
external agent writes recipe JSON
agent validates it
agent dry-runs add
agent shows commands to user
user approves exact fields
agent checks status
```

---

## 13. Near-Term Gaps

Before app/daemon work:

- final GitHub repo slug / Homebrew tap confirmation
- clean-checkout release dry run
- Apple Developer Program go/no-go for menu bar app

These are captured in `next-plan.md`.
