# Background Checks

UpdateBar can install an opt-in macOS per-user LaunchAgent for background checks.

Install:

```bash
updatebar background install --yes
```

The human output includes the manual load command:

```bash
launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.updatebar.check.plist"
```

Status:

```bash
updatebar background status
```

Plain status output is tab-separated with `STATUS`, `LABEL`, and `PATH` columns.
Install and uninstall use the same columns. Use `--json` for machine-readable automation.
JSON output includes `ok`, `path`, `label`, and the subcommand state:
`installed` for install/status or `removed` for uninstall.

Uninstall:

```bash
updatebar background uninstall
```

If the agent was loaded manually, the human output includes the unload command:

```bash
launchctl bootout gui/$(id -u)/com.updatebar.check
```

Behavior:

- writes `~/Library/LaunchAgents/com.updatebar.check.plist`
- runs the installed `updatebar` binary by absolute path
- invokes only `updatebar check --exit-zero-on-outdated`
- never invokes `update`, `import`, `approve`, or `remove`
- sets `UPDATEBAR_HOME` to the home used at install time
- uses `StartInterval` of 3600 seconds by default
- does not auto-load via `launchctl`; log out/in or load the plist manually if needed

Security:

- background checks may execute approved `check.cmd` and `latest.cmd`
- untrusted or unapproved recipes are skipped
- this is still not a sandbox
