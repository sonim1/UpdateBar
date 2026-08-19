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
if grep -qE "${macos_user_root}|file:///" "$page" "$style"; then
  echo 'public landing assets contain a local filesystem identifier' >&2
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
grep -q 'demo-frame--poster' "$page"
grep -q '.demo-motion-toggle:checked ~ .demo-window' "$style"
grep -q 'animation-play-state: paused' "$style"

echo 'landing contract passed'
