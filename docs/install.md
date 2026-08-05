# Install

UpdateBar supports three install paths: a Homebrew app cask with the bundled
CLI, a standalone CLI, and a manual macOS app bundle. Use the cask for normal
macOS installs, the formula or GitHub release installer for CLI-only installs,
and the manual app bundle when installing without Homebrew.

Published Homebrew formula and cask assets currently target Apple Silicon
macOS (`arm64`). Intel Mac users should build from source until x86_64 or
universal macOS assets are published.

## After Any CLI Install

Verify the installed CLI without a checkout:

```bash
updatebar --version
updatebar doctor
updatebar scan
updatebar status --json --exit-zero-on-outdated >/dev/null
```

From a source checkout, run the same checks with one-command verification:

```bash
Scripts/cli-smoke-test.sh
```

The smoke test runs:

```bash
updatebar --version
updatebar doctor
updatebar scan
updatebar status --json --exit-zero-on-outdated
```

To verify a specific binary instead of `updatebar` on `PATH`:

```bash
UPDATEBAR_BIN=/full/path/to/updatebar Scripts/cli-smoke-test.sh
```

## Homebrew CLI Only

```bash
brew tap sonim1/tap
brew install sonim1/tap/updatebar
updatebar doctor
```

Use this path when you want the CLI without the menu bar app.

Upgrade:

```bash
brew update
brew upgrade sonim1/tap/updatebar
```

## GitHub Release CLI Binary

```bash
curl -fsSL https://raw.githubusercontent.com/sonim1/UpdateBar/main/Scripts/install-release.sh | bash
updatebar doctor
```

Install a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/sonim1/UpdateBar/main/Scripts/install-release.sh | bash -s -- v0.6.1
```

Set `UPDATEBAR_INSTALL_PREFIX` when installing outside `~/.local/bin`.
The installer uses `curl`, `tar`, and `install`, then verifies the downloaded
archive with `shasum` or `sha256sum` against the release checksum.

Upgrade by rerunning the installer. The default installs the latest GitHub
Release:

```bash
curl -fsSL https://raw.githubusercontent.com/sonim1/UpdateBar/main/Scripts/install-release.sh | bash
```

## macOS App Bundle

The app bundle is optional and installs `UpdateBar.app`. It is a menu bar app,
so double-clicking it should show an `UB` menu bar item instead of a Dock window.

```bash
brew tap sonim1/tap
brew install --cask sonim1/tap/updatebar-app
```

The cask installs `UpdateBar.app` and links its bundled CLI as `updatebar` on
your Homebrew `PATH`:

```bash
updatebar --version
```

That link targets the installed app bundle, rather than a versioned Cask
directory. When the app updates itself through Sparkle, `updatebar` therefore
uses the CLI from the replacement app bundle too; no separate CLI upgrade is
needed.

If both the standalone formula and app cask were installed before this combined
package was available, switch the CLI link to the cask once:

```bash
brew uninstall --formula sonim1/tap/updatebar
brew reinstall --cask sonim1/tap/updatebar-app
hash -r
updatebar --version
```

The optional terminal UI is a separate formula. Launch it with `updatebar tui`:

```bash
brew install sonim1/tap/updatebar-tui
```

Upgrade:

```bash
brew update
brew upgrade --cask sonim1/tap/updatebar-app
```

Manual GitHub Release install:

```bash
VERSION=0.6.1
ARCH=arm64
curl -fL "https://github.com/sonim1/UpdateBar/releases/download/v${VERSION}/UpdateBar-${VERSION}-macos-${ARCH}.app.tar.gz" -o /tmp/UpdateBar.app.tar.gz
tar -xzf /tmp/UpdateBar.app.tar.gz -C /Applications
open /Applications/UpdateBar.app
```

The current `v0.6.1` app asset uses the legacy `.app.tar.gz` format. It is signed
with a Developer ID certificate and notarized by Apple. Starting with the next
published app release, download `UpdateBar-<version>-macos-arm64.dmg`, open it,
and drag `UpdateBar.app` to the DMG's `Applications` shortcut. Those DMGs are
signed, notarized, stapled, and verified with Gatekeeper before publication.

Runtime logs are written to:

```
~/Library/Logs/UpdateBar/updatebar-menubar.log
```

## Uninstall

Remove the standalone formula CLI:

```bash
brew uninstall sonim1/tap/updatebar
```

Remove the app and its bundled CLI link:

```bash
brew uninstall --cask sonim1/tap/updatebar-app
```

If you installed with the GitHub Release installer, remove the installed binary
from your install prefix:

```bash
rm -f "${UPDATEBAR_INSTALL_PREFIX:-$HOME/.local/bin}/updatebar"
```

User data is not removed automatically. Delete it manually only when you no
longer need manifests, state, or logs:

```bash
rm -rf "${UPDATEBAR_HOME:-$HOME/.updatebar}"
rm -rf "$HOME/Library/Logs/UpdateBar"
```
