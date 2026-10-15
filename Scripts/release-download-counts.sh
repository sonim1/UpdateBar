#!/usr/bin/env bash
set -euo pipefail

repository="${1:-sonim1/UpdateBar}"
[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
  echo 'usage: release-download-counts.sh [OWNER/REPOSITORY]' >&2
  exit 64
}

releases="$(mktemp)"
trap 'rm -f "$releases"' EXIT
gh api --paginate --slurp "/repos/$repository/releases?per_page=100" > "$releases"

ruby -rjson - "$repository" "$releases" <<'RUBY'
repository, path = ARGV
releases = JSON.parse(File.binread(path)).flatten.reject { |release| release.fetch("draft") }
total = 0

puts "# GitHub release asset downloads for #{repository}"
puts
puts "| Release | Published | Asset | Downloads |"
puts "| --- | --- | --- | ---: |"
releases.each do |release|
  release.fetch("assets").each do |asset|
    count = asset.fetch("download_count")
    total += count
    puts "| #{release.fetch("tag_name")} | #{release.fetch("published_at").to_s[0, 10]} | #{asset.fetch("name")} | #{count} |"
  end
end
puts
puts "**GitHub release asset downloads: #{total}**"
puts
puts "Downloads are transfer counts, not unique users or successful installations. " \
  "R2/Sparkle downloads are not included. GitHub source archive downloads are also unavailable in this report."
RUBY
