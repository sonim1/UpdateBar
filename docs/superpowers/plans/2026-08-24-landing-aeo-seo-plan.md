# UpdateBar Landing AEO/SEO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a three-page, script-free UpdateBar marketing site with intent-specific AEO/SEO content, taste-led UI, crawler discovery files, valid structured data, and a true custom 404 asset.

**Architecture:** Keep the existing `docs/` static-site architecture and extend it with two nested index pages, shared CSS, shared local imagery, and text discovery files. Expand the existing Bash landing contract before changing production files, then implement the smallest static assets needed to satisfy each group of assertions. No JavaScript, framework, runtime dependency, analytics, or product behavior changes.

**Tech Stack:** Static HTML5, CSS, JSON-LD, XML sitemap, plain text discovery files, Bash contract tests, Ruby standard library for JSON parsing, existing UpdateBar screenshots and app icon.

---

## File Map

- Modify `Scripts/landing-contract-test.sh` - verify all three pages, discovery files, structured data, local links, claims, assets, and responsive hooks.
- Modify `docs/index.html` - redesign the home page, add audience routing, metadata, JSON-LD, trust copy, and FAQ.
- Modify `docs/landing.css` - shared home, subpage, command, trust, FAQ, 404, responsive, and reduced-motion styles.
- Create `docs/macos/index.html` - macOS-specific product and install page.
- Create `docs/cli-agents/index.html` - CLI and external-agent workflow page.
- Create `docs/robots.txt` - crawler allowance and sitemap pointer.
- Create `docs/sitemap.xml` - canonical inventory for exactly three indexable pages.
- Create `docs/llms.txt` - concise public product and execution-boundary guide.
- Create `docs/404.html` - noindex custom not-found page.
- Create `docs/og-updatebar.png` - shared 1200x630 social preview.
- Modify `docs/superpowers/specs/2026-08-24-landing-aeo-seo-design.md` only if implementation reveals a factual contradiction; do not widen scope.

### Task 1: Expand the landing contract first

**Files:**
- Modify: `Scripts/landing-contract-test.sh`
- Test: `Scripts/landing-contract-test.sh`

- [ ] **Step 1: Add the failing three-page inventory and metadata contract.**

Keep the existing asset, forbidden-claim, and reduced-motion checks. Add these declarations and loops after the current path declarations:

```bash
pages=(
  'docs/index.html'
  'docs/macos/index.html'
  'docs/cli-agents/index.html'
)
discovery_files=(
  'docs/robots.txt'
  'docs/sitemap.xml'
  'docs/llms.txt'
  'docs/404.html'
  'docs/og-updatebar.png'
)
canonicals=(
  'https://updatebar.royjen.com/'
  'https://updatebar.royjen.com/macos/'
  'https://updatebar.royjen.com/cli-agents/'
)

for path in "${pages[@]}" "${discovery_files[@]}"; do
  test -s "$path" || { echo "missing landing asset: $path" >&2; exit 1; }
done

for page_path in "${pages[@]}"; do
  test "$(grep -oE '<h1[[:space:]>]' "$page_path" | wc -l | tr -d ' ')" = 1
  test "$(grep -oE '<main[[:space:]>]' "$page_path" | wc -l | tr -d ' ')" = 1
  test "$(grep -oE '<footer[[:space:]>]' "$page_path" | wc -l | tr -d ' ')" = 1
  grep -q '<meta name="description"' "$page_path"
  grep -q '<meta property="og:title"' "$page_path"
  grep -q '<meta property="og:description"' "$page_path"
  grep -q '<meta property="og:image" content="https://updatebar.royjen.com/og-updatebar.png">' "$page_path"
  grep -q '<meta name="twitter:card" content="summary_large_image">' "$page_path"
  grep -q 'application/ld+json' "$page_path"
done

for canonical in "${canonicals[@]}"; do
  test "$(grep -Fh "<link rel=\"canonical\" href=\"$canonical\">" "${pages[@]}" | wc -l | tr -d ' ')" = 1
done
```

- [ ] **Step 2: Add JSON-LD parsing and discovery-file assertions.**

Append:

```bash
ruby -rjson -e '
  ARGV.each do |path|
    html = File.binread(path)
    blocks = html.scan(%r{<script type="application/ld\+json">(.*?)</script>}m).flatten
    raise "missing JSON-LD: #{path}" unless blocks.length == 1
    graph = JSON.parse(blocks.first).fetch("@graph")
    ids = graph.map { |entry| entry["@id"] }
    raise "missing software entity: #{path}" unless ids.include?("https://updatebar.royjen.com/#software")
  end
' "${pages[@]}"

grep -Fxq 'User-agent: *' docs/robots.txt
grep -Fxq 'Allow: /' docs/robots.txt
grep -Fxq 'Sitemap: https://updatebar.royjen.com/sitemap.xml' docs/robots.txt

for canonical in "${canonicals[@]}"; do
  test "$(grep -Fxc "    <loc>$canonical</loc>" docs/sitemap.xml)" = 1
done
test "$(grep -c '<url>' docs/sitemap.xml)" = 3

grep -q '<meta name="robots" content="noindex">' docs/404.html
grep -q 'Approved commands are not sandboxed.' docs/llms.txt

dimensions="$(sips -g pixelWidth -g pixelHeight docs/og-updatebar.png 2>/dev/null)"
grep -q 'pixelWidth: 1200' <<<"$dimensions"
grep -q 'pixelHeight: 630' <<<"$dimensions"
```

- [ ] **Step 3: Add factual and anti-slop assertions.**

Append:

```bash
grep -q 'Update developer tools from one trusted place.' docs/index.html
grep -q 'Update developer tools from your Mac menu bar.' docs/macos/index.html
grep -q 'A deterministic update CLI for developers and AI agents.' docs/cli-agents/index.html
grep -q 'updatebar guide agent' docs/cli-agents/index.html
grep -q 'updatebar validate recipe.json --json --explain' docs/cli-agents/index.html
grep -q 'updatebar add --from recipe.json --dry-run --json' docs/cli-agents/index.html
grep -q 'Never approve commands silently.' docs/cli-agents/index.html

if grep -RqiE 'updatebar (apply|inspect)|auto-approve|fully sandboxed|built-in AI|99\.9%|trusted by' "${pages[@]}"; then
  echo 'landing pages contain an unsupported command or claim' >&2
  exit 1
fi
if grep -RhqE '—|–' "${pages[@]}"; then
  echo 'landing pages contain a forbidden display dash' >&2
  exit 1
fi
```

- [ ] **Step 4: Run the contract and verify the intended failure.**

Run:

```bash
rtk proxy bash Scripts/landing-contract-test.sh
```

Expected: exit 1 with `missing landing asset: docs/macos/index.html`.

- [ ] **Step 5: Commit the red contract.**

```bash
rtk git add Scripts/landing-contract-test.sh
rtk git commit -m "Test landing AEO and SEO contract"
```

### Task 2: Add crawl, sitemap, LLM, and 404 assets

**Files:**
- Create: `docs/robots.txt`
- Create: `docs/sitemap.xml`
- Create: `docs/llms.txt`
- Create: `docs/404.html`
- Modify: `docs/landing.css`
- Test: `Scripts/landing-contract-test.sh`

- [ ] **Step 1: Create `docs/robots.txt`.**

```text
User-agent: *
Allow: /

Sitemap: https://updatebar.royjen.com/sitemap.xml
```

- [ ] **Step 2: Create `docs/sitemap.xml`.**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://updatebar.royjen.com/</loc>
  </url>
  <url>
    <loc>https://updatebar.royjen.com/macos/</loc>
  </url>
  <url>
    <loc>https://updatebar.royjen.com/cli-agents/</loc>
  </url>
</urlset>
```

- [ ] **Step 3: Create the public `docs/llms.txt`.**

```text
# UpdateBar

UpdateBar is a macOS app and CLI for tracking local developer tools, comparing installed and latest versions, and running only update commands the user explicitly approves.

## Product routes

- macOS app: https://updatebar.royjen.com/macos/
- CLI and external agents: https://updatebar.royjen.com/cli-agents/
- source and documentation: https://github.com/sonim1/UpdateBar

## Trust boundary

Imported and agent-authored recipes start untrusted. UpdateBar validates recipe data and requires explicit approval of exact command fingerprints before execution. Approved commands are not sandboxed. They run with the user's privileges using an allowlisted environment plus time and output limits.

UpdateBar has no built-in AI recipe generation and does not approve commands automatically. External agents may author recipe JSON, but they must never approve commands silently.

## Canonical references

- Installation: https://github.com/sonim1/UpdateBar/blob/main/docs/install.md
- CLI reference: https://github.com/sonim1/UpdateBar/blob/main/docs/cli.md
- Manifest format: https://github.com/sonim1/UpdateBar/blob/main/docs/manifest.md
- Security: https://github.com/sonim1/UpdateBar/blob/main/docs/security.md
```

- [ ] **Step 4: Create a noindex `docs/404.html`.**

Use the shared stylesheet and include a minimal header, one `main`, one `h1`, links to `/`, `/macos/`, and `/cli-agents/`, plus one footer. Required head:

```html
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Page not found | UpdateBar</title>
<link rel="icon" href="/favicon.png">
<link rel="stylesheet" href="/landing.css">
```

Required main copy:

```html
<main class="not-found shell">
  <p class="eyebrow">Page not found</p>
  <h1>This page does not exist.</h1>
  <p>Choose the UpdateBar experience that matches how you work.</p>
  <div class="hero-actions">
    <a class="button button--primary" href="/">Go home</a>
    <a class="button button--secondary" href="/cli-agents/">CLI &amp; agents</a>
  </div>
</main>
```

- [ ] **Step 5: Add only the 404 styles needed now.**

```css
.not-found {
  display: grid;
  min-height: calc(100dvh - 160px);
  align-content: center;
  justify-items: start;
  padding-block: 80px;
}

.not-found h1 {
  max-width: 760px;
}

.not-found > p:not(.eyebrow) {
  max-width: 560px;
  color: var(--text-soft);
}
```

- [ ] **Step 6: Run the contract and verify it advances to the next missing asset.**

Run `rtk proxy bash Scripts/landing-contract-test.sh`.

Expected: exit 1 for `docs/macos/index.html`, `docs/cli-agents/index.html`, or `docs/og-updatebar.png`; discovery content itself no longer fails.

- [ ] **Step 7: Commit discovery assets.**

```bash
rtk git add docs/robots.txt docs/sitemap.xml docs/llms.txt docs/404.html docs/landing.css
rtk git commit -m "Add landing discovery and 404 assets"
```

### Task 3: Create the shared social preview

**Files:**
- Create: `docs/og-updatebar.png`
- Test: `Scripts/landing-contract-test.sh`

- [ ] **Step 1: Generate a 1200x630 social preview using the approved visual direction.**

Use the built-in image generation tool with `docs/AppIcon-256.png` and `docs/demo/overview.webp` as references. Prompt for a dark graphite social card with the real icon, a recognizable product screenshot crop, electric-blue accent, and exact visible text `UpdateBar` and `Update developer tools from one trusted place.` No other copy, invented UI, glow, metric, logo, or watermark.

- [ ] **Step 2: Copy the selected generated PNG to `docs/og-updatebar.png` without overwriting any unrelated asset.**

- [ ] **Step 3: Verify dimensions and inspect the final image.**

Run:

```bash
rtk proxy sips -g pixelWidth -g pixelHeight docs/og-updatebar.png
```

Expected: `pixelWidth: 1200` and `pixelHeight: 630`.

- [ ] **Step 4: Commit the social asset.**

```bash
rtk git add docs/og-updatebar.png
rtk git commit -m "Add UpdateBar social preview"
```

### Task 4: Redesign and optimize the home page

**Files:**
- Modify: `docs/index.html`
- Modify: `docs/landing.css`
- Test: `Scripts/landing-contract-test.sh`

- [ ] **Step 1: Replace home metadata with intent-specific metadata and one JSON-LD graph.**

Use:

```html
<meta name="description" content="UpdateBar is a macOS app and CLI that tracks local developer tools and runs only update commands you explicitly approve.">
<title>UpdateBar | macOS App and CLI for Updating Developer Tools</title>
<link rel="canonical" href="https://updatebar.royjen.com/">
<meta property="og:type" content="website">
<meta property="og:site_name" content="UpdateBar">
<meta property="og:title" content="UpdateBar | Update developer tools from one trusted place">
<meta property="og:description" content="Track local tools, compare versions, and run only the update commands you approve.">
<meta property="og:url" content="https://updatebar.royjen.com/">
<meta property="og:image" content="https://updatebar.royjen.com/og-updatebar.png">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="UpdateBar | Update developer tools from one trusted place">
<meta name="twitter:description" content="Track local tools, compare versions, and run only the update commands you approve.">
<meta name="twitter:image" content="https://updatebar.royjen.com/og-updatebar.png">
```

The JSON-LD graph contains one `SoftwareApplication` at `https://updatebar.royjen.com/#software` and one `WebPage` at `https://updatebar.royjen.com/#webpage`. Use `DeveloperApplication`, `macOS 13 and later`, a zero-price USD offer, the latest-release URL, repository URL, MIT license URL, and only visible factual features.

- [ ] **Step 2: Replace the centered animated hero with the approved static split hero.**

Use the exact visible copy:

```html
<h1 id="hero-title">Update developer tools from one trusted place.</h1>
<p class="hero-lede">UpdateBar is a macOS app and CLI that tracks local tools, compares versions, and runs only update commands you explicitly approve.</p>
```

Primary CTA: `Install for macOS` to `#install`. Secondary CTA: `CLI & agents` to `/cli-agents/`. Use `demo/overview.webp` as the only hero screenshot and remove the auto-cycle checkbox, labels, and animation dependency.

- [ ] **Step 3: Add two asymmetric audience routes.**

macOS route links to `/macos/` and describes the native app, Dashboard, bundled CLI, and Homebrew install. CLI route links to `/cli-agents/` and describes deterministic JSON/JSONL output, recipe validation, and explicit command approval. Do not display unsupported sample commands on the home page.

- [ ] **Step 4: Replace the four-card feature grid with one trust boundary and one unboxed workflow.**

Trust copy must include:

```text
Explicit approval. No telemetry.
UpdateBar runs a command only while its exact fingerprint is approved. Approved commands are not sandboxed and still run with your user privileges.
```

Workflow labels are exactly `Scan`, `Review`, `Update`; no numeric labels.

- [ ] **Step 5: Add a short common FAQ with visible answers.**

Questions cover what UpdateBar updates, automatic command execution, sandboxing, telemetry, and terminal use. Use semantic `details` and `summary` elements so answers remain available without JavaScript.

- [ ] **Step 6: Implement shared home styles.**

Add a 42/58 split hero, static product frame, 58/42 audience grid, full-width trust panel, unboxed three-part workflow, and details-based FAQ. Keep existing tokens and mobile breakpoints. At `< 768px`, every multi-column layout becomes one column and code or command rows scroll internally.

- [ ] **Step 7: Run the contract.**

Expected: home-specific assertions pass; overall test still fails only because the two subpages do not exist.

- [ ] **Step 8: Commit the home page.**

```bash
rtk git add docs/index.html docs/landing.css
rtk git commit -m "Redesign landing home for search intent"
```

### Task 5: Build the macOS page

**Files:**
- Create: `docs/macos/index.html`
- Modify: `docs/landing.css`
- Test: `Scripts/landing-contract-test.sh`

- [ ] **Step 1: Create unique metadata and JSON-LD.**

Title: `UpdateBar for macOS | Update Developer Tools from the Menu Bar`. Canonical: `https://updatebar.royjen.com/macos/`. The page-specific `WebPage` ID is `https://updatebar.royjen.com/macos/#webpage`; reuse the shared software ID.

- [ ] **Step 2: Build the split install hero.**

Use exact hero copy:

```html
<h1 id="hero-title">Update developer tools from your Mac menu bar.</h1>
<p class="hero-lede">See what is outdated, review the exact command access, and update approved tools from one native macOS app.</p>
```

Primary CTA links to `#install`; secondary link points to `/cli-agents/`. The right side uses `../demo/overview.webp` with explicit dimensions.

- [ ] **Step 3: Build the varied product narrative.**

Use `overview.webp`, `approval.webp`, and `history.webp` in three distinct compositions. Visible labels are `Scan`, `Review`, and `Update`, without numeric prefixes. Copy must match current behavior and avoid saying scan mutates state or commands are sandboxed.

- [ ] **Step 4: Add the honest boundary, requirements, FAQ, and final install CTA.**

Requirements include macOS 13+, current Apple Silicon app assets, signed and notarized releases, bundled CLI, and no telemetry. Primary command remains:

```text
brew install --cask sonim1/tap/updatebar-app
```

- [ ] **Step 5: Add only reusable subpage styles and mobile collapse rules.**

- [ ] **Step 6: Run the contract.**

Expected: macOS assertions pass; failure remains only for the missing CLI/agent page.

- [ ] **Step 7: Commit the macOS page.**

```bash
rtk git add docs/macos/index.html docs/landing.css
rtk git commit -m "Add UpdateBar macOS landing page"
```

### Task 6: Build the CLI and agents page

**Files:**
- Create: `docs/cli-agents/index.html`
- Modify: `docs/landing.css`
- Test: `Scripts/landing-contract-test.sh`

- [ ] **Step 1: Create unique metadata and JSON-LD.**

Title: `UpdateBar CLI for Developers and AI Agents`. Canonical: `https://updatebar.royjen.com/cli-agents/`. The page-specific `WebPage` ID is `https://updatebar.royjen.com/cli-agents/#webpage`; reuse the shared software ID.

- [ ] **Step 2: Build the technical split hero with real HTML commands.**

Use exact hero copy:

```html
<h1 id="hero-title">A deterministic update CLI for developers and AI agents.</h1>
<p class="hero-lede">External agents may author recipe JSON. UpdateBar validates it, stores it untrusted, and gates exact command execution behind user approval.</p>
```

Primary CTA is `Open the agent guide` and points to the repository agent workflow. The command sheet uses the six approved commands listed in the design spec. Do not use terminal window chrome or copy buttons that require JavaScript.

- [ ] **Step 3: Add the non-numbered safe workflow.**

Labels: `Author`, `Validate`, `Dry run`, `Import and review`. Every command matches `llms.txt` and current CLI docs exactly.

- [ ] **Step 4: Add contract explanation and high-contrast warning.**

Visible warning:

```text
Never approve commands silently.
Approved commands are not sandboxed. They run with your user privileges after explicit approval.
```

Explain JSON for snapshots and JSONL for streamed command events without implying UpdateBar contains an AI model.

- [ ] **Step 5: Add visible FAQ and final guide CTA.**

FAQ covers agent safety, auto approval, recipe formats, read-only status, secret handling, and supported platforms.

- [ ] **Step 6: Run the landing contract and verify green.**

Run `rtk proxy bash Scripts/landing-contract-test.sh`.

Expected: `landing contract passed`.

- [ ] **Step 7: Commit the CLI and agents page.**

```bash
rtk git add docs/cli-agents/index.html docs/landing.css
rtk git commit -m "Add CLI and agents landing page"
```

### Task 7: Browser, link, structured-data, and responsive QA

**Files:**
- Modify if defects are found: `docs/index.html`
- Modify if defects are found: `docs/macos/index.html`
- Modify if defects are found: `docs/cli-agents/index.html`
- Modify if defects are found: `docs/404.html`
- Modify if defects are found: `docs/landing.css`
- Test: `Scripts/landing-contract-test.sh`

- [ ] **Step 1: Start a local static server from `docs/`.**

```bash
rtk proxy python3 -m http.server 4173 --directory docs
```

Expected: server listens on `http://127.0.0.1:4173`.

- [ ] **Step 2: Inspect `/`, `/macos/`, `/cli-agents/`, and `/404.html` at 1440px, 768px, 390px, and 320px.**

Verify one-line navigation, hero CTA visibility, screenshot legibility, no document-level overflow, exact command wrapping, visible focus, semantic FAQ behavior, and static rendering under reduced motion.

- [ ] **Step 3: Check local response and asset behavior.**

```bash
rtk proxy curl -fsS http://127.0.0.1:4173/ >/dev/null
rtk proxy curl -fsS http://127.0.0.1:4173/macos/ >/dev/null
rtk proxy curl -fsS http://127.0.0.1:4173/cli-agents/ >/dev/null
rtk proxy curl -fsS http://127.0.0.1:4173/robots.txt
rtk proxy curl -fsS http://127.0.0.1:4173/sitemap.xml
rtk proxy curl -fsS http://127.0.0.1:4173/llms.txt
```

Expected: all commands succeed and return the intended file contents.

- [ ] **Step 4: Fix only observed defects and rerun the contract after each fix.**

- [ ] **Step 5: Commit QA fixes if any.**

```bash
rtk git add docs Scripts/landing-contract-test.sh
rtk git commit -m "Polish landing responsive behavior"
```

Skip the commit when no tracked file changed.

### Task 8: Final repository verification

**Files:**
- Verify: all task files

- [ ] **Step 1: Run the focused landing contract.**

```bash
rtk proxy bash Scripts/landing-contract-test.sh
```

Expected: `landing contract passed`.

- [ ] **Step 2: Run formatting and diff checks.**

```bash
rtk git diff --check origin/main...HEAD
rtk git status --short
rtk git diff --stat origin/main...HEAD
```

Expected: no whitespace errors; only approved landing, test, spec, and plan files appear.

- [ ] **Step 3: Run the repository completion gate.**

```bash
rtk Scripts/quality-gate.sh
```

Expected: exit 0 with `quality gate complete`. Record the Swift and TUI test counts and any pre-existing compiler warnings.

- [ ] **Step 4: Verify deployment behavior after publication.**

```bash
rtk proxy curl -sS -o /dev/null -w '%{http_code}\n' https://updatebar.royjen.com/
rtk proxy curl -sS -o /dev/null -w '%{http_code}\n' https://updatebar.royjen.com/macos/
rtk proxy curl -sS -o /dev/null -w '%{http_code}\n' https://updatebar.royjen.com/cli-agents/
rtk proxy curl -sS -o /dev/null -w '%{http_code}\n' https://updatebar.royjen.com/not-a-real-page
```

Expected after deploy: `200`, `200`, `200`, `404`. If the last status remains `200`, report the Cloudflare Pages rewrite as an external deployment blocker; do not claim soft-404 resolution from local files alone.
