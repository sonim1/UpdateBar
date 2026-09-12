#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

home_page='docs/index.html'
style='docs/landing.css'
icon='docs/AppIcon-256.png'
favicon='docs/favicon.png'
headers='docs/_headers'
demo_dir='docs/demo'
demo_assets=(overview.webp approval.webp history.webp)
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

for path in "$style" "$icon" "$favicon" "$headers" "${pages[@]}" "${discovery_files[@]}"; do
  test -s "$path" || { echo "missing landing asset: $path" >&2; exit 1; }
done

grep -q 'id="install"' "$home_page"
grep -q 'id="how-it-works"' "$home_page"
grep -q 'class="demo-reel"' "$home_page"
grep -q 'Every tool.' "$home_page"
grep -q 'One update away.' "$home_page"
grep -q 'brew install --cask sonim1/tap/updatebar-app' "$home_page"
grep -q 'macOS 13+' "$home_page"
grep -q 'Signed &amp; notarized' "$home_page"
grep -q 'No telemetry' "$home_page"

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

ruby -rjson -ruri -e '
  titles = []
  descriptions = []
  ARGV.each do |path|
    html = File.binread(path)
    blocks = html.scan(%r{<script type="application/ld\+json">(.*?)</script>}m).flatten
    raise "missing JSON-LD: #{path}" unless blocks.length == 1
    raise "unexpected executable script: #{path}" unless html.scan(/<script\b/i).length == 1
    graph = JSON.parse(blocks.first).fetch("@graph")
    ids = graph.map { |entry| entry["@id"] }
    raise "missing software entity: #{path}" unless ids.include?("https://updatebar.royjen.com/#software")
    title = html[/<title>(.*?)<\/title>/m, 1]
    description = html[/<meta name="description" content="([^"]+)"/, 1]
    canonical = html[/<link rel="canonical" href="([^"]+)"/, 1]
    raise "missing title: #{path}" if title.nil? || title.empty?
    titles << title
    descriptions << description
    webpage = graph.find { |entry| entry["@type"] == "WebPage" }
    raise "invalid webpage entity: #{path}" unless webpage &&
      webpage["@id"] == "#{canonical}#webpage" && webpage["url"] == canonical &&
      webpage["name"] == title && webpage["description"] == description &&
      webpage.dig("about", "@id") == "https://updatebar.royjen.com/#software"
  end
  raise "duplicate landing titles" unless titles.uniq.length == ARGV.length
  raise "duplicate landing descriptions" unless descriptions.uniq.length == ARGV.length

  (ARGV + ["docs/404.html"]).each do |path|
    html = File.binread(path)
    raise "unexpected executable script: #{path}" if path.end_with?("404.html") && html.match?(/<script\b/i)
    html.scan(/(?:href|src)="([^"]+)"/).flatten.each do |value|
      next if value.match?(%r{\Ahttps?://})
      route = path.delete_prefix("docs").sub(/index\.html\z/, "")
      uri = URI.join("https://updatebar.royjen.com#{route}", value)
      target = "docs#{uri.path}"
      target += "index.html" if target.end_with?("/")
      raise "missing local link or asset: #{path}: #{value}" unless File.file?(target)
      if uri.fragment && !File.binread(target).include?("id=\"#{uri.fragment}\"")
        raise "missing local anchor: #{path}: #{value}"
      end
    end
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

grep -q 'Update developer tools from one trusted place.' docs/index.html
grep -q 'Update developer tools from your Mac menu bar.' docs/macos/index.html
grep -q 'A deterministic CLI for developers and AI agents.' docs/cli-agents/index.html
grep -q 'updatebar guide agent' docs/cli-agents/index.html
grep -q 'updatebar validate recipe.json --json --explain' docs/cli-agents/index.html
grep -q 'updatebar add --from recipe.json --dry-run --json' docs/cli-agents/index.html
grep -q 'Never approve commands silently.' docs/cli-agents/index.html
grep -q 'brew install --cask sonim1/tap/updatebar-app' docs/index.html docs/macos/index.html
grep -q 'macOS 13+' docs/macos/index.html
grep -q 'Signed &amp; notarized' docs/macos/index.html
grep -q 'No telemetry' docs/index.html docs/macos/index.html
grep -q 'X-Content-Type-Options: nosniff' "$headers"
grep -q "Content-Security-Policy: default-src 'self'" "$headers"

if grep -RqiE '<video[[:space:]>]|<canvas[[:space:]>]|tracker|analytics|http://' "${pages[@]}" docs/404.html "$style"; then
  echo 'landing pages must stay free of video, canvas, trackers, analytics, and insecure URLs' >&2
  exit 1
fi
if grep -RqiE 'src="https?://' "${pages[@]}" docs/404.html; then
  echo 'landing page images must be served locally' >&2
  exit 1
fi
if grep -RqiE 'updatebar (apply|inspect)|fully sandboxed|safe to run arbitrary|auto-approve|built-in AI|99\.9%|(^|[^[:alnum:]_])trusted by' "${pages[@]}"; then
  echo 'landing pages contain an unsupported command or claim' >&2
  exit 1
fi
if grep -RhqE '—|–' "${pages[@]}" docs/404.html; then
  echo 'landing pages contain a forbidden display dash' >&2
  exit 1
fi
if grep -RqiE 'TODO|TBD|placeholder|lorem ipsum' "${pages[@]}" docs/404.html "$style"; then
  echo 'landing pages contain unfinished copy' >&2
  exit 1
fi
macos_user_root='/'"Users/"
if grep -RqE "${macos_user_root}|file:///" "${pages[@]}" docs/404.html "$style"; then
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

for asset in "${demo_assets[@]}"; do
  grep -Rq "demo/$asset" "${pages[@]}"
done
test "$(grep -oE 'src="/?demo/(overview|approval|history)\.webp"' "$home_page" | sort -u | wc -l | tr -d ' ')" = 3
grep -q -- '--demo-cycle: 9s' "$style"
grep -q '@keyframes demo-overview' "$style"
grep -q '@keyframes demo-approval' "$style"
grep -q '@keyframes demo-history' "$style"
grep -q 'prefers-reduced-motion: reduce' "$style"
grep -q 'demo-frame--poster' "$home_page"
grep -q '.demo-motion-toggle:checked ~ .demo-window' "$style"
grep -q 'animation-play-state: paused' "$style"
grep -q -- '--surface-glass:' "$style"
grep -q 'grid-auto-flow: dense' "$style"
for page_path in "${pages[@]:1}"; do
  if grep -q 'demo-motion-toggle\|demo-cycle\|animation-play-state' "$page_path"; then
    echo 'audience pages must use stable product imagery without automatic demo cycling' >&2
    exit 1
  fi
done

echo 'landing contract passed'
