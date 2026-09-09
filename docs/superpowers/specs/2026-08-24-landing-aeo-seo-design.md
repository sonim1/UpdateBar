# UpdateBar Landing AEO/SEO Design

**Date:** 2026-08-24  
**Status:** Approved design  
**Baseline:** `origin/main` at `f9e89b6` (`v0.6.19`)

## Goal

Turn the current single-page landing site into a three-page intent cluster that serves macOS app users and CLI/agent users equally. Preserve the existing product-led visual quality while adding enough precise, source-backed content for search engines and answer engines to identify, summarize, and cite UpdateBar accurately.

The primary conversions are:

- macOS visitors install the app with Homebrew;
- CLI and agent visitors open the safe getting-started workflow.

The public content remains English-only.

## Current State

The existing static landing page already has useful foundations:

- crawlable static HTML with no JavaScript;
- one `h1`, semantic sections, a canonical URL, and a meta description;
- local, small product images;
- accessible focus and reduced-motion behavior;
- no analytics or telemetry.

The audit found these material gaps:

1. `robots.txt`, `sitemap.xml`, `llms.txt`, and arbitrary missing paths return the home document with HTTP `200`. This is a soft-404 deployment behavior.
2. The title and hero headline are slogan-led and do not clearly name the product category or primary search intent.
3. The site has no Open Graph metadata, Twitter card metadata, or structured data.
4. The home page does not answer common product, platform, trust, and agent-integration questions directly.
5. The single page cannot give the macOS and CLI/agent search intents independent titles, canonical URLs, explanations, and conversion paths.

## Chosen Approach

Use an intent-cluster architecture with documentation-level factual depth:

- keep the home page concise and conversion-led;
- add one macOS page and one CLI/agent page with source-backed explanations and FAQs;
- give each page one distinct search intent;
- keep the implementation fully static and script-free;
- add crawl-control, discovery, social preview, structured-data, and real 404 assets;
- reuse the current design system instead of redesigning the site.

A metadata-only change was rejected because it would not create enough topical clarity. A full documentation-site conversion was rejected because it would weaken the landing experience and expand maintenance beyond the requested scope.

## Information Architecture

### `/`

Purpose: define UpdateBar broadly, establish trust, and route visitors to the right product surface.

Required content:

- exact title: `UpdateBar | macOS App and CLI for Updating Developer Tools`;
- exact `h1`: `Update developer tools from one trusted place.`;
- a 40–60 word opening answer identifying UpdateBar as a macOS app and CLI that tracks local tools, compares versions, and runs only explicitly approved update commands;
- the existing product demo and Homebrew install section;
- two equal route cards: `UpdateBar for macOS` and `CLI & agents`;
- a concise explanation of the approval model and the honest non-sandbox boundary;
- a short common FAQ;
- primary links to `/macos/` and `/cli-agents/`.

The existing slogan `Every tool. One update away.` may remain as supporting display copy, but it must not be the only category-level headline.

### `/macos/`

Purpose: answer the intent behind a native macOS developer-tool updater and convert the visitor to a Homebrew app install.

Required content:

- exact title: `UpdateBar for macOS | Update Developer Tools from the Menu Bar`;
- exact `h1`: `Update developer tools from your Mac menu bar.`;
- support statement: macOS 13 or later, with published app assets currently targeting Apple Silicon;
- supported tracking examples: Homebrew, npm, GitHub releases, files, and custom recipes;
- `Scan → Review → Update` workflow;
- native menu bar and Dashboard capabilities, using only claims supported by `README.md` and `docs/menu-bar.md`;
- explicit approval behavior and the statement that approved recipe commands are not sandboxed;
- Homebrew cask install command as the primary CTA;
- links to installation, security, menu bar, and release documentation;
- macOS-specific FAQ covering requirements, CLI inclusion, telemetry, approvals, and uninstallation.

### `/cli-agents/`

Purpose: answer the intent behind a deterministic update CLI for developers and external AI agents, then route visitors into the safe authoring workflow.

Required content:

- exact title: `UpdateBar CLI for Developers and AI Agents`;
- exact `h1`: `A deterministic update CLI for developers and AI agents.`;
- a direct statement that UpdateBar does not contain built-in AI recipe generation;
- an explanation that external agents may author recipe JSON while UpdateBar remains the validation, trust, and execution boundary;
- JSON and JSONL contract use cases;
- the exact safe workflow from schema and template generation through validation, dry-run, import, approval review, and explicit approval;
- a visible warning never to approve commands silently;
- an honest explanation that approved commands run with user privileges and are not sandboxed;
- `updatebar guide agent` as the primary CTA, supported by links to CLI, manifest, security, and installation references;
- CLI/agent FAQ covering read-only status, command approval, recipe validation, secret handling, and supported platforms.

## Content and Trust Rules

Every page must follow these rules:

- Lead with a direct answer before marketing detail.
- Use product facts already supported by repository documentation or behavior tests.
- Use question headings and short self-contained answers where users naturally ask questions.
- Do not claim arbitrary commands are safe, sandboxed, auto-approved, or generated by built-in AI.
- Do not add review scores, usage counts, testimonials, unsupported comparisons, or security superlatives.
- State both sides of the trust boundary: exact command approval is required, and approved commands still run with the user's privileges.
- Keep copy unique enough that each page owns one search intent; do not duplicate full sections across pages.
- Link factual claims to the most authoritative relevant documentation page.
- Keep installation commands exact and consistent with `docs/install.md`.

FAQ content exists to help users and answer engines understand the product. The design does not depend on `FAQPage` rich results, and no FAQ structured data is required.

## Visual Design Direction

Read this as a preservation-focused redesign of a technical product landing site for macOS developers and CLI/agent users. The visual language is calm, native, and trust-first rather than futuristic or AI-themed.

Design dials:

- `DESIGN_VARIANCE: 6` - asymmetric enough to avoid a template-like centered composition while remaining easy to scan;
- `MOTION_INTENSITY: 3` - static product storytelling with hover, focus, and active feedback only;
- `VISUAL_DENSITY: 4` - documentation-level substance with landing-page spacing.

System rules:

- preserve the existing dark graphite theme across every section and page;
- use the existing electric blue as the single interface accent; the original app icon keeps its brand artwork but does not introduce additional UI accent colors;
- retain the system sans-serif stack and monospace only for commands;
- use 14-16px radii for content panels, 10-12px radii for controls, and a larger 20px radius only for product screenshot frames;
- use real UpdateBar screenshots as product imagery; never recreate the Dashboard or terminal as decorative fake UI;
- use borders, spacing, and background tone before shadows or glass effects;
- keep navigation to one line and no taller than 72px on desktop;
- use no em dash, numbered section label, decorative status dot, scroll cue, testimonial, fake metric, or unrelated logo in visible page content;
- use no automatic carousel or screenshot animation; show a stable representative image and place additional real screenshots in the relevant narrative sections;
- preserve visible focus, reduced-motion behavior, and mobile single-column collapse.

### Home composition

Use a 42/58 asymmetric split hero. The left side contains the product definition, one macOS install CTA, and one CLI/agent route CTA. The right side contains the real Overview screenshot at a readable scale. Move platform and trust details below the hero so the first viewport remains limited to the headline, concise answer, CTAs, and product image.

Below the hero:

1. two unequal audience route panels, with macOS slightly wider because it carries the primary install conversion while both routes retain equal hierarchy;
2. one full-width trust-boundary statement containing explicit approval, no telemetry, and the honest non-sandbox fact;
3. a non-numbered `Scan`, `Review`, `Update` flow separated by space and connectors rather than three generic cards;
4. a compact FAQ and focused footer.

### macOS composition

Use a split hero with installation copy on the left and the real Overview screenshot on the right. Follow it with a compact capability band, then a vertical product narrative that uses the real Overview, Items, and Logs screenshots at varied scales. Do not repeat three identical image-and-copy rows: one state may span the full content width while the other two use offset compositions.

Place the command approval and non-sandbox statement in one high-contrast full-width boundary panel. Group requirements and FAQ content beneath it, followed by one final Homebrew CTA.

### CLI and agents composition

Use an asymmetric split hero with the product definition and agent-guide CTA on the left. The right side is a real HTML command sheet, not terminal chrome or a rasterized code image.

The command sheet and workflow may show only commands documented by the repository:

```text
updatebar guide agent
updatebar template recipe --kind npm --id my-tool --source my-tool > recipe.json
updatebar validate recipe.json --json --explain
updatebar add --from recipe.json --dry-run --json
updatebar add --from recipe.json --json
updatebar approvals my-tool --json
```

Follow with a non-numbered `Author`, `Validate`, `Dry run`, `Import and review` workflow. Pair the JSON/JSONL contract explanation with a prominent warning that agents never approve commands silently, approved commands are not sandboxed, and approved commands run with user privileges. Finish with grouped FAQ content and one repeated `Open the agent guide` CTA.

Generated mockups are directional references only. Their rasterized text and any invented command or product claim must not be copied. The implementation source of truth remains repository documentation and tests.

## Metadata and Structured Data

Each indexable page receives unique:

- `<title>`;
- meta description;
- canonical URL;
- Open Graph title, description, URL, type, site name, and image;
- Twitter summary-large-image card metadata;
- one visible `h1` matching the page intent.

Create one 1200×630 local social preview image at `docs/og-updatebar.png`, composed from the existing app icon, product name, category statement, and a public-safe product capture. Keep essential text inside the central safe area. All three pages may share it because it represents the same product and avoids three nearly identical assets.

Each page embeds a JSON-LD `@graph` containing:

1. a shared `SoftwareApplication` entity with stable `@id` `https://updatebar.royjen.com/#software`, name, URL, application category, operating system, free offer, download URL, code repository, license, and factual feature list;
2. a page-specific `WebPage` entity with its canonical URL, name, description, and `about` reference to the shared software entity.

Omit volatile or unsupported fields such as current version, ratings, review counts, download counts, and organization claims. JSON-LD copy must match visible page copy.

## Static Assets and Routing

Create:

- `docs/macos/index.html`;
- `docs/cli-agents/index.html`;
- `docs/robots.txt`;
- `docs/sitemap.xml`;
- `docs/llms.txt`;
- `docs/404.html`;
- `docs/og-updatebar.png`.

Modify:

- `docs/index.html` for the new home definition, routing, metadata, structured data, and common FAQ;
- `docs/landing.css` only for reusable subpage, route-card, FAQ, warning, and 404 layouts;
- `Scripts/landing-contract-test.sh` to cover the complete three-page contract.

No client-side router, JavaScript, build framework, remote font, analytics script, or new runtime dependency is introduced.

`robots.txt` allows normal crawling and points to `https://updatebar.royjen.com/sitemap.xml`. The sitemap lists only `/`, `/macos/`, and `/cli-agents/`; it omits `lastmod` because the static project has no reliable automated publication date.

The site-specific `llms.txt` provides a concise product definition, the honest execution boundary, the two audience routes, and links to canonical public documentation. It is a supplementary discovery document, not a ranking guarantee.

`404.html` includes `noindex`, a concise not-found message, and links to the three valid routes. After deployment, unknown paths must return the 404 document with HTTP `404`, not the home document with `200`. If Cloudflare Pages continues rewriting unknown paths, deployment configuration must be corrected separately; the implementation must not hide that failure with client-side logic.

## Navigation and Internal Links

The shared header exposes `macOS`, `CLI & agents`, `Docs`, and the context-appropriate primary CTA. The footer links to home, both audience pages, installation, security, documentation, and GitHub.

Internal link flow:

```text
Home
├── macOS page ──> Install / Security / Menu Bar / Releases
└── CLI & agents page ──> CLI / Manifest / Security / Install
```

The home page gives both audience routes equal visual weight. The macOS page prioritizes the cask installation. The CLI/agent page prioritizes `updatebar guide agent` and the safe workflow rather than a generic GitHub visit.

## Accessibility and Responsive Behavior

Preserve the existing landing contract:

- usable at 320px without horizontal overflow;
- one `h1` and a logical heading hierarchy per page;
- semantic `main`, sections, navigation, and footer;
- visible keyboard focus;
- sufficient contrast;
- meaningful link labels;
- no essential information conveyed only by image, color, hover, or motion;
- all motion disabled or simplified under `prefers-reduced-motion`.

Code examples must scroll within their own container on narrow screens and must not force document-level horizontal overflow.

## Verification

### Static contract

Extend `Scripts/landing-contract-test.sh` to verify:

- all required HTML and discovery files exist and are non-empty;
- each indexable page has exactly one `h1`, one `main`, one footer, and unique title, description, and canonical URL;
- required Open Graph and Twitter fields exist;
- each JSON-LD block parses as JSON and contains the expected stable entity IDs and page URL;
- `robots.txt` points to the canonical sitemap;
- the sitemap contains exactly the three canonical page URLs;
- `404.html` contains `noindex`;
- all local links and referenced assets resolve inside `docs/`;
- forbidden claims, placeholders, insecure URLs, scripts, analytics, remote images, and remote fonts are absent;
- existing demo asset limits and reduced-motion guarantees remain intact.

### Browser QA

Test `/`, `/macos/`, `/cli-agents/`, and `/404.html` at desktop, tablet, 390px, and 320px. Verify keyboard navigation, focus visibility, code overflow, reduced motion, route links, CTA targets, local assets, and absence of console or network errors.

### Deployment QA

After publication, verify:

- `/`, `/macos/`, and `/cli-agents/` return `200` with their own canonical document;
- `/robots.txt`, `/sitemap.xml`, and `/llms.txt` return `200` with the intended body and suitable content type;
- an arbitrary unknown path returns `404` and the custom 404 document;
- social preview metadata resolves to a public image;
- sitemap URLs are fetchable and indexable.

### Repository QA

Run the landing contract, `git diff --check`, and `Scripts/quality-gate.sh`. The final diff must remain limited to landing assets, the landing contract, and the approved design/plan documentation.

## Measurement

Do not add client-side analytics. Use search-engine webmaster tooling after deployment to observe:

- index coverage for all three canonical pages;
- disappearance of soft-404 classification;
- impressions, clicks, and click-through rate;
- brand versus non-brand queries;
- macOS-intent versus CLI/agent-intent queries.

Initial success means all three pages are indexed, unknown paths are no longer soft 404s, and the site begins receiving non-brand impressions. Ranking or traffic volume is not guaranteed by this implementation.

## Non-Goals

- No Korean localization or `hreflang` implementation.
- No blog, changelog site, full documentation renderer, comparison pages, pricing, testimonials, or community registry.
- No analytics, tracking pixel, cookie banner, form, account system, or newsletter.
- No native app, CLI, trust-policy, release, Homebrew, Sparkle, or update-feed behavior changes.
- No built-in AI functionality.
- No claims that `llms.txt`, structured data, or metadata guarantee ranking or answer-engine citation.

## Success Criteria

The implementation is complete when:

1. a visitor can identify UpdateBar as a macOS app and CLI for updating developer tools from the first home viewport;
2. macOS and CLI/agent visitors each have a dedicated, indexable page and a clear primary conversion;
3. all security and agent-workflow claims match repository documentation;
4. crawlers can discover exactly the three canonical pages through robots and sitemap files;
5. social crawlers and structured-data parsers receive valid, consistent metadata;
6. unknown deployed paths return a true HTTP `404`;
7. the existing static, accessible, script-free landing experience remains intact;
8. the landing contract and full repository quality gate pass.
