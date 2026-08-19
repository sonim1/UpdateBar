# UpdateBar Landing Page Design

**Date:** 2026-08-19  
**Status:** Approved direction; implementation plan pending  
**Primary goal:** Make a new visitor understand within five seconds that UpdateBar tracks heterogeneous local tools and runs only update commands they explicitly approve.

## Scope

Create a responsive static landing page at `docs/index.html`, using the existing SwitchTab landing page as the structural and quality reference. The page is a presentation layer only. It does not change UpdateBarCore, the CLI, the menu bar app, release automation, update feeds, permissions, or product behavior.

The initial implementation includes the page, local product imagery, a focused stylesheet, a static contract test, and a README link. Publishing to Cloudflare Pages or a custom domain is a separate task because the UpdateBar repository does not yet contain a landing deployment contract or confirmed Pages project.

## Chosen approach

Use a faithful structural port of the SwitchTab landing page rather than a line-for-line clone:

1. centered benefit-led hero;
2. one wide, real-product visual directly below the hero;
3. concise installation section;
4. three-step workflow;
5. focused feature proof;
6. restrained footer.

Keep SwitchTab's dark, macOS-native visual discipline while giving UpdateBar its own blue-cyan accent, copy, imagery, and update-oriented motion. A minimal documentation-style page was rejected because it would undersell the native app. A full visual reinvention was rejected because it adds risk without improving the proven hierarchy.

## Visual thesis

A calm, trustworthy macOS control surface: near-black canvas, cool blue-cyan light, native app imagery, crisp typography, and restrained glass only around real product surfaces. The page should feel operational and safe rather than futuristic or automated.

Design rules:

- brand and promise dominate the first screen;
- one accent family, blue through cyan;
- system typography only; no remote fonts;
- cards appear only where a distinct feature needs a bounded visual;
- no generic dashboard mosaics, logo clouds, testimonials, pricing, or decorative gradients competing with the product;
- imagery must show the real UpdateBar app with staged, public-safe data.

## Content plan

### Header

- UpdateBar app icon and wordmark on the left.
- `GitHub` text link and compact `Install` button on the right.
- Header remains lightweight and does not consume a separate visual band on mobile.

### Hero

- Eyebrow: `Trusted updates, one place.`
- Headline: `Every tool. One update away.`
- Supporting copy: `Track local tools, review what changed, and run only the update commands you approve.`
- Primary CTA: `Install UpdateBar`, linking to `#install`.
- Secondary CTA: `See how it works`, linking to `#how-it-works`.
- Trust row: `macOS 13+`, `Native Swift`, `Signed & notarized`, and `No telemetry`.

These claims come from the current README and menu bar documentation. The page must not claim that recipe commands are sandboxed or that UpdateBar safely runs arbitrary recipes.

### Product demo

Place one wide demo below the centered hero copy, matching SwitchTab's current first-view composition. Use real UpdateBar captures produced from a temporary staged `UPDATEBAR_HOME`, never the user's real registry, paths, logs, usernames, or installed-tool inventory.

The CSS-only nine-second sequence has three three-second beats:

1. **See:** Dashboard Overview shows updates available and approval waiting.
2. **Review:** the native menu or approval confirmation shows that command approval is explicit.
3. **Update:** the native menu shows bounded progress and a completed state.

Use stable hard cuts or short opacity transitions between captures. Do not recreate the native app UI in HTML, animate fake command execution, or add video, canvas, or JavaScript. Mark visual layers decorative and provide one adjacent caption explaining the sequence. Under `prefers-reduced-motion: reduce`, stop on the representative Overview poster.

If a trustworthy three-state capture cannot be produced without changing product code, ship the Overview poster as a static hero visual. Do not substitute a fabricated dashboard.

### Install

- Heading: `One command. Everything current.`
- Primary Homebrew command: `brew install --cask sonim1/tap/updatebar-app`.
- Secondary actions: latest GitHub release and CLI-only Homebrew formula.
- Supporting note: the cask includes the signed macOS app and bundled `updatebar` CLI.

### Workflow

Use three steps, adapted from SwitchTab's `Hold → Cycle → Release` structure:

1. `Scan` — discover supported local tools without changing state;
2. `Review` — inspect versions and approve exact command fields where required;
3. `Update` — update one item or all approved outdated items from the app or CLI.

The sequence must preserve the product's security boundary: scanning does not silently approve commands, and updates run only after the required approval.

### Feature proof

Use four focused feature blocks:

1. **One registry** — track Homebrew, npm, GitHub releases, files, and custom recipes in one place.
2. **Explicit trust** — imported and discovered commands remain gated by exact fingerprints.
3. **Native where it matters** — use the menu bar and Dashboard for daily operation.
4. **CLI when you need it** — deterministic JSON and JSONL contracts support terminals and agents.

Copy stays concrete and must not imply built-in AI generation, automatic approval, full sandboxing, sync, a community registry, or telemetry.

### Footer

- UpdateBar icon and wordmark.
- One short line: `A trusted update layer for the tools already on your machine.`
- Links only where useful: GitHub, installation, security, and documentation.

## Interaction thesis

Use three restrained motion ideas:

1. a short hero entrance for the eyebrow, headline, actions, and demo frame;
2. the CSS-only three-beat product sequence;
3. small CTA, command-row, and feature hover/focus transitions that clarify affordance.

All motion must stop or simplify under reduced-motion preferences. No interaction is required to understand the page.

## Architecture and file boundaries

- `docs/index.html` — semantic page structure, product copy, local asset references, accessible labels, and anchor navigation.
- `docs/landing.css` — design tokens, layout, responsive behavior, focus states, demo timing, and reduced-motion behavior.
- `docs/AppIcon-256.png` and favicon asset — web-sized derivatives of the existing product icon.
- `docs/demo/` — optimized, privacy-safe real product captures with stable descriptive names.
- `scripts/tests/landing-contract-test.sh` — verifies structure, local assets, forbidden dependencies, public-safe paths, asset limits, and reduced-motion hooks.
- `README.md` — adds a landing-page source link without replacing the existing documentation index.

The page has no runtime data flow. Browser requests load only local HTML, CSS, and image assets. CTA links navigate to repository documentation or GitHub release pages.

## Responsive and accessibility behavior

- Desktop uses centered copy and a wide product demo.
- Tablet preserves the full frame at reduced scale.
- At 640px and below, the demo uses a deliberate crop or mobile-safe static poster so status text remains legible.
- The page remains usable at 320px without horizontal overflow.
- Use one `h1`, semantic sections, visible keyboard focus, meaningful link labels, and sufficient contrast.
- Decorative screenshot layers are hidden from assistive technology; nearby text communicates the same workflow.
- No essential meaning depends only on color or motion.
- `prefers-reduced-motion` disables entrance animation and freezes the demo on a representative frame.

## Failure and fallback behavior

The page has no dynamic operations or client-side error state. Broken or missing assets must fail the static contract before merge. The representative poster is loaded in the initial document flow, so the hero remains understandable if animation is unavailable. External GitHub and documentation links are verified during implementation but do not block local rendering.

## Verification

### Static contract

- `docs/index.html`, `docs/landing.css`, icon derivatives, and every referenced demo asset exist and are non-empty.
- Exactly one `h1`, one `main`, one `footer`, `#install`, and `#how-it-works` exist.
- No script, video, canvas, analytics, tracker, remote image, remote font, insecure URL, local filesystem identifier, `TODO`, or placeholder text appears.
- Demo assets have an explicit inventory and total byte limit; the poster has a separate first-load limit.
- Reduced-motion CSS disables all nonessential animation and reveals the stable poster.
- `git diff --check` passes.

### Browser QA

- Verify desktop, tablet, 390px mobile, and 320px mobile layouts.
- Confirm the first viewport establishes brand, promise, CTA, and product visual.
- Confirm all demo states appear in order with no blank frame or stretched capture.
- Confirm keyboard navigation, focus visibility, anchor navigation, and reduced-motion rendering.
- Confirm no console errors, missing assets, or unexpected network requests.

### Repository QA

- Run the landing contract test.
- Run the existing project quality gate or the smallest equivalent Swift test suite to prove landing files do not affect the app.
- Confirm the final diff is limited to landing, test, and documentation files.

## Non-goals

- No deployment workflow, Cloudflare project creation, DNS, analytics, or custom domain in this implementation.
- No changes to native app UI, app fixtures, release automation, Sparkle, Homebrew publishing, or update behavior.
- No live web simulator, interactive command execution, signup form, pricing, testimonials, blog, registry browser, or recipe marketplace.
- No reuse of SwitchTab product imagery or SwitchTab-specific copy.

## Success criteria

A first-time visitor can answer these questions after scanning the first viewport:

1. What is UpdateBar? A macOS app and CLI for tracking and updating local tools.
2. Why trust it? Commands require explicit, fingerprinted approval and the product has no telemetry.
3. How do I start? Install the signed app and bundled CLI with the displayed Homebrew command.

