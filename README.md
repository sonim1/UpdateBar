# UpdateBar

UpdateBar is a safe, scriptable CLI for tracking and updating user-approved recipes covering local tools, CLIs, packages, and custom install targets. It keeps a manifest of registered items, checks current/latest versions on demand, and only runs update commands that have been explicitly trusted.

UpdateBar can scan local package managers for untrusted recipe candidates and register only the ones you select. It does not auto-trust commands. External agents (or you) can still author recipe JSON; UpdateBar remains the validation, trust, and execution boundary. Run `updatebar guide agent` for the agent workflow.

## Install With Homebrew

```bash
brew tap sonim1/tap
brew install --cask sonim1/tap/updatebar-app
```

The cask installs both the macOS menu bar app and the `updatebar` CLI. For a
CLI-only installation, use the standalone formula:

```bash
brew install --formula sonim1/tap/updatebar
```

Releases from v0.3.0 are signed with a Developer ID certificate and notarized
by Apple, so the app opens without Gatekeeper warnings.
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
curl -fsSL https://raw.githubusercontent.com/sonim1/UpdateBar/main/Scripts/install-release.sh | bash -s -- v0.6.1

# Optional: change install directory
curl -fsSL https://raw.githubusercontent.com/sonim1/UpdateBar/main/Scripts/install-release.sh | UPDATEBAR_INSTALL_PREFIX="$HOME/.local/bin" bash
```

Published prebuilt CLI archives currently cover Apple Silicon macOS and Linux
x86_64. Other platforms should build from source.
The installer downloads the matching release archive with `curl`, extracts it
with `tar`, and verifies the `.sha256` checksum with `shasum` or `sha256sum`
before installing `updatebar`.

### Menu bar app

`updatebar-menubar` ships as an optional macOS wrapper. The public `v0.6.1`
release provides the signed and notarized Apple Silicon asset
`UpdateBar-0.6.1-macos-arm64.app.tar.gz`. Starting with the next published app
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

The normal publication path is `.github/workflows/automatic-release.yml`, which
hands one exact tag to the protected `.github/workflows/release.yml`. A version
tag selects one immutable commit;
GitHub Actions builds the two CLI archives, signs and notarizes the macOS app,
publishes the Sparkle feed and GitHub Release, and then asks
`sonim1/homebrew-tap` to update its packages.

### Automatic release flow

Normal releases start with a trusted same-repo pull request targeting
`main`. CI prepares the default patch version, or the version selected by the
`release:minor` or `release:major` label. Root Markdown files, `docs/`, and
`openspec/`-only pull requests are documentation-only and never release. Fork,
untrusted-author, and Dependabot pull requests fail closed before the
write-token version job; a maintainer must move an approved change to a
maintainer-owned branch in this repository.

A code or release pull request must contain nonempty notes under the canonical
`## Unreleased` heading before the bot's first preparation. After that
preparation, a fresh empty `## Unreleased` section is expected; the exact bot
candidate version section (for example, `## X.Y.Z - YYYY-MM-DD`) immediately
below it must be nonempty. The bot updates and commits only `version.env`, the
exact generated `Sources/UpdateBarCLI/UpdateBarVersion.swift`, and the
`CHANGELOG.md` release entry. Do not manually bump a future version in a normal
pull request.

After a strict, up-to-date `main` merge, the automatic workflow plans the
range, creates or verifies one exact annotated tag, and explicitly dispatches
`release.yml` with that tag. The existing release workflow then runs
`verify` (macOS/Linux), `package`, `publish`, and `notify`, producing the
GitHub Release, R2/Sparkle update artifacts, and Homebrew tap update.

The bootstrap rollout PR needs one explicit/manual candidate version and
changelog preparation to establish this contract. Do not bump a version in this
documentation change; subsequent normal pull requests are prepared by the bot.

Automatic versioning requires a separate contents-write-only GitHub App with
only `Contents: write`, installed only on `sonim1/UpdateBar`. Store its
repository variable `VERSION_GITHUB_APP_ID` and repository secret
`VERSION_GITHUB_APP_PRIVATE_KEY`.
Create the `release:minor` and `release:major` labels, and protect `main` with
strict up-to-date required checks named exactly `macos` and `linux`.

Run `Scripts/setup-release-secrets.sh` to configure those repository-scoped
version-App credentials together with the protected `release` Environment
values. The local `.env.release.local` file is ignored; PEM values in it must
use literal escaped newlines (`\n`) or a complete single-/double-quoted
multiline block. Exported multiline values are also accepted. Never print,
commit, or paste private keys into logs or documentation.

The release Environment currently has no protection rules, so the workflow is
hands-off after merge. If a required reviewer is added later, it would
intentionally pause `package`, `publish`, and `notify`; approval is not required
by the current setup.

The checked-in Homebrew formula/cask metadata is a coherent packaging snapshot;
it may differ from both the candidate version and the public tap. Public latest
is currently `v0.6.1`; this repository's candidate and `version.env` are
`0.6.3`, matching the checked-in packaging snapshot.
Authoritative public tap metadata is updated after the corresponding GitHub
Release is public.

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
`updates.updatebar.royjen.com` custom domain. It creates missing resources,
accepts an exact existing configuration, and stops on conflicting state; it
never deletes a bucket or domain. `updatebar.royjen.com` is an optional future
product website and is separate from the update host. A later move to
`updatebar.app` must keep `https://updates.updatebar.royjen.com/appcast.xml`
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
(
set -euo pipefail
set +x
unset SPARKLE_PRIVATE_ED_KEY
sparkle_secret_dir=''
sparkle_private_key_path=''
cleanup_sparkle_export() {
  local status=$?
  trap - EXIT HUP INT TERM
  unset SPARKLE_PRIVATE_ED_KEY
  [[ -z "$sparkle_private_key_path" ]] || rm -f -- "$sparkle_private_key_path" || :
  [[ -z "$sparkle_secret_dir" ]] || rmdir "$sparkle_secret_dir" || :
  exit "$status"
}
trap cleanup_sparkle_export EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
umask 077
sparkle_secret_dir="$(mktemp -d "${TMPDIR:-/tmp}/updatebar-sparkle-export.XXXXXX")"
chmod 700 "$sparkle_secret_dir"
sparkle_private_key_path="$sparkle_secret_dir/updatebar-sparkle-private-key"
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account updatebar -x "$sparkle_private_key_path"
chmod 600 "$sparkle_private_key_path"
gh secret set --env release SPARKLE_PRIVATE_ED_KEY < "$sparkle_private_key_path"
)
```

Do not pass the private key on a command line, print it, commit it, or leave the
export behind. The release script writes the CI value to a mode-0600 temporary
file, removes the environment copy, verifies that the public and private keys
match cryptographically, and deletes the temporary file on exit.

### GitHub release environment

Create a GitHub Environment named `release` and configure these Environment
variables, grouped by the job that references them:

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
`release` Environment in sequence. That Environment currently has no
protection rules, so the pipeline is hands-off after merge and presents no
approval prompt. Adding a required reviewer would intentionally pause each of
those jobs; approval is not currently required. The workflow injects only the
listed values into each job, but all secrets in one Environment become
available to that job once any configured protection rule is satisfied. Use
separate Environments if availability isolation is required.

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
`release` Environment. Set the same variable and secret at repository
scope in `sonim1/homebrew-tap`, because the receiving workflow needs them to
create its guarded branch and pull request. Scope the installation owner to
`sonim1` and the repository selection to `homebrew-tap` only. Enable auto-merge
and strict default-branch protection in the tap repository with the exact
required checks `contracts` and `homebrew`; the release scripts do not change
these administrative settings.

### Recovery for an existing tag

If automatic tag creation succeeded but its dispatch step failed, do not create
or move another tag. Verify that the existing tag is annotated and peels to the
intended commit on `main`, then dispatch the existing release explicitly:

```bash
release_tag=vX.Y.Z
git fetch --prune --no-tags origin \
  '+refs/heads/main:refs/remotes/origin/main' \
  "+refs/tags/$release_tag:refs/tags/$release_tag"
git show-ref --verify --quiet "refs/tags/$release_tag"
test "$(git cat-file -t "refs/tags/$release_tag")" = tag
git merge-base --is-ancestor "refs/tags/$release_tag^{commit}" "refs/remotes/origin/main^{commit}"
gh workflow run release.yml --ref "$release_tag" -f tag="$release_tag"
```

Use the exact tag value in both places. Recovery executes the workflow
definition from that exact tag, not from movable `main`; the release workflow
rechecks the remote tag, version, and `main` ancestry before it packages or
publishes.

### Emergency manual tag procedure

The automatic workflow owns normal version preparation and tag creation. Keep
the guarded procedure below only as an emergency fallback when that workflow is
cancelled or disabled and no active run owns the candidate. Start from a clean
`main` checkout after an explicitly approved version/changelog preparation. It
compares the local commit with freshly fetched `origin/main`, creates one exact
annotated tag, verifies it, and pushes only its fully qualified ref:

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
from an unverified local branch. The tag push is the end of this emergency
procedure; GitHub Actions owns publication.

### Automated release graph

The workflow executes this graph:

```text
provenance -> verify (macOS/Linux matrix) -> package -> publish -> notify
```

`provenance` resolves the exact tag once, requires the local and freshly
fetched remote tag to identify the checked-out commit, and proves that commit
is an ancestor of freshly fetched `origin/main`. Unlike tag creation, queued or
retried execution does not require current `origin/main` to equal the tagged
commit; `main` may contain newer descendants. The secret-free `verify` matrix
runs Swift tests and builds and smoke-checks the Apple Silicon macOS and x86-64
Linux CLI archives.
Those intermediate artifacts are retained for 7 days.
`package` signs and notarizes the arm64 DMG, signs the Sparkle appcast, creates
the release manifest, and uploads one checksum-bound immutable bundle retained
for 30 days. `publish` then downloads that same bundle, validates its commit
and checksums, publishes R2 and the GitHub Release, and makes the complete
draft public. `notify` then enters the Environment and dispatches the exact
repository and tag to the tap. The current `release` Environment has no
protection rules, so these jobs proceed hands-off; a required reviewer would
intentionally pause them and is not currently configured.

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
When an older queued tag starts after `main` advances, the workflow still
checks out that exact immutable tag and accepts the run only while the tag
remains on the current remote `main` history.

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
`release` Environment gate again if a reviewer rule is configured, but the
current Environment has no protection rules. It does not rebuild or republish
the release.

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
remote_tag_ref=''
remote_ref_nonce=''
cleanup_local_release() {
  local status=$?
  trap - EXIT HUP INT TERM
  [[ -z "$remote_tag_ref" ]] || git update-ref -d "$remote_tag_ref" >/dev/null 2>&1 || :
  [[ -z "$remote_ref_nonce" || ! -d "$remote_ref_nonce" ]] || rmdir "$remote_ref_nonce" || :
  unset R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY TAP_GH_TOKEN
  exit "$status"
}
trap cleanup_local_release EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
git fetch --prune --no-tags origin '+refs/heads/main:refs/remotes/origin/main'
test -z "$(git status --porcelain=v1 --untracked-files=all)"
release_commit="$(git rev-parse HEAD)"
remote_main_commit="$(git rev-parse refs/remotes/origin/main)"
git show-ref --verify --quiet "refs/tags/$release_tag"
test "$(git rev-parse "refs/tags/$release_tag^{commit}")" = "$release_commit"
remote_ref_nonce="$(mktemp -d "${TMPDIR:-/tmp}/updatebar-manual-tag.XXXXXX")"
remote_tag_ref="refs/updatebar-release-verification/${remote_ref_nonce##*/}"
git fetch --force --no-tags origin \
  "+refs/tags/$release_tag:$remote_tag_ref"
test "$(git rev-parse "$remote_tag_ref^{commit}")" = "$release_commit"
git merge-base --is-ancestor "$release_commit" "$remote_main_commit"
git update-ref -d "$remote_tag_ref"
remote_tag_ref=''
rmdir "$remote_ref_nonce"
remote_ref_nonce=''

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

## Safety Model

Imported recipes are saved as `untrusted`. `status` only reads local state. `check` and `update` refuse untrusted or unapproved command fields.

Approved recipe commands are not sandboxed. They run with your user privileges after fingerprint approval, with an allowlisted environment, time/output caps, and redacted captured output.

See [docs/security.md](docs/security.md) for details.

Contributing notes live in [CONTRIBUTING.md](CONTRIBUTING.md).
Shell completion setup lives in [docs/completions.md](docs/completions.md).
Background check setup lives in [docs/background.md](docs/background.md).
Architecture notes live in [docs/architecture.md](docs/architecture.md).
Troubleshooting lives in [docs/troubleshooting.md](docs/troubleshooting.md).
