# Blockers

## TypeScript major update decision

- **Blocked item:** Upgrade `typescript` from 6.0.3 to the latest major line reported by `npm outdated`.
- **Why I cannot complete it:** This is a major version change and may alter compiler behavior or type checking semantics across the TUI package.
- **User action:** Decide whether to accept a TypeScript major upgrade in this cleanup cycle.
- **Needed material or decision:** Confirm whether a major toolchain bump is acceptable now, or should wait for a dedicated dependency-upgrade branch.
- **Next step after resolution:** Run the TypeScript major upgrade, then `npm --prefix tui run typecheck`, `lint`, `test`, and `build`.
- **Why no workaround:** Pinning the current major while applying safe patch/minor updates preserves behavior without hiding the outstanding major upgrade.

## Local ignored artifact cleanup approval

- **Blocked item:** Remove ignored build outputs and untracked local directories such as `.build/`, `dist/`, `tui/node_modules/`, `tui/dist/`, and empty untracked source/spec directories.
- **Why I cannot complete it:** These are local workspace artifacts that may belong to the user or another running task; deleting them is destructive and may slow or disrupt active work.
- **User action:** Approve an ignored-only cleanup command or identify which paths should be preserved.
- **Needed material or decision:** Decide whether cleanup should be ignored-only (`git clean -ndX` preview, then `git clean -fdX`) or include specific untracked directories after review.
- **Next step after resolution:** Run a dry-run cleanup preview, confirm the exact target list, then remove only approved paths.
- **Why no workaround:** Leaving artifacts in place is safer than deleting possibly user-owned local state without explicit approval.
