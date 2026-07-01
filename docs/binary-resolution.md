# Binary Resolution

UpdateBar presentation layers that need to launch the Swift CLI should resolve
the `updatebar` binary in this order:

1. `UPDATEBAR_BIN` environment override.
2. Configured binary path, when a presentation layer exposes one.
3. Legacy `UPDATEBAR_CLI` environment override (deprecated; prefer `UPDATEBAR_BIN`).
4. Bundled `updatebar` next to the macOS app resources.
5. `updatebar` on `PATH`, including `/opt/homebrew/bin` and `/usr/local/bin`
   for Finder-launched macOS apps with a sparse environment.
6. SwiftPM development fallback under `.build/debug/updatebar`, including
   architecture-specific debug directories.

Explicit override paths must be executable. Bundled, `PATH`, and development
fallback candidates are used only when executable.

The Swift Menu Bar layer uses `UpdateBarBinaryResolver`. The future Ink TUI
package should implement the same order and prefer `UPDATEBAR_BIN` when it
spawns the Swift CLI.
