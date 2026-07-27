# Blockers

There are no repository or release blockers as of 2026-07-20.

TypeScript 7.0.2 was evaluated and is outside the official peer range of the
current `typescript-eslint` release (`>=4.8.4 <6.1.0`). UpdateBar therefore keeps
TypeScript 6.0.3 until the lint toolchain declares support; no force-install or
legacy peer override is used.

`Scripts/generate-appcast-test.sh` fails on a clean checkout of `main` (verified
against `3f69e02` with no working-tree changes): the keychain fixture stage exits
66 with `Missing or unsafe DMG: .../dist/UpdateBar-0.6.3-macos-arm64.dmg`. Both
CI jobs already route around it via `SKIP_SIGNED_APPCAST=1` (`a7ebfd7`,
`40e4f0d`), so local gate runs need the same skip until the fixture builds its
own DMG. This is unrelated to release credential wiring.

Ignored build outputs and local tool state are intentionally retained. A
`git clean -ndX` preview includes Swift dependency checkouts, `.omo/`,
`.superpowers/`, `dist/`, and `tui/node_modules/`; deleting these is local
housekeeping and is not required to build, test, or release UpdateBar.
