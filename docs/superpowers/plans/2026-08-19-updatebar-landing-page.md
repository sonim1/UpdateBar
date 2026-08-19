# UpdateBar Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a responsive static UpdateBar landing page that communicates trusted local-tool updates within five seconds and matches the structure and quality bar of the SwitchTab landing page.

**Architecture:** Add a semantic, dependency-free page in `docs/` with one focused stylesheet and local icon/demo assets. A shell contract test locks product claims, page structure, privacy constraints, asset budgets, animation timing, and reduced-motion behavior; existing Swift code remains untouched.

**Tech Stack:** HTML5, CSS, Bash contract tests, local PNG/WebP assets, macOS native app captures, Orca browser QA.

---

## File map

- Create `docs/index.html` — semantic landing content and local demo layers.
- Create `docs/landing.css` — tokens, layout, animation, responsive states, and accessibility.
- Create `docs/AppIcon-256.png` — web-sized product identity asset.
- Create `docs/favicon.png` — browser favicon derived from the product icon.
- Create `docs/demo/overview.webp` — representative Dashboard Overview poster.
- Create `docs/demo/approval.webp` — native command-approval state.
- Create `docs/demo/history.webp` — native completed-update/history state.
- Create `Scripts/landing-contract-test.sh` — static landing contract.
- Modify `README.md` — add the landing source to the documentation list.

Do not modify Swift sources, release workflows, Homebrew packaging, Sparkle, or existing product documentation claims.

### Task 1: Lock the landing contract

**Files:**
- Create: `Scripts/landing-contract-test.sh`
- Test: `Scripts/landing-contract-test.sh`

- [ ] **Step 1: Write the failing contract test**

Create `Scripts/landing-contract-test.sh` with executable mode and this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

page='docs/index.html'
style='docs/landing.css'
icon='docs/AppIcon-256.png'
favicon='docs/favicon.png'
demo_dir='docs/demo'
demo_assets=(overview.webp approval.webp history.webp)

for path in "$page" "$style" "$icon" "$favicon"; do
  test -s "$path" || { echo "missing landing asset: $path" >&2; exit 1; }
done

test "$(grep -oE '<h1[[:space:]>]' "$page" | wc -l | tr -d ' ')" = 1
grep -qE '<main[[:space:]>]' "$page"
grep -qE '<footer[[:space:]>]' "$page"
grep -q 'id="install"' "$page"
grep -q 'id="how-it-works"' "$page"
grep -q 'class="demo-reel"' "$page"
grep -q 'Every tool.' "$page"
grep -q 'One update away.' "$page"
grep -q 'brew install --cask sonim1/tap/updatebar-app' "$page"
grep -q 'macOS 13+' "$page"
grep -q 'Signed &amp; notarized' "$page"
grep -q 'No telemetry' "$page"

if grep -qiE '<script[[:space:]>]|<video[[:space:]>]|<canvas[[:space:]>]|tracker|analytics|http://' "$page" "$style"; then
  echo 'landing page must stay free of scripts, video, canvas, trackers, analytics, and insecure URLs' >&2
  exit 1
fi
if grep -qiE 'src="https?://' "$page"; then
  echo 'landing page images must be served locally' >&2
  exit 1
fi
if grep -qiE 'fully sandboxed|safe to run arbitrary|auto-approve|built-in AI' "$page"; then
  echo 'landing page contains a forbidden product claim' >&2
  exit 1
fi
if grep -qiE 'TODO|TBD|placeholder|lorem ipsum' "$page" "$style"; then
  echo 'landing page contains unfinished copy' >&2
  exit 1
fi
macos_user_root='/'"Users/"
if grep -R -qE "${macos_user_root}|file:///" docs; then
  echo 'public documentation contains a local filesystem identifier' >&2
  exit 1
fi

total_bytes=0
for asset in "${demo_assets[@]}"; do
  asset_path="$demo_dir/$asset"
  test -s "$asset_path" || { echo "missing landing demo asset: $asset_path" >&2; exit 1; }
  asset_bytes="$(wc -c < "$asset_path" | tr -d ' ')"
  total_bytes=$((total_bytes + asset_bytes))
done
test "$(find "$demo_dir" -maxdepth 1 -type f -name '*.webp' | wc -l | tr -d ' ')" = 3
poster_bytes="$(wc -c < "$demo_dir/overview.webp" | tr -d ' ')"
test "$poster_bytes" -le 358400 || {
  echo "landing demo poster exceeds 350 KiB: $poster_bytes bytes" >&2
  exit 1
}
test "$total_bytes" -le 1572864 || {
  echo "landing demo assets exceed 1.5 MiB: $total_bytes bytes" >&2
  exit 1
}

test "$(grep -oE 'src="demo/(overview|approval|history)\.webp"' "$page" | sort -u | wc -l | tr -d ' ')" = 3
grep -q -- '--demo-cycle: 9s' "$style"
grep -q '@keyframes demo-overview' "$style"
grep -q '@keyframes demo-approval' "$style"
grep -q '@keyframes demo-history' "$style"
grep -q 'prefers-reduced-motion: reduce' "$style"
grep -q '.demo-frame--poster' "$page"
grep -q '.demo-motion-toggle:checked ~ .demo-window' "$style"
grep -q 'animation-play-state: paused' "$style"

echo 'landing contract passed'
```

- [ ] **Step 2: Run the contract and confirm the red state**

Run:

```bash
rtk proxy chmod +x Scripts/landing-contract-test.sh
rtk proxy bash Scripts/landing-contract-test.sh
```

Expected: exit 1 with `missing landing asset: docs/index.html`.

- [ ] **Step 3: Commit the contract**

```bash
rtk git add Scripts/landing-contract-test.sh
rtk git commit -m "test: define landing page contract"
```

### Task 2: Add web icon assets

**Files:**
- Create: `docs/AppIcon-256.png`
- Create: `docs/favicon.png`
- Test: `Scripts/landing-contract-test.sh`

- [ ] **Step 1: Generate deterministic icon derivatives from the existing app icon**

Run:

```bash
rtk proxy mkdir -p docs
rtk proxy cp Assets/AppIcon/UpdateBar.png docs/AppIcon-256.png
rtk proxy sips -Z 256 docs/AppIcon-256.png
rtk proxy cp Assets/AppIcon/UpdateBar.png docs/favicon.png
rtk proxy sips -Z 64 docs/favicon.png
```

Expected: `docs/AppIcon-256.png` is 256×256 and `docs/favicon.png` is 64×64.

- [ ] **Step 2: Verify dimensions and the next expected contract failure**

Run:

```bash
rtk proxy sips -g pixelWidth -g pixelHeight docs/AppIcon-256.png docs/favicon.png
rtk proxy bash Scripts/landing-contract-test.sh
```

Expected: dimensions are 256×256 and 64×64; contract still fails because `docs/index.html` is missing.

- [ ] **Step 3: Commit icon assets**

```bash
rtk git add docs/AppIcon-256.png docs/favicon.png
rtk git commit -m "feat: add landing icon assets"
```

### Task 3: Capture privacy-safe real product imagery

**Files:**
- Create: `docs/demo/overview.webp`
- Create: `docs/demo/approval.webp`
- Create: `docs/demo/history.webp`
- Local only: `.build/landing-demo-home/`
- Local only: `.build/landing-demo-captures/`
- Test: `Scripts/landing-contract-test.sh`

- [ ] **Step 1: Build the app and create isolated capture directories**

Run:

```bash
rtk proxy mkdir -p .build/landing-demo-home .build/landing-demo-captures docs/demo
rtk proxy swift build --product updatebar
rtk proxy bash Scripts/package-app.sh
```

Expected: `dist/UpdateBar.app/Contents/MacOS/UpdateBar` exists. Do not use the user's default `~/.updatebar` directory.

- [ ] **Step 2: Seed public-safe manifest and state files**

Create `.build/landing-demo-home/manifest.json` with this exact public-safe fixture. Every command is harmless and deterministic, and all approvals remain empty:

```json
{
  "schema_version": 1,
  "items": [
    {
      "id": "atlas-cli",
      "name": "Atlas CLI",
      "category": "Developer Tools",
      "path": null,
      "source": { "kind": "github_release", "ref": "example/atlas-cli", "branch": null },
      "version_scheme": "semver",
      "check": { "cmd": "/usr/bin/printf '1.8.0\\n'" },
      "latest": { "strategy": "github_release", "cmd": null, "pattern": null },
      "version_parse": { "regex": "([0-9]+\\.[0-9]+\\.[0-9]+)" },
      "update": { "cmd": "/usr/bin/printf 'updated Atlas CLI\\n'", "requires_write": false, "cwd": null },
      "pin": null,
      "enabled": true,
      "trust": { "level": "untrusted", "approved_commands": {} }
    },
    {
      "id": "format-kit",
      "name": "FormatKit",
      "category": "Developer Tools",
      "path": null,
      "source": { "kind": "brew", "ref": "format-kit", "branch": null },
      "version_scheme": "semver",
      "check": { "cmd": "/usr/bin/printf '0.14.2\\n'" },
      "latest": { "strategy": "brew", "cmd": null, "pattern": null },
      "version_parse": { "regex": "([0-9]+\\.[0-9]+\\.[0-9]+)" },
      "update": { "cmd": "/usr/bin/printf 'updated FormatKit\\n'", "requires_write": false, "cwd": null },
      "pin": null,
      "enabled": true,
      "trust": { "level": "untrusted", "approved_commands": {} }
    },
    {
      "id": "node-runtime",
      "name": "Node Runtime",
      "category": "Runtimes",
      "path": null,
      "source": { "kind": "npm", "ref": "node", "branch": null },
      "version_scheme": "semver",
      "check": { "cmd": "/usr/bin/printf '24.6.0\\n'" },
      "latest": { "strategy": "npm_registry", "cmd": null, "pattern": null },
      "version_parse": { "regex": "([0-9]+\\.[0-9]+\\.[0-9]+)" },
      "update": { "cmd": "/usr/bin/printf 'updated Node Runtime\\n'", "requires_write": false, "cwd": null },
      "pin": null,
      "enabled": true,
      "trust": { "level": "untrusted", "approved_commands": {} }
    }
  ],
  "provenance": {
    "created_by": "updatebar-landing-fixture",
    "created_at": "2026-08-19T12:00:00Z",
    "updated_at": "2026-08-19T12:00:00Z"
  }
}
```

Create `.build/landing-demo-home/state.json` with this exact shape:

```json
{
  "schema_version": 1,
  "generated_at": "2026-08-19T12:00:00Z",
  "items": {
    "atlas-cli": {
      "current": "1.8.0",
      "latest": "1.9.0",
      "status": "outdated",
      "last_checked": "2026-08-19T12:00:00Z",
      "error": null,
      "backoff_until": null
    },
    "format-kit": {
      "current": "0.14.2",
      "latest": "0.15.0",
      "status": "outdated",
      "last_checked": "2026-08-19T12:00:00Z",
      "error": null,
      "backoff_until": null
    },
    "node-runtime": {
      "current": "24.6.0",
      "latest": "24.6.0",
      "status": "ok",
      "last_checked": "2026-08-19T12:00:00Z",
      "error": null,
      "backoff_until": null
    }
  }
}
```

Create `.build/landing-demo-home/history.jsonl` with these exact fictional events:

```jsonl
{"at":"2026-07-29T12:00:00Z","event":"update_finished","from":"1.6.0","id":"atlas-cli","outcome":"success","schema_version":1,"to":"1.7.0"}
{"at":"2026-08-02T12:00:00Z","event":"update_finished","from":"0.13.0","id":"format-kit","outcome":"success","schema_version":1,"to":"0.14.0"}
{"at":"2026-08-06T12:00:00Z","event":"update_finished","from":"23.9.0","id":"node-runtime","outcome":"success","schema_version":1,"to":"24.0.0"}
{"at":"2026-08-10T12:00:00Z","event":"update_finished","from":"1.7.0","id":"atlas-cli","outcome":"success","schema_version":1,"to":"1.8.0"}
{"at":"2026-08-14T12:00:00Z","event":"update_finished","from":"0.14.0","id":"format-kit","outcome":"success","schema_version":1,"to":"0.14.2"}
{"at":"2026-08-18T12:00:00Z","event":"update_finished","from":"1.8.0","id":"atlas-cli","outcome":"success","schema_version":1,"to":"1.9.0"}
```

- [ ] **Step 3: Validate the isolated fixture through the real CLI**

Run:

```bash
UPDATEBAR_HOME="$PWD/.build/landing-demo-home" rtk proxy .build/debug/updatebar validate .build/landing-demo-home/manifest.json --json
UPDATEBAR_HOME="$PWD/.build/landing-demo-home" rtk proxy .build/debug/updatebar status --json
```

Expected: manifest validation succeeds; status reports two outdated items and one current item without touching the user's registry.

- [ ] **Step 4: Launch the packaged app against the isolated home**

Run the app executable with `UPDATEBAR_HOME` set to `.build/landing-demo-home`. Use the `computer-use` skill to open Dashboard Overview, the command-approval confirmation, and Logs. Before each capture, inspect visible text and confirm no username, home path, real tool inventory, notification, account, or personal file appears.

Capture only the active UpdateBar window. For each command, click the UpdateBar window once when macOS presents the window-selection cursor:

```bash
rtk proxy screencapture -x -i -W .build/landing-demo-captures/overview.png
rtk proxy screencapture -x -i -W .build/landing-demo-captures/approval.png
rtk proxy screencapture -x -i -W .build/landing-demo-captures/history.png
```

Never capture the full desktop. Cancel and repeat immediately if the selected window is not UpdateBar.

- [ ] **Step 5: Inspect and convert the captures**

Use `view_image` on all three PNGs. Reject any capture with personal data, distorted UI, inconsistent scale, or unrelated desktop chrome. Then convert at one quality level:

```bash
rtk proxy cwebp -quiet -q 80 .build/landing-demo-captures/overview.png -o docs/demo/overview.webp
rtk proxy cwebp -quiet -q 80 .build/landing-demo-captures/approval.png -o docs/demo/approval.webp
rtk proxy cwebp -quiet -q 80 .build/landing-demo-captures/history.png -o docs/demo/history.webp
rtk proxy wc -c docs/demo/*.webp
```

Expected: `overview.webp` ≤ 358400 bytes and all three assets together ≤ 1572864 bytes. If the limit is exceeded, reconvert all three at `-q 72`; do not vary quality per file.

- [ ] **Step 6: Commit only public WebP assets**

```bash
rtk git status --short
rtk git add docs/demo
rtk git commit -m "feat: add landing product captures"
```

Expected: `.build/landing-demo-home/` and `.build/landing-demo-captures/` do not appear in the commit.

### Task 4: Build the semantic landing page

**Files:**
- Create: `docs/index.html`
- Test: `Scripts/landing-contract-test.sh`

- [ ] **Step 1: Add the complete page structure and approved copy**

Create `docs/index.html` with these required semantic blocks and exact product copy:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="description" content="UpdateBar tracks local tools and runs only update commands you explicitly approve.">
    <title>UpdateBar — Every tool. One update away.</title>
    <link rel="icon" href="favicon.png">
    <link rel="stylesheet" href="landing.css">
  </head>
  <body>
    <div class="page-glow page-glow--top" aria-hidden="true"></div>
    <div class="page-glow page-glow--bottom" aria-hidden="true"></div>

    <header class="site-header shell">
      <a class="brand" href="index.html" aria-label="UpdateBar home">
        <img src="AppIcon-256.png" alt="">
        <span>UpdateBar</span>
      </a>
      <nav class="header-nav" aria-label="Primary navigation">
        <a class="nav-link" href="https://github.com/sonim1/UpdateBar">GitHub</a>
        <a class="button button--small button--light" href="#install">Install <span aria-hidden="true">↓</span></a>
      </nav>
    </header>

    <main>
      <section class="hero shell" aria-labelledby="hero-title">
        <div class="hero-copy">
          <p class="eyebrow"><span class="eyebrow-dot" aria-hidden="true"></span> Trusted updates, one place.</p>
          <h1 id="hero-title">Every tool.<br><em>One update away.</em></h1>
          <p class="hero-lede">Track local tools, review what changed, and run only the update commands you approve.</p>
          <div class="hero-actions">
            <a class="button button--primary" href="#install">Install UpdateBar <span aria-hidden="true">→</span></a>
            <a class="text-link" href="#how-it-works">See how it works <span aria-hidden="true">↓</span></a>
          </div>
          <ul class="trust-row" aria-label="Product highlights">
            <li>macOS 13+</li>
            <li>Native Swift</li>
            <li>Signed &amp; notarized</li>
            <li>No telemetry</li>
          </ul>
        </div>

        <figure class="demo-reel" aria-labelledby="demo-caption">
          <input class="demo-motion-toggle" id="demo-motion-toggle" type="checkbox">
          <label class="demo-motion-control" for="demo-motion-toggle">
            <span class="demo-motion-control__pause" aria-hidden="true">Ⅱ&nbsp; Pause</span>
            <span class="demo-motion-control__play" aria-hidden="true">▶&nbsp; Play</span>
            <span class="demo-motion-control__name">Pause or play demo animation</span>
          </label>
          <div class="demo-window" aria-hidden="true">
            <img class="demo-frame demo-frame--overview demo-frame--poster" src="demo/overview.webp" alt="" width="1200" height="760" fetchpriority="high" decoding="async">
            <img class="demo-frame demo-frame--approval" src="demo/approval.webp" alt="" width="1200" height="760" loading="lazy" decoding="async">
            <img class="demo-frame demo-frame--history" src="demo/history.webp" alt="" width="1200" height="760" loading="lazy" decoding="async">
            <span class="demo-label demo-label--overview">See what needs attention</span>
            <span class="demo-label demo-label--approval">Approve exact commands</span>
            <span class="demo-label demo-label--history">Keep a clear update history</span>
          </div>
          <figcaption id="demo-caption">See updates, review command access, and keep the result visible from one native macOS app.</figcaption>
        </figure>
      </section>

      <section class="source-cta shell" id="install" aria-labelledby="install-title">
        <div class="source-cta__inner">
          <div>
            <p class="eyebrow">Get it running</p>
            <h2 id="install-title">One command.<br><em>Everything current.</em></h2>
            <p>Install the signed macOS app and bundled CLI with Homebrew. No account or telemetry.</p>
          </div>
          <div class="install-options">
            <div class="install-option">
              <span class="install-option__label">Install with Homebrew</span>
              <div class="source-command" aria-label="Homebrew install command">
                <span class="source-command__prompt" aria-hidden="true">$</span>
                <code>brew install --cask sonim1/tap/updatebar-app</code>
              </div>
            </div>
            <div class="install-links">
              <a href="https://github.com/sonim1/UpdateBar/releases/latest">Latest release ↗</a>
              <a href="https://github.com/sonim1/homebrew-tap/blob/main/Formula/updatebar.rb">CLI-only formula ↗</a>
            </div>
          </div>
        </div>
      </section>

      <section class="how-it-works shell" id="how-it-works" aria-labelledby="how-title">
        <div class="section-heading">
          <p class="eyebrow">The flow</p>
          <h2 id="how-title">From scattered tools<br><em>to one clear queue.</em></h2>
        </div>
        <div class="steps" aria-label="How UpdateBar works">
          <article class="step"><span class="step-number">01</span><h3>Scan</h3><p>Discover supported local tools without changing your UpdateBar state.</p></article>
          <span class="step-connector" aria-hidden="true">→</span>
          <article class="step"><span class="step-number">02</span><h3>Review</h3><p>Compare versions and approve exact command fields only when required.</p></article>
          <span class="step-connector" aria-hidden="true">→</span>
          <article class="step"><span class="step-number">03</span><h3>Update</h3><p>Update one item or every approved outdated tool from the app or CLI.</p></article>
        </div>
      </section>

      <section class="features shell" aria-labelledby="features-title">
        <div class="section-heading section-heading--split">
          <div><p class="eyebrow">Built around trust</p><h2 id="features-title">One update layer.<br><em>No hidden decisions.</em></h2></div>
          <p class="section-intro">UpdateBar stays deterministic: it shows state, gates commands, and records outcomes.</p>
        </div>
        <div class="feature-grid">
          <article class="feature"><p class="feature-kicker">One registry</p><h3>Track different tool ecosystems together.</h3><p>Homebrew, npm, GitHub releases, files, and custom recipes share one clear status model.</p></article>
          <article class="feature"><p class="feature-kicker">Explicit trust</p><h3>Commands run only after exact approval.</h3><p>Imported and discovered command fields stay gated, and edits invalidate their fingerprints.</p></article>
          <article class="feature"><p class="feature-kicker">Native where it matters</p><h3>Keep daily updates in the menu bar.</h3><p>Check status, manage items, review approvals, and watch progress in a native macOS surface.</p></article>
          <article class="feature"><p class="feature-kicker">CLI when you need it</p><h3>Script the same deterministic core.</h3><p>Stable JSON and JSONL contracts work from terminals, scripts, and external agents.</p></article>
        </div>
      </section>
    </main>

    <footer class="site-footer shell">
      <a class="brand brand--footer" href="index.html"><img src="AppIcon-256.png" alt=""><span>UpdateBar</span></a>
      <p>A trusted update layer for the tools already on your machine.</p>
      <nav aria-label="Footer navigation"><a href="https://github.com/sonim1/UpdateBar">GitHub</a><a href="https://github.com/sonim1/UpdateBar/blob/main/docs/install.md">Install</a><a href="https://github.com/sonim1/UpdateBar/blob/main/docs/security.md">Security</a><a href="https://github.com/sonim1/UpdateBar#documentation">Docs</a></nav>
    </footer>
  </body>
</html>
```

- [ ] **Step 2: Run the contract and confirm only styling remains red**

```bash
rtk proxy bash Scripts/landing-contract-test.sh
```

Expected: failure at `missing landing asset: docs/landing.css` after HTML and image checks pass.

- [ ] **Step 3: Commit semantic structure**

```bash
rtk git add docs/index.html
rtk git commit -m "feat: add UpdateBar landing structure"
```

### Task 5: Implement the visual system and motion

**Files:**
- Create: `docs/landing.css`
- Test: `Scripts/landing-contract-test.sh`

- [ ] **Step 1: Define tokens and base layout**

Start `docs/landing.css` with these exact tokens and base rules:

```css
:root {
  color-scheme: dark;
  --demo-cycle: 9s;
  --canvas: #07090d;
  --canvas-raised: #0d121a;
  --surface: rgba(20, 27, 38, 0.76);
  --surface-strong: rgba(24, 33, 46, 0.92);
  --line: rgba(255, 255, 255, 0.11);
  --line-soft: rgba(255, 255, 255, 0.07);
  --text: #f5f8fc;
  --text-soft: #b4bfce;
  --text-faint: #778397;
  --blue: #70aaff;
  --cyan: #62d9e9;
  --green: #72d5aa;
  --radius-lg: 28px;
  --radius-md: 18px;
  --radius-sm: 12px;
  --max-width: 1180px;
  --shadow: 0 28px 90px rgba(0, 0, 0, 0.44);
}
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body { margin: 0; min-width: 320px; overflow-x: hidden; background: var(--canvas); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", sans-serif; line-height: 1.5; -webkit-font-smoothing: antialiased; }
a { color: inherit; text-decoration: none; }
a:focus-visible { outline: 3px solid var(--blue); outline-offset: 4px; border-radius: 6px; }
.shell { width: min(calc(100% - 48px), var(--max-width)); margin-inline: auto; }
.page-glow { position: absolute; width: 34rem; height: 34rem; border-radius: 50%; pointer-events: none; filter: blur(90px); opacity: .18; }
.page-glow--top { top: -24rem; right: 12%; background: #2869d9; }
.page-glow--bottom { top: 70rem; left: -24rem; background: #167b97; }
```

Append these focused component rules:

```css
.site-header { position: relative; z-index: 2; display: flex; align-items: center; justify-content: space-between; padding-top: 28px; }
.brand { display: inline-flex; align-items: center; gap: 10px; font-size: 16px; font-weight: 700; letter-spacing: -.02em; }
.brand img { width: 30px; height: 30px; border-radius: 8px; box-shadow: 0 6px 18px rgba(0, 0, 0, .3); }
.header-nav { display: flex; align-items: center; gap: 24px; }
.nav-link { color: var(--text-soft); font-size: 13px; transition: color 180ms ease; }
.nav-link:hover { color: var(--text); }
.button { display: inline-flex; min-height: 48px; align-items: center; justify-content: center; gap: 9px; padding: 0 19px; border: 1px solid transparent; border-radius: 999px; font-size: 13px; font-weight: 700; transition: transform 180ms ease, background 180ms ease, border-color 180ms ease; }
.button:hover { transform: translateY(-2px); }
.button--small { min-height: 36px; padding-inline: 15px; font-size: 12px; }
.button--light { border-color: var(--line); background: rgba(255, 255, 255, .08); }
.button--light:hover { border-color: rgba(255, 255, 255, .2); background: rgba(255, 255, 255, .13); }
.button--primary { background: var(--text); color: #10141a; box-shadow: 0 10px 30px rgba(0, 0, 0, .28); }
.button--primary:hover { background: #fff; }
.hero { position: relative; z-index: 1; display: flex; flex-direction: column; align-items: center; padding-top: 86px; padding-bottom: 96px; text-align: center; }
.hero-copy { max-width: 800px; animation: hero-rise 600ms cubic-bezier(.2, .7, .2, 1) both; }
.eyebrow { display: flex; align-items: center; gap: 9px; margin: 0 0 18px; color: var(--blue); font-size: 12px; font-weight: 700; letter-spacing: .08em; text-transform: uppercase; }
.hero .eyebrow { justify-content: center; }
.eyebrow-dot { width: 7px; height: 7px; border-radius: 50%; background: var(--cyan); box-shadow: 0 0 18px rgba(98, 217, 233, .7); }
h1, h2, h3, p { margin-top: 0; }
h1 { margin-bottom: 22px; font-size: clamp(58px, 8vw, 98px); font-weight: 760; letter-spacing: -.065em; line-height: .94; }
h1 em, h2 em { color: var(--blue); font-style: normal; }
.hero-lede { max-width: 640px; margin: 0 auto; color: var(--text-soft); font-size: 18px; }
.hero-actions { display: flex; justify-content: center; gap: 20px; margin-top: 30px; }
.text-link { display: inline-flex; min-height: 48px; align-items: center; gap: 8px; color: var(--text-soft); font-size: 13px; font-weight: 650; }
.text-link:hover { color: var(--text); }
.trust-row { display: flex; flex-wrap: wrap; justify-content: center; gap: 14px 26px; padding: 0; margin: 28px 0 0; color: var(--text-faint); font-size: 12px; list-style: none; }
.demo-reel { animation: hero-rise 700ms 120ms cubic-bezier(.2, .7, .2, 1) both; }
.demo-reel figcaption { max-width: 620px; margin: 15px auto 0; color: var(--text-faint); font-size: 12px; text-align: center; }
.source-cta { padding-bottom: 96px; }
.source-cta__inner { display: grid; grid-template-columns: 1fr 1fr; gap: 72px; align-items: center; padding: 48px; border: 1px solid var(--line); border-radius: var(--radius-lg); background: linear-gradient(135deg, rgba(39, 81, 145, .18), var(--surface)); }
.source-cta h2, .section-heading h2 { margin-bottom: 16px; font-size: clamp(38px, 5vw, 64px); letter-spacing: -.055em; line-height: 1; }
.source-cta p, .section-intro { color: var(--text-soft); }
.install-options { display: grid; gap: 16px; }
.install-option__label { display: block; margin-bottom: 8px; color: var(--text-faint); font-size: 11px; text-transform: uppercase; }
.source-command { display: flex; align-items: center; gap: 10px; padding: 15px; border: 1px solid var(--line); border-radius: var(--radius-sm); background: rgba(3, 5, 8, .72); color: #c9d6e8; font: 12px ui-monospace, SFMono-Regular, Menlo, monospace; white-space: nowrap; }
.source-command__prompt { color: var(--cyan); }
.install-links { display: flex; flex-wrap: wrap; gap: 18px; color: var(--text-soft); font-size: 12px; }
.install-links a:hover { color: var(--text); }
.how-it-works, .features { padding-bottom: 112px; }
.section-heading { margin-bottom: 46px; }
.section-heading--split { display: grid; grid-template-columns: 1fr minmax(260px, 380px); gap: 48px; align-items: end; }
.section-intro { margin-bottom: 18px; }
.steps { display: grid; grid-template-columns: 1fr auto 1fr auto 1fr; gap: 20px; align-items: center; }
.step { min-height: 220px; padding: 28px; border-top: 1px solid var(--line); background: linear-gradient(180deg, rgba(255, 255, 255, .025), transparent); }
.step-number { color: var(--cyan); font: 11px ui-monospace, SFMono-Regular, Menlo, monospace; }
.step h3 { margin: 38px 0 10px; font-size: 24px; }
.step p { margin: 0; color: var(--text-soft); font-size: 14px; }
.step-connector { color: var(--text-faint); }
.feature-grid { display: grid; grid-template-columns: repeat(2, 1fr); border-top: 1px solid var(--line); border-left: 1px solid var(--line); }
.feature { min-height: 280px; padding: 34px; border-right: 1px solid var(--line); border-bottom: 1px solid var(--line); background: rgba(255, 255, 255, .018); transition: background 180ms ease, transform 180ms ease; }
.feature:hover { background: rgba(112, 170, 255, .055); transform: translateY(-2px); }
.feature-kicker { color: var(--cyan); font-size: 11px; font-weight: 700; letter-spacing: .08em; text-transform: uppercase; }
.feature h3 { max-width: 420px; margin: 54px 0 12px; font-size: 26px; line-height: 1.15; }
.feature > p:last-child { margin-bottom: 0; color: var(--text-soft); font-size: 14px; }
.site-footer { display: flex; align-items: center; justify-content: space-between; gap: 24px; padding-top: 32px; padding-bottom: 44px; border-top: 1px solid var(--line-soft); color: var(--text-faint); font-size: 12px; }
.site-footer p { margin: 0; }
.site-footer nav { display: flex; flex-wrap: wrap; gap: 18px; }
.site-footer a:hover { color: var(--text); }
@keyframes hero-rise { from { opacity: 0; transform: translateY(16px); } to { opacity: 1; transform: translateY(0); } }
```

- [ ] **Step 2: Add the demo sequence**

Add these exact animation hooks, then style the surrounding figure and caption consistently:

```css
.demo-reel { position: relative; width: min(100%, 1040px); margin: 52px auto 0; }
.demo-window { position: relative; aspect-ratio: 1200 / 760; overflow: hidden; border: 1px solid var(--line); border-radius: var(--radius-lg); background: var(--canvas-raised); box-shadow: var(--shadow); }
.demo-frame { position: absolute; inset: 0; display: block; width: 100%; height: 100%; object-fit: cover; opacity: 0; }
.demo-frame--overview { animation: demo-overview var(--demo-cycle) steps(1, end) infinite; }
.demo-frame--approval { animation: demo-approval var(--demo-cycle) steps(1, end) infinite; }
.demo-frame--history { animation: demo-history var(--demo-cycle) steps(1, end) infinite; }
.demo-label { position: absolute; left: 50%; bottom: 22px; z-index: 3; min-width: 230px; padding: 10px 15px; border: 1px solid var(--line); border-radius: 999px; background: rgba(7, 9, 13, .82); color: var(--text); font-size: 13px; font-weight: 650; text-align: center; transform: translateX(-50%); backdrop-filter: blur(18px); }
.demo-label--overview { animation: demo-overview var(--demo-cycle) steps(1, end) infinite; }
.demo-label--approval { animation: demo-approval var(--demo-cycle) steps(1, end) infinite; }
.demo-label--history { animation: demo-history var(--demo-cycle) steps(1, end) infinite; }
.demo-motion-toggle { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); clip-path: inset(50%); }
.demo-motion-control { position: absolute; top: 14px; right: 14px; z-index: 5; padding: 7px 10px; border: 1px solid var(--line); border-radius: 999px; background: rgba(7, 9, 13, .74); color: var(--text-soft); cursor: pointer; font-size: 11px; backdrop-filter: blur(14px); }
.demo-motion-control__play { display: none; }
.demo-motion-control__name { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); }
.demo-motion-toggle:checked + .demo-motion-control .demo-motion-control__pause { display: none; }
.demo-motion-toggle:checked + .demo-motion-control .demo-motion-control__play { display: inline; }
.demo-motion-toggle:checked ~ .demo-window .demo-frame,
.demo-motion-toggle:checked ~ .demo-window .demo-label { animation-play-state: paused; }
@keyframes demo-overview { 0%, 33.332% { opacity: 1; } 33.333%, 100% { opacity: 0; } }
@keyframes demo-approval { 0%, 33.332% { opacity: 0; } 33.333%, 66.665% { opacity: 1; } 66.666%, 100% { opacity: 0; } }
@keyframes demo-history { 0%, 66.665% { opacity: 0; } 66.666%, 100% { opacity: 1; } }
```

- [ ] **Step 3: Add responsive and reduced-motion rules**

```css
@media (max-width: 760px) {
  .shell { width: min(calc(100% - 32px), var(--max-width)); }
  .site-header { padding-top: 20px; }
  .hero { padding-top: 58px; padding-bottom: 72px; }
  .hero h1 { font-size: clamp(46px, 15vw, 68px); }
  .trust-row { gap: 12px 18px; }
  .source-cta__inner, .section-heading--split { grid-template-columns: 1fr; }
  .steps { grid-template-columns: 1fr; }
  .step-connector { transform: rotate(90deg); }
  .feature-grid { grid-template-columns: 1fr; }
  .demo-window { aspect-ratio: 4 / 5; }
  .demo-frame { object-position: center; }
  .source-command { overflow-x: auto; }
}
@media (max-width: 420px) {
  .header-nav .nav-link { display: none; }
  .hero-actions { align-items: stretch; flex-direction: column; }
  .button, .text-link { justify-content: center; }
  .demo-label { min-width: 0; width: calc(100% - 32px); }
  .site-footer { align-items: flex-start; flex-direction: column; }
}
@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  *, *::before, *::after { scroll-behavior: auto !important; transition-duration: .01ms !important; animation-duration: .01ms !important; animation-iteration-count: 1 !important; }
  .demo-frame, .demo-label { animation: none !important; opacity: 0; }
  .demo-frame--poster, .demo-label--overview { opacity: 1; }
  .demo-motion-control { display: none; }
}
```

- [ ] **Step 4: Run the landing contract**

```bash
rtk proxy bash Scripts/landing-contract-test.sh
rtk git diff --check
```

Expected: `landing contract passed`; diff check has no output.

- [ ] **Step 5: Commit styling**

```bash
rtk git add docs/landing.css
rtk git commit -m "feat: style UpdateBar landing page"
```

### Task 6: Link the landing source and run browser QA

**Files:**
- Modify: `README.md`
- Verify: `docs/index.html`
- Verify: `docs/landing.css`
- Verify: `docs/demo/*.webp`
- Test: `Scripts/landing-contract-test.sh`

- [ ] **Step 1: Add the landing page to the README documentation list**

Add this entry before `Documentation index`:

```markdown
- [Landing page](docs/index.html) — a visual introduction to trusted tool tracking and updates
```

- [ ] **Step 2: Start a local static server and open it in Orca**

```bash
rtk proxy python3 -m http.server 4173 --directory docs
rtk orca tab create --url http://localhost:4173 --json
```

Run the server in a persistent execution session. Use the returned Orca `browserPageId` for all browser checks.

- [ ] **Step 3: Verify desktop and mobile behavior**

At desktop width, verify brand, headline, primary CTA, and top of the product demo form one hierarchy. Capture a screenshot. Then use browser viewport controls or the in-app browser's responsive surface to verify 760px, 390px, and 320px widths.

For each width, verify:

- no horizontal overflow;
- headline remains 2–3 readable lines;
- CTA targets resolve;
- demo text stays legible and images retain aspect ratio;
- the install command can scroll without expanding the page;
- footer links remain reachable.

- [ ] **Step 4: Verify interaction and accessibility**

Use Orca snapshot and keyboard navigation to verify one `h1`, semantic landmarks, tab order, visible focus, `#install`, and `#how-it-works`. Toggle the demo pause control and confirm frames stop. Emulate reduced motion and confirm only Overview remains visible. Check console and network output for missing assets or unexpected requests.

- [ ] **Step 5: Run repository verification**

```bash
rtk proxy bash Scripts/landing-contract-test.sh
rtk proxy bash Scripts/app-icon-test.sh
rtk proxy swift test
rtk git diff --check
rtk git status --short
```

Expected: landing and icon contracts pass, Swift reports zero test failures, diff check has no output, and status contains only intentional landing/README changes not already committed.

- [ ] **Step 6: Commit documentation and any evidence-backed landing fixes**

```bash
rtk git add README.md docs/index.html docs/landing.css docs/demo Scripts/landing-contract-test.sh
rtk git commit -m "docs: link UpdateBar landing page"
```

If QA required HTML/CSS fixes, include only those evidence-backed changes. Do not change native app sources.

## Final verification gate

- [ ] `rtk proxy bash Scripts/landing-contract-test.sh` prints `landing contract passed`.
- [ ] `rtk proxy swift test` reports zero failures.
- [ ] `rtk git diff --check` prints no output.
- [ ] Desktop, 760px, 390px, and 320px screenshots show no overflow or clipped CTA.
- [ ] Reduced motion shows the Overview poster without animation.
- [ ] Browser console has no errors and network requests contain only local assets plus user-initiated GitHub navigation.
- [ ] The final diff contains no Swift, release workflow, Homebrew, Sparkle, or product-behavior changes.
