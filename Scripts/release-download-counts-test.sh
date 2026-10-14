#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/Scripts/release-download-counts.sh"
[[ -x "$SCRIPT" ]] || { echo "release download count script is missing or not executable" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'api --paginate --slurp /repos/sonim1/UpdateBar/releases?per_page=100' ]]
cat <<'JSON'
[[
  {"tag_name":"v1.2.0","published_at":"2026-10-01T00:00:00Z","draft":false,"assets":[
    {"name":"UpdateBar-1.2.0.dmg","download_count":12},
    {"name":"checksums.txt","download_count":3}
  ]},
  {"tag_name":"v1.1.0","published_at":"2026-09-01T00:00:00Z","draft":false,"assets":[
    {"name":"UpdateBar-1.1.0.dmg","download_count":7}
  ]},
  {"tag_name":"v1.3.0-draft","published_at":null,"draft":true,"assets":[
    {"name":"draft.dmg","download_count":99}
  ]}
]]
JSON
SH
chmod +x "$TMP/bin/gh"

output="$(PATH="$TMP/bin:$PATH" bash "$SCRIPT")"
grep -Fq '| v1.2.0 | 2026-10-01 | UpdateBar-1.2.0.dmg | 12 |' <<< "$output"
grep -Fq '| v1.2.0 | 2026-10-01 | checksums.txt | 3 |' <<< "$output"
grep -Fq '| v1.1.0 | 2026-09-01 | UpdateBar-1.1.0.dmg | 7 |' <<< "$output"
grep -Fq '**GitHub release asset downloads: 22**' <<< "$output"
grep -Fq 'Downloads are transfer counts, not unique users or successful installations.' <<< "$output"
grep -Fq 'R2/Sparkle downloads are not included.' <<< "$output"
if grep -q 'v1.3.0-draft\|draft.dmg\|99' <<< "$output"; then
  echo 'release download report included a draft release' >&2
  exit 1
fi

echo 'release download count tests passed'
