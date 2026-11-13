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
- ignores relative `PATH` entries such as `.` when resolving that binary
- invokes only `updatebar check --exit-zero-on-outdated`
- never invokes `update`, `import`, `approve`, or `remove`
- sets `UPDATEBAR_HOME` to the home used at install time
- uses `StartInterval` of 3600 seconds by default
- does not auto-load via `launchctl`; log out/in or load the plist manually if needed

Security:

- background checks may execute approved `check.cmd` and `latest.cmd`
- untrusted or unapproved recipes are skipped
- this is still not a sandbox

## Daily maintenance in the menu bar app

Settings → Daily maintenance offers **Off**, **Check only**, and **Check and update
approved items**. The default is **Check only, every day at 09:00 local time**.
Choose a time and click **Save**. The schedule is separate from **Status cache
lifetime**, which controls how long cached version information stays fresh.

Keep UpdateBar running in the menu bar. Closing the Dashboard window is fine;
quitting UpdateBar stops this schedule. A missed run starts after wake or after
the current task finishes, with at most one scheduled attempt per local day.
Restarting the app or changing the time does not trigger a second attempt that
day. Failed attempts can be retried manually with Check Now or Update All.

Check and update performs a fresh check, then uses the same approval, enabled,
pin, and outdated-state checks as Update All. It never approves commands. A
recipe whose fresh check fails is excluded from updates. Stop after Current
prevents starting updates after the check phase.

The config keys are `schedule.mode` (`off`, `check`, `check_and_update`) and
`schedule.time` (24-hour `HH:mm`). These settings apply to the menu bar app only.
The separate CLI LaunchAgent above retains its existing check-only behavior.

In the opt-in CLI-adapter mode, an older CLI that does not recognize the schedule
keys leaves scheduling off. Other preferences remain available; update the CLI
before saving a schedule change. Aggregate config JSON keeps its existing shape;
schedule values are read through `config get schedule.mode --json` and
`config get schedule.time --json`.
