# Security Policy

## Reporting a Vulnerability

Please report suspected vulnerabilities privately through GitHub Security
Advisories for `sonim1/UpdateBar` when available.

If private reporting is unavailable, email the maintainer before opening a
public issue. Do not include working exploit details, private tokens, or user
data in public issues.

## Scope

Security-sensitive areas include:

- recipe validation, command approval, and trust fingerprints
- command execution environment filtering
- release archives, Homebrew metadata, and installer checksum handling
- macOS app packaging, signing, and notarization

UpdateBar has no telemetry and does not collect vulnerability reports from
installed clients.
