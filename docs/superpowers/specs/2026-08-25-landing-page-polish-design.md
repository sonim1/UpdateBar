# UpdateBar Landing Page Polish Design

**Date:** 2026-08-25
**Status:** Approved direction
**Primary goal:** Increase perceived trust and product quality while making the Homebrew install action more prominent.

## Relationship to the existing design

This is a focused visual refinement of the landing page defined in `2026-08-19-updatebar-landing-page-design.md`. It does not replace the page structure, product claims, local assets, or security constraints. Every changed line must improve hierarchy, polish, product proof, or install conversion.

## Chosen direction

Use **Cinematic Trust**: preserve the near-black blue-cyan identity, but give the page stronger editorial rhythm, deeper product framing, more deliberate typography, and a clearer action path.

The page keeps its static HTML/CSS architecture. The `gpt-taste` motion recommendation is adapted to CSS because the landing contract explicitly forbids scripts. GSAP, remote fonts, remote images, analytics, video, and canvas remain out of scope.

## Visual system

- Use the existing system font stack, tuned toward a Geist-like neutral grotesk character through weight, tracking, and line-height.
- Keep the hero centered and cinematic. The H1 remains two lines at desktop and no more than three lines on narrow screens.
- Expand the content shell and hero breathing room without hiding the product screenshot below the fold at common desktop heights.
- Replace broad ambient glow with tighter blue light around the product proof and subtle grain/grid texture already generated in CSS.
- Use one radius scale, one border hierarchy, and one shadow language across the demo, install panel, and feature grid.
- Maintain white-on-dark button contrast and visible keyboard focus.

## Page refinements

### Navigation and hero

- Keep the compact brand, GitHub link, and Install action.
- Make the header feel like a precise floating control through a restrained translucent surface and hairline border.
- Keep `Every tool. One update away.` and its product-safe supporting copy.
- Strengthen the primary CTA and make the secondary CTA quieter.
- Preserve the trust row, but integrate it into the hero composition rather than presenting it as detached metadata.

### Product proof

- Keep the three real product captures and CSS-only sequence.
- Give the demo a more intentional stage: subtle perspective, inner highlight, controlled glow, and concise caption.
- Preserve the pause/play control, poster fallback, asset limits, and reduced-motion behavior.
- Do not fabricate app chrome or add decorative stock imagery.

### Install action

- Treat the install block as the page's primary conversion surface.
- Increase its contrast against surrounding sections, reduce copy width, and improve command readability.
- Keep the exact Homebrew command and existing release links.
- Do not add clipboard JavaScript; the no-script contract remains authoritative.

### Workflow and feature proof

- Keep the three-step Scan → Review → Update narrative.
- Improve flow through spacing, connectors, and state-like visual accents without adding fake interaction.
- Keep four features in a gapless 2×2 grid on desktop and a single column on mobile. Four cards occupy four cells, leaving zero empty grid cells.
- Make card hover and focus feedback subtle and nonessential.

### Footer

- Keep the existing concise brand statement and four links.
- Increase separation from the final content chapter without turning the footer into another card.

## Responsive and accessibility behavior

- Verify at 1440×1000, 768×1024, 390×844, and 320×700.
- Keep all content within the viewport width with no horizontal scrolling.
- At small widths, prioritize readable heading scale, full-width CTA, legible demo crop, and command overflow handling.
- Preserve semantic headings, focus-visible states, accessible navigation labels, and text equivalents for decorative product imagery.
- `prefers-reduced-motion: reduce` must freeze the demo on the overview poster and remove nonessential entrance motion.

## File boundaries

- `docs/index.html`: only minimal semantic wrappers or class changes needed for the refined composition.
- `docs/landing.css`: tokens, layout, surfaces, responsive rules, and CSS motion.
- `Scripts/landing-contract-test.sh`: change only if the refined markup requires a directly relevant contract assertion.
- Existing local image assets remain unchanged unless visual verification proves a crop is unusable.

## Verification

1. Capture the unchanged page at 1440×1000 as the baseline.
2. Run `Scripts/landing-contract-test.sh` and `git diff --check`.
3. Inspect desktop, tablet, 390px mobile, and 320px mobile rendering.
4. Verify keyboard focus, anchors, pause/play control, reduced motion, and command overflow.
5. Capture the finished page at the same 1440×1000 viewport and generate a before/after comparison.
6. Confirm the final code diff is limited to landing-specific files.

## Success criteria

- The first viewport communicates trust, product proof, and the install action in that order.
- The page looks materially more polished while remaining recognizably UpdateBar.
- The H1 stays within two desktop lines and three mobile lines.
- The 2×2 feature grid has no empty cells.
- Static contract, responsive checks, accessibility checks, and before/after capture pass.
