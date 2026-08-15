# UpdateBar Documentation

Use this page as the entry point for UpdateBar documentation. The root
[README](../README.md) provides the product overview and shortest path to a
working installation.

## Get Started

- [Installation](install.md) — install, upgrade, verify, and uninstall the app,
  CLI, and TUI
- [Quick start](../README.md#quick-start) — discover, register, review, check,
  and update tools
- [Troubleshooting](troubleshooting.md) — recover from common installation,
  build, TUI, and menu bar failures
- [Shell completions](completions.md) — configure Bash, Zsh, or Fish completion
- [Background checks](background.md) — manage the optional macOS LaunchAgent

## Use UpdateBar

- [CLI reference](cli.md) — commands, flags, output contracts, and exit codes
- [Menu bar app](menu-bar.md) — menu actions, dashboard behavior, settings, and
  diagnostic logs
- [TUI](../tui/README.md) — install, run, and develop the Ink terminal UI
- [Manifest](manifest.md) — recipe schema and manifest structure
- [Scan and guided init](scan-init-spec.md) — discovery rules, candidates, and
  selection behavior

## Understand The System

- [Architecture](architecture.md) — boundaries between the core, CLI, TUI, and
  macOS app
- [Binary resolution](binary-resolution.md) — how presentation layers locate the
  `updatebar` executable
- [Security](security.md) — trust states, approvals, secret handling, and the
  command execution boundary
- [Core boundary audit](core-boundary-audit.md) — ownership of business and
  presentation logic

## Develop And Release

- [Development](development.md) — prerequisites, builds, tests, and local app/TUI
  workflows
- [Contributing](../CONTRIBUTING.md) — repository rules and contribution checks
- [Release workflow](release-workflow.md) — concise release path and recovery
- [Release reference](release.md) — detailed release contracts, signing,
  packaging, and publication
- [Repository maintenance audit](repo-maintenance-audit.md) — current ownership,
  dependency, and security maintenance notes

## Historical Planning

These files preserve product decisions and implementation history. They are not
the primary operational documentation.

- [Historical PRD](../PRD.md)
- [Initial implementation plan](../plan.md)
- [Current-direction decision record](../current-plan.md)
- [Historical roadmap](../next-plan.md)
- [Release readiness audit](../release-plan.md)
- [Current implementation architecture](../current-architecture.md)
- [Feature designs and plans](superpowers/)
- [OpenSpec changes and specifications](../openspec/)

Current blockers remain in [BLOCKERS.md](../BLOCKERS.md) and
[SECURITY_BLOCKERS.md](../SECURITY_BLOCKERS.md).
