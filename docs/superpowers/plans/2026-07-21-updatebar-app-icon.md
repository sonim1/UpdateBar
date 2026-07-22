# UpdateBar App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the approved graphite/forest and mint/chartreuse UpdateBar app icon in the macOS app bundle.

**Architecture:** Store one deterministic 1024-pixel SVG master with background, arrow, and bar groups, and generate a standard multi-representation `UpdateBar.icns` with macOS system tools. The existing manual packaging script copies that immutable artifact into `Contents/Resources`, declares it through `CFBundleIconFile`, and existing packaging/archive tests verify the resource survives signing and distribution.

**Tech Stack:** SVG, Bash, `sips`, `iconutil`, SwiftPM app packaging, plist bundle metadata

---

## File Map

- Create `Assets/AppIcon/UpdateBar.svg`: canonical 1024-by-1024 vector artwork with named background, arrow, and bar groups.
- Create `Assets/AppIcon/UpdateBar.icns`: generated shipping artifact containing standard macOS 1x/2x representations.
- Create `Scripts/build-app-icon.sh`: reproducibly rasterizes the SVG and assembles the `.icns` file.
- Create `Scripts/app-icon-test.sh`: validates source structure and the generated icon representations.
- Modify `Scripts/quality-gate.sh`: runs the focused icon validation.
- Modify `Scripts/package-app.sh`: copies the icon and declares `CFBundleIconFile` before signing.
- Modify `Scripts/package-app-signing-test.sh`: provides the fixture icon and proves packaging includes it without changing signing order.
- Modify `Scripts/app-archive-smoke-test.sh`: proves the distributed archive contains the icon and matching plist entry.

### Task 1: Create and validate the production icon assets

**Files:**
- Create: `Scripts/app-icon-test.sh`
- Create: `Scripts/build-app-icon.sh`
- Create: `Assets/AppIcon/UpdateBar.svg`
- Create: `Assets/AppIcon/UpdateBar.icns`
- Modify: `Scripts/quality-gate.sh:100-115`

- [ ] **Step 1: Write the failing asset validation test**

Create `Scripts/app-icon-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/Assets/AppIcon/UpdateBar.svg"
ICNS="$ROOT/Assets/AppIcon/UpdateBar.icns"

[[ -f "$SVG" ]] || { echo "missing app icon SVG: $SVG" >&2; exit 1; }
[[ -f "$ICNS" ]] || { echo "missing app icon ICNS: $ICNS" >&2; exit 1; }

grep -Fq 'viewBox="0 0 1024 1024"' "$SVG" || {
  echo "app icon SVG must use a 1024x1024 viewBox" >&2
  exit 1
}
for layer in 'id="background"' 'id="arrow"' 'id="bar"'; do
  grep -Fq "$layer" "$SVG" || {
    echo "app icon SVG missing layer: $layer" >&2
    exit 1
  }
done
if grep -Eq '<text([[:space:]>])' "$SVG"; then
  echo "app icon SVG must not contain text" >&2
  exit 1
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  iconutil -c iconset "$ICNS" -o "$TMP_DIR/UpdateBar.iconset"
  for file in \
    icon_16x16.png icon_16x16@2x.png \
    icon_32x32.png icon_32x32@2x.png \
    icon_128x128.png icon_128x128@2x.png \
    icon_256x256.png icon_256x256@2x.png \
    icon_512x512.png icon_512x512@2x.png; do
    [[ -f "$TMP_DIR/UpdateBar.iconset/$file" ]] || {
      echo "app icon ICNS missing representation: $file" >&2
      exit 1
    }
  done
fi

echo "app icon assets ok"
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
rtk test bash Scripts/app-icon-test.sh
```

Expected: FAIL with `missing app icon SVG`.

- [ ] **Step 3: Add the deterministic SVG master**

Create `Assets/AppIcon/UpdateBar.svg` with the approved colors, centered geometry, shallow V-tail, and restrained material treatment:

```svg
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="backgroundFill" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#252D2B"/>
      <stop offset="0.58" stop-color="#14251F"/>
      <stop offset="1" stop-color="#0C3D2B"/>
    </linearGradient>
    <linearGradient id="arrowFill" x1="0" y1="0" x2="0.65" y2="1">
      <stop offset="0" stop-color="#D8FF72"/>
      <stop offset="0.45" stop-color="#9DEB67"/>
      <stop offset="1" stop-color="#50D99A"/>
    </linearGradient>
    <linearGradient id="barFill" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#D7FBE2" stop-opacity="0.78"/>
      <stop offset="1" stop-color="#72CAA0" stop-opacity="0.58"/>
    </linearGradient>
    <filter id="lift" x="-20%" y="-20%" width="140%" height="150%">
      <feDropShadow dx="0" dy="12" stdDeviation="12" flood-color="#42C986" flood-opacity="0.18"/>
    </filter>
  </defs>
  <g id="background">
    <rect width="1024" height="1024" fill="url(#backgroundFill)"/>
    <path d="M0 0H1024" stroke="#FFFFFF" stroke-opacity="0.16" stroke-width="10"/>
  </g>
  <g id="arrow" filter="url(#lift)">
    <path
      d="M512 180L754 466Q770 485 760 507Q750 530 724 530H626V688Q626 706 612 716Q598 726 582 717L512 680L442 717Q426 726 412 716Q398 706 398 688V530H300Q274 530 264 507Q254 485 270 466Z"
      fill="url(#arrowFill)"
      stroke="#E9FFD1"
      stroke-opacity="0.72"
      stroke-width="8"
      stroke-linejoin="round"
    />
    <path d="M512 194L744 469" fill="none" stroke="#FFFFFF" stroke-opacity="0.34" stroke-width="8" stroke-linecap="round"/>
  </g>
  <g id="bar" filter="url(#lift)">
    <rect x="282" y="790" width="460" height="74" rx="37" fill="url(#barFill)" stroke="#E8FFF0" stroke-opacity="0.62" stroke-width="7"/>
    <path d="M320 806H704" stroke="#FFFFFF" stroke-opacity="0.25" stroke-width="5" stroke-linecap="round"/>
  </g>
</svg>
```

- [ ] **Step 4: Add the reproducible ICNS builder**

Create `Scripts/build-app-icon.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/Assets/AppIcon/UpdateBar.svg"
OUTPUT="$ROOT/Assets/AppIcon/UpdateBar.icns"

for tool in sips iconutil; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "$tool is required to build the macOS app icon" >&2
    exit 1
  }
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
MASTER="$TMP_DIR/UpdateBar.png"
ICONSET="$TMP_DIR/UpdateBar.iconset"
mkdir -p "$ICONSET"

sips -s format png "$SOURCE" --out "$MASTER" >/dev/null

while read -r points scale filename; do
  pixels=$((points * scale))
  sips -z "$pixels" "$pixels" "$MASTER" --out "$ICONSET/$filename" >/dev/null
done <<'SIZES'
16 1 icon_16x16.png
16 2 icon_16x16@2x.png
32 1 icon_32x32.png
32 2 icon_32x32@2x.png
128 1 icon_128x128.png
128 2 icon_128x128@2x.png
256 1 icon_256x256.png
256 2 icon_256x256@2x.png
512 1 icon_512x512.png
512 2 icon_512x512@2x.png
SIZES

iconutil -c icns "$ICONSET" -o "$OUTPUT"
echo "$OUTPUT"
```

Make both scripts executable and generate the binary artifact:

```bash
rtk proxy chmod +x Scripts/build-app-icon.sh Scripts/app-icon-test.sh
rtk proxy bash Scripts/build-app-icon.sh
```

Expected: prints the absolute path to `Assets/AppIcon/UpdateBar.icns`.

- [ ] **Step 5: Run the focused test and add it to the quality gate**

Run:

```bash
rtk test bash Scripts/app-icon-test.sh
```

Expected: `app icon assets ok`.

Add this block to `Scripts/quality-gate.sh` before archive tests:

```bash
echo "running app icon asset check"
bash Scripts/app-icon-test.sh
```

Then run:

```bash
rtk test bash Scripts/quality-gate-contract-test.sh
```

Expected: `quality gate contract ok`.

- [ ] **Step 6: Commit the asset unit**

```bash
rtk git add Assets/AppIcon/UpdateBar.svg Assets/AppIcon/UpdateBar.icns Scripts/build-app-icon.sh Scripts/app-icon-test.sh Scripts/quality-gate.sh
rtk git commit -m "feat: add UpdateBar app icon assets"
```

### Task 2: Package the icon before code signing

**Files:**
- Modify: `Scripts/package-app-signing-test.sh:10-19,92-107`
- Modify: `Scripts/package-app.sh:16-20,102-109,114-126`

- [ ] **Step 1: Extend the signing fixture with failing packaging assertions**

In `Scripts/package-app-signing-test.sh`, create the fixture asset directory and copy the real test asset:

```bash
mkdir -p "$TEST_ROOT/Scripts" "$TEST_ROOT/Assets/AppIcon" "$BIN_DIR"
cp "$ROOT/Assets/AppIcon/UpdateBar.icns" "$TEST_ROOT/Assets/AppIcon/UpdateBar.icns"
```

After the subshell that invokes `Scripts/package-app.sh`, add:

```bash
PACKAGED_ICON="$TEST_ROOT/dist/UpdateBar.app/Contents/Resources/UpdateBar.icns"
PACKAGED_PLIST="$TEST_ROOT/dist/UpdateBar.app/Contents/Info.plist"

[[ -f "$PACKAGED_ICON" ]] || {
  echo "package app should copy UpdateBar.icns" >&2
  exit 1
}
grep -A1 -F '<key>CFBundleIconFile</key>' "$PACKAGED_PLIST" | grep -Fq '<string>UpdateBar.icns</string>' || {
  echo "package app should declare CFBundleIconFile" >&2
  exit 1
}
```

- [ ] **Step 2: Run the signing test to verify it fails**

```bash
rtk test bash Scripts/package-app-signing-test.sh
```

Expected: FAIL with `package app should copy UpdateBar.icns`.

- [ ] **Step 3: Implement minimal bundle integration**

In `Scripts/package-app.sh`, define and validate the source:

```bash
ICON_SOURCE="$ROOT/Assets/AppIcon/UpdateBar.icns"
if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "missing app icon: $ICON_SOURCE" >&2
  exit 1
fi
```

Copy it beside the bundled CLI before plist generation and signing:

```bash
cp "$ICON_SOURCE" "$RESOURCES_DIR/UpdateBar.icns"
```

Add the plist declaration immediately after `CFBundleExecutable`:

```xml
  <key>CFBundleIconFile</key>
  <string>UpdateBar.icns</string>
```

- [ ] **Step 4: Run packaging regression tests**

```bash
rtk test bash Scripts/package-app-signing-test.sh
rtk test env UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE=1 bash Scripts/package-app.sh
```

Expected: signing test prints `package app signing behavior ok`; packaging prints `dist/UpdateBar.app`.

Inspect the built bundle:

```bash
rtk proxy plutil -extract CFBundleIconFile raw dist/UpdateBar.app/Contents/Info.plist
rtk proxy test -f dist/UpdateBar.app/Contents/Resources/UpdateBar.icns
```

Expected: `UpdateBar.icns` and exit code 0.

- [ ] **Step 5: Commit packaging integration**

```bash
rtk git add Scripts/package-app.sh Scripts/package-app-signing-test.sh
rtk git commit -m "feat: package the UpdateBar app icon"
```

### Task 3: Verify the icon in release archives

**Files:**
- Modify: `Scripts/app-archive-smoke-test.sh:24-28,46-61,63-101`

- [ ] **Step 1: Add archive-level icon assertions**

Define the extracted icon beside the existing bundle paths:

```bash
APP_ICON="$APP_DIR/Contents/Resources/UpdateBar.icns"
```

After checking the plist, require the resource:

```bash
if [[ ! -f "$APP_ICON" ]]; then
  echo "missing app icon: $APP_ICON" >&2
  exit 1
fi
```

After reading `CFBundleExecutable`, verify the plist binding:

```bash
APP_ICON_FILE="$(plist_value CFBundleIconFile)"
if [[ "$APP_ICON_FILE" != "UpdateBar.icns" ]]; then
  echo "app archive has unexpected icon file: $ARCHIVE" >&2
  echo "  expected: UpdateBar.icns" >&2
  echo "  actual:   ${APP_ICON_FILE:-missing}" >&2
  exit 1
fi
```

- [ ] **Step 2: Build and verify a real app archive**

```bash
rtk test env UPDATEBAR_PACKAGE_SKIP_LAUNCH_SMOKE=1 bash Scripts/package-app.sh
rtk test bash Scripts/build-app-archive.sh
rtk test bash Scripts/app-archive-smoke-test.sh
```

Expected: final command prints `app archive smoke ok`.

- [ ] **Step 3: Commit archive verification**

```bash
rtk git add Scripts/app-archive-smoke-test.sh
rtk git commit -m "test: verify app icon in release archive"
```

### Task 4: Final verification and visual inspection

**Files:**
- Verify only; no planned file changes.

- [ ] **Step 1: Run automated checks**

```bash
rtk test bash Scripts/app-icon-test.sh
rtk test bash Scripts/package-app-signing-test.sh
rtk test bash Scripts/app-archive-smoke-test.sh
rtk test swift test
rtk git diff --check
```

Expected: all tests exit 0 and the diff check emits no output.

- [ ] **Step 2: Inspect generated icon sizes**

```bash
ICON_PREVIEW_DIR="$(mktemp -d)"
trap 'rm -rf "$ICON_PREVIEW_DIR"' EXIT
ICONSET_DIR="$ICON_PREVIEW_DIR/UpdateBar.iconset"
rtk proxy iconutil -c iconset Assets/AppIcon/UpdateBar.icns -o "$ICONSET_DIR"
rtk proxy qlmanage -t -s 512 -o "$ICON_PREVIEW_DIR" Assets/AppIcon/UpdateBar.icns
```

Open the 16, 32, 128, and 512 pixel representations and confirm:

- the broad upward arrow remains immediately recognizable;
- the centered V-tail remains present without becoming a noisy notch;
- the separate bar is visible but subordinate;
- mint/chartreuse remains distinct against graphite/forest;
- no edge content is clipped by the current macOS mask.

- [ ] **Step 3: Inspect the packaged app**

```bash
rtk proxy open dist/UpdateBar.app
rtk proxy open -R dist/UpdateBar.app
```

Confirm the icon appears in Finder and Get Info, and the menu-bar app still launches normally.

- [ ] **Step 4: Review final branch state**

```bash
rtk git status --short
rtk git log --oneline -5
```

Expected: clean worktree with the plan commit followed by the three focused implementation commits.
