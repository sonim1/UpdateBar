# AI installation prompt implementation plan

**Goal:** Offer the same installation prompt on the landing page and README for a coding agent with terminal access.

**Architecture:** Keep Homebrew instructions. Add native details with selectable prompt text to home and macOS, enhanced by a small same-origin clipboard script. README uses a fenced text block. No dependencies, browser installer or recipe approval.

**Design:** Follow docs/DESIGN.md and existing install surfaces. The previously proposed Copy prompt approach was accepted by the user's instruction to continue. Manual selection remains available when JavaScript or clipboard permission is unavailable.

- Add matching prompt to README, home and macOS. Link official installation instructions; inspect OS/architecture/existing install, preserve configuration, verify version and doctor, exclude recipe approval and tracked-tool updates.
- Add clipboard enhancement and responsive wrapping; update the landing contract to permit only this exact deferred local script while still rejecting other scripts.
- Run landing contract, real-browser clipboard success/failure/no-JS and keyboard checks, capture 375/768/1280px pages, and review the current commit.
- Pass CI, merge, publish tracked docs, verify production copying, and clean the task branch/worktree.

Execution status and verification evidence live in .omo/evidence/ai-install-prompt (not published).
