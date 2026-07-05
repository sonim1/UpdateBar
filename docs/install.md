# Install

UpdateBar supports three install paths: Homebrew CLI, GitHub release CLI binary,
and optional macOS app bundle.

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

The app bundle is optional and installs `UpdateBar.app`.

```bash
brew tap sonim1/tap
brew install --cask sonim1/tap/updatebar-app
```

The cask installs only `UpdateBar.app`. Install the CLI separately with:

```bash
brew install sonim1/tap/updatebar
```

The app is currently unsigned. If macOS blocks the first launch,
Control-click `UpdateBar.app` in Finder, choose Open, then confirm Open.

## Verify Install

Run one-command verification from a checkout:

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
