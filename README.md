# UpdateBar

UpdateBar is a safe, scriptable CLI for tracking and updating user-approved recipes covering local tools, CLIs, packages, and custom install targets. It keeps a manifest of registered items, checks current/latest versions on demand, and only runs update commands that have been explicitly trusted.

UpdateBar can scan local package managers for untrusted recipe candidates and register only the ones you select. It does not auto-trust commands. External agents (or you) can still author recipe JSON; UpdateBar remains the validation, trust, and execution boundary. Run `updatebar guide agent` for the agent workflow.

## Install With Homebrew

```bash
brew tap sonim1/tap
brew install sonim1/tap/updatebar
```

Install the optional macOS menu bar app:

```bash
brew install --cask sonim1/tap/updatebar-app
```

Releases from v0.3.0 are signed with a Developer ID certificate and notarized
by Apple, so the app opens without Gatekeeper warnings.
The `updatebar-app` cask installs the app only; install the formula for the `updatebar` CLI.
All supported install paths are summarized in [docs/install.md](docs/install.md).

## Install From Source

```bash
swift build -c release --product updatebar
cp .build/release/updatebar ~/.local/bin/updatebar
```

Or use the local installer:

```bash
Scripts/install-local.sh

# Optional: change install directory
UPDATEBAR_INSTALL_PREFIX="$HOME/.local/bin" Scripts/install-local.sh
```

For development checks from a source checkout, use the same gate as CI:

```bash
Scripts/quality-gate.sh
```

On macOS, the gate prefers `/Applications/Xcode.app` when available so SwiftPM
can find `XCTest`. If direct `swift test` fails, set `DEVELOPER_DIR` or see
[docs/troubleshooting.md](docs/troubleshooting.md).

### Install from GitHub (single command)

```bash
curl -fsSL https://raw.githubusercontent.com/sonim1/UpdateBar/main/Scripts/install-release.sh | bash

# Or install a specific version:
curl -fsSL https://raw.githubusercontent.com/sonim1/UpdateBar/main/Scripts/install-release.sh | bash -s -- v0.6.0

# Optional: change install directory
curl -fsSL https://raw.githubusercontent.com/sonim1/UpdateBar/main/Scripts/install-release.sh | UPDATEBAR_INSTALL_PREFIX="$HOME/.local/bin" bash
```

Published prebuilt CLI archives currently cover Apple Silicon macOS and Linux
x86_64. Other platforms should build from source.
The installer downloads the matching release archive with `curl`, extracts it
with `tar`, and verifies the `.sha256` checksum with `shasum` or `sha256sum`
before installing `updatebar`.

### Menu bar app

`updatebar-menubar` ships as an optional macOS wrapper. The current `v0.5.0`
release provides the signed and notarized Apple Silicon asset
`UpdateBar-0.5.0-macos-arm64.app.tar.gz`. Starting with the next published app
release, tags publish the canonical `UpdateBar-<version>-macos-arm64.dmg` and
its checksum. `Scripts/package-app.sh` builds the local app bundle used by the
DMG release builder.
It prefers direct `UpdateBarCore` calls, keeps a CLI subprocess fallback, and exposes:

- check now
- refresh status
- update selected
- update all approved outdated
- per-command approve/revoke
- open TUI
- open config
- view logs
- quit

Build a local development app (not a public release artifact):

```bash
SPARKLE_PUBLIC_ED_KEY="$UPDATEBAR_RELEASE_SPARKLE_PUBLIC_KEY" Scripts/package-app.sh
open dist/UpdateBar.app
```

### Ink TUI

The terminal UI lives in `tui/` and consumes the Swift CLI JSON/JSONL contracts.
It supports status, checks, updates, and scan/select registration.

```bash
swift build --product updatebar
npm --prefix tui install
npm --prefix tui run build
UPDATEBAR_BIN=$PWD/.build/debug/updatebar UPDATEBAR_TUI=$PWD/tui/dist/index.js .build/debug/updatebar tui
```

## Release Operations

The normal release path is the protected GitHub Actions workflow in
`.github/workflows/release.yml`. A version tag selects one immutable commit;
GitHub Actions builds the two CLI archives, signs and notarizes the macOS app,
publishes the Sparkle feed and GitHub Release, and then asks
`sonim1/homebrew-tap` to update its packages.

### One-time update hosting setup

Install exactly the release tooling recorded in `package-lock.json`. Lifecycle
scripts are disabled, and the local Wrangler version is fixed at 4.112.0:

```bash
npm ci --ignore-scripts
node_modules/.bin/wrangler --version
```

Authenticate Wrangler with a Cloudflare identity that can inspect and create
the R2 bucket and bind its custom domain. Then provide the 32-character account
and zone IDs to the idempotent setup script:

```bash
CLOUDFLARE_ACCOUNT_ID=your-32-character-account-id \
CLOUDFLARE_ZONE_ID=your-32-character-zone-id \
Scripts/setup-update-hosting.sh
```

The script accepts only the `updatebar-updates` bucket and
`updates.updatebar.sonim1.com` custom domain. It creates missing resources,
accepts an exact existing configuration, and stops on conflicting state; it
never deletes a bucket or domain. `updatebar.sonim1.com` is an optional future
product website and is separate from the update host. A later move to
`updatebar.app` must keep `https://updates.updatebar.sonim1.com/appcast.xml`
reachable for installed builds. Introduce a new feed domain only with a tested
compatibility or redirect strategy.

### Sparkle signing key

UpdateBar must use its own Sparkle Ed25519 key pair. Do not reuse SwitchTab's
Sparkle key even when both apps share the same Apple Developer team,
Developer ID certificate, and notarization credentials. After SwiftPM has
resolved the pinned Sparkle package, create the local key under the Keychain
account `updatebar`:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account updatebar
```

Set the printed public key as `SPARKLE_PUBLIC_ED_KEY`. The local
`Scripts/generate-appcast.sh` path reads the private key directly from that
Keychain account and never prints it. For GitHub Actions, export the private
key to a permission-restricted temporary file and pipe it into the Environment
secret prompt; remove the export immediately:

```bash
sparkle_secret_dir="$(mktemp -d)"
chmod 700 "$sparkle_secret_dir"
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account updatebar -x "$sparkle_secret_dir/updatebar-sparkle-private-key"
gh secret set --env release SPARKLE_PRIVATE_ED_KEY \
  < "$sparkle_secret_dir/updatebar-sparkle-private-key"
rm -f "$sparkle_secret_dir/updatebar-sparkle-private-key"
rmdir "$sparkle_secret_dir"
```

Do not pass the private key on a command line, print it, commit it, or leave the
export behind. The release script writes the CI value to a mode-0600 temporary
file, removes the environment copy, verifies that the public and private keys
match cryptographically, and deletes the temporary file on exit.

### GitHub release environment

Create a GitHub Environment named `release` and require reviewer approval.
Configure these Environment variables, grouped by the job that references
them:

- `package`: `DEVELOPER_ID_APPLICATION`, `SPARKLE_PUBLIC_ED_KEY`
- `publish`: `CLOUDFLARE_ACCOUNT_ID`
- `notify`: `TAP_GITHUB_APP_ID`

Configure these Environment secrets:

- `package`: `APPLE_CERTIFICATE_P12_BASE64`,
  `APPLE_CERTIFICATE_PASSWORD`, `APPLE_NOTARY_KEY_P8_BASE64`,
  `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID`, and
  `SPARKLE_PRIVATE_ED_KEY`
- `publish`: `R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY`, using R2 Object
  Read & Write credentials scoped only to `updatebar-updates`
- `notify`: `TAP_GITHUB_APP_PRIVATE_KEY`

The `publish` job also receives GitHub's built-in `github.token`; it is not a
configured secret. Each of `package`, `publish`, and `notify` enters the same
protected Environment in sequence, so one release can present multiple
approval prompts. The workflow injects only the listed values into each job,
but all secrets in one Environment become available after that job's approval.
Use separate Environments if availability isolation is required.

The Apple certificate and notarization secrets may be the same values used by
SwitchTab because the apps share the Apple team and certificate. The Sparkle
key and bucket-scoped R2 credentials remain UpdateBar-specific.

### Homebrew GitHub App

Use one shared GitHub App for the unified tap automation and install it only on
`sonim1/homebrew-tap`, not on `sonim1/UpdateBar` or `sonim1/switchtab`. Its
minimum permission union is:

- `Administration: Read` for the tap workflow's branch-protection preflight
- `Contents: Read and write` for dispatches and the generated update branch
- `Pull requests: Read and write` for pull-request creation and auto-merge

Set `TAP_GITHUB_APP_ID` and `TAP_GITHUB_APP_PRIVATE_KEY` in UpdateBar's
protected `release` Environment. Set the same variable and secret at repository
scope in `sonim1/homebrew-tap`, because the receiving workflow needs them to
create its guarded branch and pull request. Scope the installation owner to
`sonim1` and the repository selection to `homebrew-tap` only. Enable auto-merge
and strict default-branch protection in the tap repository with the exact
required checks `contracts` and `homebrew`; the release scripts do not change
these administrative settings.

### Create and push a release tag

Start from a clean `main` checkout after updating `version.env` and the
changelog. Use one guarded flow that compares the local commit with freshly
fetched `origin/main`, creates one exact annotated tag, verifies it, and pushes
only its fully qualified ref:

```bash
(
set -euo pipefail
release_tag=v0.6.0
git fetch --prune --no-tags origin '+refs/heads/main:refs/remotes/origin/main'
git fetch --prune --tags origin
test -z "$(git status --porcelain=v1 --untracked-files=all)"
test "$(git branch --show-current)" = main
test "$(git rev-parse HEAD)" = "$(git rev-parse refs/remotes/origin/main)"
version_line="$(< version.env)"
[[ "$version_line" =~ ^UPDATEBAR_VERSION=([0-9]+([.][0-9]+){1,2})$ ]]
test "${release_tag#v}" = "${BASH_REMATCH[1]}"
if git show-ref --verify --quiet "refs/tags/$release_tag"; then
  echo "Release tag already exists: $release_tag" >&2
  exit 64
fi
release_commit="$(git rev-parse HEAD)"
git tag -a "$release_tag" "$release_commit" -m "UpdateBar ${release_tag#v}"
git show-ref --verify --quiet "refs/tags/$release_tag"
test "$(git rev-parse "refs/tags/$release_tag^{commit}")" = "$release_commit"
git push origin "refs/tags/$release_tag:refs/tags/$release_tag"
)
```

Do not use a shorter tag command, move or recreate a release tag, or publish
from an unverified local branch. The tag push is the end of the normal local
procedure; GitHub Actions owns publication.

### Automated release graph

The workflow executes this graph:

```text
provenance -> verify (macOS/Linux matrix) -> package -> publish -> notify
```

`provenance` resolves the exact tag once and proves that it belongs to freshly
fetched `origin/main`. The secret-free `verify` matrix runs Swift tests and
builds and smoke-checks the Apple Silicon macOS and x86-64 Linux CLI archives.
Those intermediate artifacts are retained for 7 days. After approval,
`package` signs and notarizes the arm64 DMG, signs the Sparkle appcast, creates
the release manifest, and uploads one checksum-bound immutable bundle retained
for 30 days. After another approval, `publish` downloads that same bundle,
validates its commit and checksums, publishes R2 and the GitHub Release, and
makes the complete draft public. `notify` then enters the Environment and
dispatches the exact repository and tag to the tap.

All external Actions are pinned to reviewed 40-character commit SHAs:
`actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1`,
`swift-actions/setup-swift@7591e4f04c00624cb043783da51a7fd6ee0a6bf6`,
`actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02`,
`actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093`,
and
`actions/create-github-app-token@67018539274d69449ef7c02e8e71183d1719ab42`.

Every release publishes exactly eight GitHub assets:

- `updatebar-<version>-macos-arm64.tar.gz` and its `.sha256`
- `updatebar-<version>-linux-x86_64.tar.gz` and its `.sha256`
- `UpdateBar-<version>-macos-arm64.dmg` and its `.sha256`
- `appcast.xml`
- `release-manifest.json`

The tap dispatch payload contains only `repository=sonim1/UpdateBar` and the
exact tag. The tap downloads and validates the public manifest. It updates the
`updatebar` formula from the CLI release asset, the `updatebar-app` cask from
the same DMG used by Sparkle, and the `updatebar-tui` formula from the immutable
GitHub tag archive, then opens one guarded pull request for CI and auto-merge.

Every tag shares the non-cancelling `updatebar-release` concurrency group. Its
current `queue: max` behavior keeps the full queue, subject to GitHub Actions'
limit of up to 100 queued workflow runs, instead of replacing pending tags.

### Failed-job recovery

If `package` fails before publication, fix the cause and use **Re-run failed
jobs**. No GitHub Release or R2 update has occurred at that point, so the failed
package job may build again.

If `publish` fails, use **Re-run failed jobs** or rerun that specific failed
`publish` job within the bundle's 30-day retention window. The rerun must reuse
the existing `updatebar-release-<tag>` bundle; do not rerun all jobs, rebuild
the bundle, or recreate, move, or delete the tag. The publisher can reuse an
existing complete draft only when every required asset has identical bytes.
R2 versioned objects are reused only when their bytes match, and the mutable
appcast is updated last with an ETag precondition. These are script guarantees,
not permission to replace conflicting state. Investigate any conflict instead
of deleting or rolling back remote objects.

If `notify` fails after publication, rerun only `notify`. It can request the
`release` Environment approval again, but it does not rebuild or republish the
release.

### Local publication fallback

Use this fallback only after the tag-triggered workflow is cancelled or
disabled and no active run owns the tag. First produce both canonical CLI
archives and checksums for their supported platforms in `dist/` without
changing the tagged checkout. Then run the remaining steps from the same clean,
freshly fetched tag. Keep Apple signing and notarization credentials in the
Keychain, the Sparkle private key in Keychain account `updatebar`, and read
short-lived R2 and tap credentials without placing them in shell history:

```bash
(
set -euo pipefail
set +x
release_tag=v0.6.0
trap 'unset R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY TAP_GH_TOKEN' EXIT HUP INT TERM
git fetch --prune --no-tags origin '+refs/heads/main:refs/remotes/origin/main'
git fetch --prune --tags origin
test -z "$(git status --porcelain=v1 --untracked-files=all)"
test "$(git rev-parse HEAD)" = "$(git rev-parse refs/remotes/origin/main)"
git show-ref --verify --quiet "refs/tags/$release_tag"
test "$(git rev-parse "refs/tags/$release_tag^{commit}")" = "$(git rev-parse HEAD)"

read -r -s -p 'R2 access key ID: ' R2_ACCESS_KEY_ID; printf '\n'
read -r -s -p 'R2 secret access key: ' R2_SECRET_ACCESS_KEY; printf '\n'
read -r -s -p 'Temporary tap token: ' TAP_GH_TOKEN; printf '\n'
export R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY TAP_GH_TOKEN

app_dmg="$(Scripts/build-app-dmg.sh)"
Scripts/app-dmg-smoke-test.sh "$app_dmg"
Scripts/generate-appcast.sh
Scripts/generate-release-manifest.sh "$release_tag"
Scripts/publish-release.sh "$release_tag"
Scripts/dispatch-homebrew-update.sh "$release_tag"
)
```

Before the block, export the non-secret `DEVELOPER_ID_APPLICATION`,
`NOTARYTOOL_KEYCHAIN_PROFILE`, `SPARKLE_PUBLIC_ED_KEY`, and
`CLOUDFLARE_ACCOUNT_ID` values. `publish-release.sh` publishes the exact eight
assets, calls `publish-update.sh` for the immutable DMG/checksum and ETag-guarded
appcast, and makes the GitHub draft public last. Dispatch runs only after that
succeeds. Do not invent a rollback path or race local publication against CI.

## Quick Start

```bash
# See what UpdateBar can discover without changing state.
updatebar scan

# Select discovered tools to register as untrusted recipes.
updatebar init

# Or register candidates directly with stable ids from scan output.
updatebar init --select <candidate-id-from-scan>

# Review command fields before running checks or updates. Follow the approval commands it prints.
updatebar approvals <id-from-init>

# Inspect state without running checks.
updatebar status --json

# Refresh versions. Exit code 10 means outdated items were found.
updatebar check

# Run approved updates only.
updatebar update --yes
```

For agent-authored or hand-written recipes:

```bash
updatebar guide agent
updatebar schema
updatebar template recipe --kind npm --id demo-tool --name "Demo Tool" --source demo-tool > recipe.json
updatebar validate recipe.json --json
updatebar add --from recipe.json --dry-run --json
```

Manual JSON import is also supported:

```bash
updatebar import Fixtures/manifests/untrusted-import.json --json
```

## Scope

v1 ships the CLI first, with optional Ink TUI and macOS Menu Bar presentation layers over the same core behavior.
Built-in AI generation, OAuth providers, and local LLM providers are removed by design — recipe authoring belongs to external agents. Sync, community registries, recipe signing, and `diff` are not planned until real external demand appears. Current architecture notes live in [current-architecture.md](current-architecture.md); [next-plan.md](next-plan.md) is retained as historical planning context.

UpdateBar has no telemetry.

## Agent Command Editing

External agents can inspect and correct one command field without a TTY:

```bash
updatebar approvals demo-tool --json
updatebar edit demo-tool --field check.cmd --from check-command.txt --json
updatebar approvals demo-tool --json
```

Editing validates the complete recipe and invalidates affected approvals. It
never approves or executes the new command; approval remains a separate,
explicit action after review.

## Safety Model

Imported recipes are saved as `untrusted`. `status` only reads local state. `check` and `update` refuse untrusted or unapproved command fields.

Approved recipe commands are not sandboxed. They run with your user privileges after fingerprint approval, with an allowlisted environment, time/output caps, and redacted captured output.

See [docs/security.md](docs/security.md) for details.

Contributing notes live in [CONTRIBUTING.md](CONTRIBUTING.md).
Shell completion setup lives in [docs/completions.md](docs/completions.md).
Background check setup lives in [docs/background.md](docs/background.md).
Architecture notes live in [docs/architecture.md](docs/architecture.md).
Troubleshooting lives in [docs/troubleshooting.md](docs/troubleshooting.md).
