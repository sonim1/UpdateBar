# UpdateBar landing design contract

## 0. Existing product and scope
Preserve the existing static HTML/CSS landing system from landing.css and the August landing/SEO specs. Update product proof to the approved native Items dashboard. The native app is pictured, not simulated. Publish only once the corresponding app release is available.

## 1. Audience and content
Mac developers first need to see which tools can update, choose a scope, and understand command approval. Home introduces these actions, macOS explains five states and batch controls, CLI remains an accurate separate workflow. No unshipped AI, automatic approval, ratings, or fabricated usage claims.

## 2. Tokens and typography
Use existing landing.css tokens: canvas #06090d, raised #0c1219, text #f5f8fc, soft #b5c0ce, faint #788598, blue #70aaff, cyan #62d9e9, green #72d5aa; existing translucent surfaces and border ramps. System sans and system monospace; existing type scale and spacing. Preserve native screen pixels and aspect ratios. Product reel uses1520:904,44px top clearance for its pause control and64px bottom clearance for captions.

## 3. Layout and depth
1200px max shell, 24px desktop/16px mobile gutters. Existing blue glow, inset borders and shadow give product images depth. Home has a three-state product reel; audience pages have stable images. Native app screenshots must be fully visible on narrow screens, never center-cropped into a portrait.

## 4. Motion and accessibility
Keep existing 9s CSS-only three-frame reel, keyboard-operable pause and reduced-motion poster. Place reel controls and captions outside screenshot content. Preserve real links, semantic headings, visible focus, FAQ disclosures. Describe screenshot contents in text/alt and do not rely on image text alone.

## 5. Reusable primitives and states
Existing shell, site-header/nav, button primary/secondary/light and hover/focus, demo-reel/window/frame/caption and pause/reduced-motion, product-frame, story-row/media/copy, fact-list, FAQ details/summary, footer. Existing pages are the state harness; verify 375/768/1280px and keyboard/pause/FAQ states before completion. No new component framework.

AI installation uses a native disclosure beside the Homebrew instructions on home and macOS. Reuse the source-command surface, secondary button and existing text colors; 12px mono prompt, 16px spacing, 14px help text. Wrap the full selectable prompt, including URLs. The macOS install card uses two equal shrinkable columns, stacking at the existing mobile breakpoint, so an expanded prompt cannot collapse the heading. A small deferred same-origin script copies only on a button click, announces success through a status region, and selects the prompt with manual-copy guidance when clipboard access fails. Hide the copy button until the script loads; the disclosure and text work without JavaScript. No installation executes in the browser. Explain that the prompt needs a coding agent with terminal access. Preserve keyboard focus and reduced-motion behavior.

## 6. SEO and publication
Unique concise titles/descriptions reflect visible content. Canonical, OpenGraph, Twitter and JSON-LD describe the same routes/product. Sitemap contains only three public pages and truthful change dates. llms.txt supplies factual product/trust references. Software metadata has no invented reviews or ratings. No ranking guarantee.

## 7. Accepted debt
Existing static HTML repeats shared navigation and metadata; retain this small three-page architecture. Native screenshots use isolated fixture data. CJK localization is outside the current English site. Production audit depends on app release and site publication authorization.

## 8. Stable media URLs
Retain the existing overview.webp, approval.webp and history.webp URLs and their CSS slots while refreshing the native captures to ready, selected-running and completed states. This keeps the existing asset contract and avoids triggering an unrelated app release through a Scripts/ change. Visible captions and alt text describe the actual new images.
