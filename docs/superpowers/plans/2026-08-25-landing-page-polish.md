# UpdateBar Landing Page Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refine the existing static landing page into a more cinematic, trustworthy product surface with a clearer install action.

**Architecture:** Preserve the semantic HTML, local assets, and no-script runtime. Apply the visual refinement almost entirely in `docs/landing.css`, using the existing landing contract and real browser screenshots as verification.

**Tech Stack:** Static HTML5, CSS, Bash contract test, `@vercel/before-and-after`

---

### Task 1: Establish the clean visual baseline

**Files:**
- Test: `Scripts/landing-contract-test.sh`
- Reference: `docs/index.html`
- Reference: `docs/landing.css`

- [x] **Step 1: Run the static contract before editing**

Run: `rtk test Scripts/landing-contract-test.sh`

Expected: `landing contract passed`

- [x] **Step 2: Preserve the desktop baseline**

Run:

```bash
rtk before-and-after \
  'file:///Users/kendrick/projects/UpdateBar/.worktrees/landing-polish/docs/index.html' \
  'file:///Users/kendrick/projects/UpdateBar/.worktrees/landing-polish/docs/index.html' \
  --size 1440x1000 \
  --output /Users/kendrick/projects/UpdateBar/.superpowers/screenshots/baseline
```

Expected: two PNG paths; keep the `before` image for the final comparison.

- [x] **Step 3: Add the failing polish contract**

Add two focused assertions to `Scripts/landing-contract-test.sh` before changing production CSS:

```bash
grep -q -- '--surface-glass:' "$style"
grep -q 'grid-auto-flow: dense' "$style"
```

Run: `rtk test Scripts/landing-contract-test.sh`

Expected: FAIL because `--surface-glass` is not defined yet.

### Task 2: Refine the cinematic hero and product stage

**Files:**
- Modify: `docs/landing.css`

- [x] **Step 1: Add precise surface and motion tokens**

Extend `:root` with the reusable values used by the refinement:

```css
--surface-glass: rgba(11, 17, 25, 0.72);
--line-bright: rgba(255, 255, 255, 0.18);
--blue-glow: rgba(57, 140, 255, 0.24);
--ease-out: cubic-bezier(0.2, 0.7, 0.2, 1);
```

- [x] **Step 2: Turn the header into a restrained floating control**

Keep `.site-header` semantic placement and add a translucent inner surface, thin border, radius, and backdrop blur without introducing fixed positioning or JavaScript.

```css
.site-header {
  margin-top: 18px;
  padding: 10px 12px 10px 14px;
  border: 1px solid var(--line-soft);
  border-radius: 16px;
  background: var(--surface-glass);
  box-shadow: 0 10px 40px rgba(0, 0, 0, 0.18);
  backdrop-filter: blur(20px) saturate(130%);
}
```

- [x] **Step 3: Tighten hero hierarchy without changing copy**

Use a wide two-line heading, balanced supporting copy, integrated trust surface, and high-contrast CTA. Keep desktop product proof visible in the first 1000px viewport.

```css
.hero { padding-top: 88px; }
.hero-copy { max-width: 960px; }
h1 { max-width: 1000px; margin-inline: auto; text-wrap: balance; }
.hero-lede { max-width: 590px; }
.trust-row {
  width: fit-content;
  margin-inline: auto;
  padding: 9px 14px;
  border: 1px solid var(--line-soft);
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.025);
}
```

- [x] **Step 4: Give the real product screenshot a deliberate stage**

Add a controlled blue glow, inner highlight, shallow perspective, and hover response. Do not alter the images or CSS-only three-state sequence.

```css
.demo-reel::before {
  position: absolute;
  inset: 10% 8% -5%;
  z-index: -1;
  border-radius: 50%;
  background: var(--blue-glow);
  filter: blur(70px);
  content: "";
}
.demo-window {
  transform: perspective(1400px) rotateX(1.2deg);
  transform-origin: center top;
  transition: transform 700ms var(--ease-out), border-color 300ms ease;
}
.demo-reel:hover .demo-window {
  border-color: var(--line-bright);
  transform: perspective(1400px) rotateX(0deg) translateY(-4px);
}
```

- [x] **Step 5: Run the contract**

Run: `rtk test Scripts/landing-contract-test.sh`

Expected: `landing contract passed`

### Task 3: Strengthen install conversion and content rhythm

**Files:**
- Modify: `docs/landing.css`

- [x] **Step 1: Make install the dominant conversion surface**

Increase chapter spacing, use a stronger border and layered blue surface, and improve command legibility without adding clipboard behavior.

```css
.source-cta__inner {
  border-color: rgba(112, 170, 255, 0.24);
  background:
    radial-gradient(circle at 78% 18%, rgba(57, 140, 255, 0.2), transparent 26rem),
    linear-gradient(135deg, rgba(39, 81, 145, 0.18), transparent 56%),
    var(--surface-strong);
}
.source-command {
  border-color: rgba(98, 217, 233, 0.2);
  box-shadow: inset 0 1px rgba(255, 255, 255, 0.04), 0 12px 30px rgba(0, 0, 0, 0.2);
}
```

- [x] **Step 2: Improve workflow continuity**

Use the existing three cards and connectors. Add clearer top accents and hover/focus movement while preserving the Scan → Review → Update order.

```css
.step {
  position: relative;
  overflow: hidden;
  transition: transform 300ms var(--ease-out), background 300ms ease;
}
.step::before {
  position: absolute;
  top: -1px;
  left: 0;
  width: 72px;
  height: 2px;
  background: linear-gradient(90deg, var(--cyan), transparent);
  content: "";
}
.step:hover {
  background: linear-gradient(180deg, rgba(112, 170, 255, 0.05), transparent);
  transform: translateY(-4px);
}
.step-connector { color: rgba(98, 217, 233, 0.55); }
```

- [x] **Step 3: Refine the gapless feature grid**

Keep exactly four cards in a 2×2 desktop grid, set `grid-auto-flow: dense`, and add distinct but restrained hover light. Verify four items fill four cells with no empty space.

```css
.feature-grid { grid-auto-flow: dense; }
.feature { position: relative; overflow: hidden; }
.feature::after {
  position: absolute;
  inset: auto -20% -60% 20%;
  height: 180px;
  background: radial-gradient(circle, rgba(112, 170, 255, 0.12), transparent 68%);
  content: "";
  opacity: 0;
  transition: opacity 400ms ease;
  pointer-events: none;
}
.feature:hover::after { opacity: 1; }
```

- [x] **Step 4: Run the contract and whitespace check**

Run: `rtk test Scripts/landing-contract-test.sh && rtk git diff --check`

Expected: contract passes and `git diff --check` prints no errors.

### Task 4: Verify responsive behavior and produce comparison assets

**Files:**
- Verify: `docs/index.html`
- Verify: `docs/landing.css`
- Create outside Git tracking: `.superpowers/screenshots/landing-polish/*.png`

- [x] **Step 1: Capture desktop after state at the baseline viewport**

Run `before-and-after` at `1440x1000`, using the preserved baseline PNG and the refined `docs/index.html` URL.

Expected: before and after PNGs with matching dimensions.

- [x] **Step 2: Capture responsive states**

Capture tablet at `768x1024` and mobile at `390x844`. Inspect overflow, heading line count, CTA layout, demo crop, command scrolling, and feature stacking.

- [x] **Step 3: Verify reduced-motion and contract behavior**

Confirm `prefers-reduced-motion` still freezes the overview poster and removes nonessential transitions. Run:

```bash
rtk test Scripts/landing-contract-test.sh
rtk git diff --check
rtk git status --short
```

Expected: contract passes; no whitespace errors; only the plan and landing-specific CSS are changed.

- [x] **Step 4: Commit the implementation**

```bash
rtk git add docs/landing.css docs/superpowers/plans/2026-08-25-landing-page-polish.md
rtk git commit -m "style: refine landing page visual hierarchy"
```
