# Install

UpdateBar supports three install paths: Homebrew CLI, GitHub release CLI binary,
and optional macOS app bundle. Use Homebrew for normal macOS CLI installs, the
GitHub release installer for one-command CLI installs without Homebrew, and the
app bundle when you want the menu bar UI.

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

## Homebrew CLI

```bash
brew tap sonim1/tap
brew install sonim1/tap/updatebar
updatebar doctor
```

Use this path for normal CLI usage.

## GitHub Release CLI Binary

```bash
curl -fsSL https://raw.githubusercontent.com/sonim1/UpdateBar/main/Scripts/install-release.sh | bash
updatebar doctor
```

Install a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/sonim1/UpdateBar/main/Scripts/install-release.sh | bash -s -- v0.2.0
```

Set `UPDATEBAR_INSTALL_PREFIX` when installing outside `~/.local/bin`.
The installer uses `curl`, `tar`, and `install`, then verifies the downloaded
archive with `shasum` or `sha256sum` against the release checksum.

## macOS App Bundle

The app bundle is optional and installs `UpdateBar.app`. It is a menu bar app,
so double-clicking it should show an `UB` menu bar item instead of a Dock window.

```bash
brew tap sonim1/tap
brew install --cask sonim1/tap/updatebar-app
```

The cask installs only `UpdateBar.app`. Install the CLI separately with:

```bash
brew install sonim1/tap/updatebar
```

Manual GitHub Release install:

```bash
VERSION=0.2.0
ARCH=arm64
curl -fL "https://github.com/sonim1/UpdateBar/releases/download/v${VERSION}/UpdateBar-${VERSION}-macos-${ARCH}.app.tar.gz" -o /tmp/UpdateBar.app.tar.gz
tar -xzf /tmp/UpdateBar.app.tar.gz -C /Applications
open /Applications/UpdateBar.app
```

The app is currently unsigned. If macOS blocks the first launch,
Control-click `UpdateBar.app` in Finder, choose Open, then confirm Open.

Runtime logs are written to:

```
~/Library/Logs/UpdateBar/updatebar-menubar.log
```
