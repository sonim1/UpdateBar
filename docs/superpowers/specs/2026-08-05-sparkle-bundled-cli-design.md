# Sparkle bundled CLI continuity

## Goal

An UpdateBar installation made through `updatebar-app` must keep the
`updatebar` command current when Sparkle replaces `UpdateBar.app`.

## Design

Homebrew links `updatebar` to the stable application path:

```
/Applications/UpdateBar.app/Contents/Resources/updatebar
```

Sparkle replaces the application bundle at that same path. Therefore the
existing Homebrew symlink resolves to the CLI contained in the newly installed
bundle without an app-side relink step or Homebrew mutation.

## Verification

The packaging test creates a versioned fake bundled CLI, links a launcher to
the stable app-bundle path, replaces the bundle, and asserts that the launcher
now reports the replacement version. This protects the path contract used by
the Cask and Sparkle update flow.
