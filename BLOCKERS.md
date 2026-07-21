# Blockers

There are no repository or release blockers as of 2026-07-20.

TypeScript 7.0.2 was evaluated and is outside the official peer range of the
current `typescript-eslint` release (`>=4.8.4 <6.1.0`). UpdateBar therefore keeps
TypeScript 6.0.3 until the lint toolchain declares support; no force-install or
legacy peer override is used.

Ignored build outputs and local tool state are intentionally retained. A
`git clean -ndX` preview includes Swift dependency checkouts, `.omo/`,
`.superpowers/`, `dist/`, and `tui/node_modules/`; deleting these is local
housekeeping and is not required to build, test, or release UpdateBar.
