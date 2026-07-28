#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

usage() {
  echo 'Usage: Scripts/prepare-pr-version.sh <base-commit> <head-commit> <patch|minor|major> [output-file]' >&2
}

reject() {
  echo "prepare PR version rejected: $1" >&2
  exit 65
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage
  exit 64
fi

BASE_INPUT="$1"
HEAD_INPUT="$2"
RELEASE_KIND="$3"
OUTPUT_FILE="${4:-}"

case "$RELEASE_KIND" in
  patch | minor | major) ;;
  *) reject "release kind must be patch, minor, or major: $RELEASE_KIND" ;;
esac

REPOSITORY_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" ||
  reject 'current directory is not a git repository'
cd -- "$REPOSITORY_ROOT"

resolve_commit() {
  local input="$1"
  local resolved

  if ! resolved="$(git rev-parse --verify --quiet --end-of-options "$input^{commit}" 2>/dev/null)"; then
    reject "commit does not exist: $input"
  fi
  [[ -n "$resolved" ]] || reject "commit does not exist: $input"
  printf '%s\n' "$resolved"
}

BASE_COMMIT="$(resolve_commit "$BASE_INPUT")"
HEAD_COMMIT="$(resolve_commit "$HEAD_INPUT")"
CURRENT_HEAD="$(git rev-parse --verify HEAD 2>/dev/null)" || reject 'could not resolve the checked-out HEAD'
[[ "$CURRENT_HEAD" == "$HEAD_COMMIT" ]] ||
  reject "checked-out HEAD does not match requested head commit: $CURRENT_HEAD"

emit() {
  local result="$1"

  if [[ -n "$OUTPUT_FILE" ]]; then
    printf '%s\n' "$result" > "$OUTPUT_FILE"
  fi
  printf '%s\n' "$result"
}

DOCS_ONLY=1
while IFS= read -r -d '' changed_path; do
  case "$changed_path" in
    docs/* | openspec/*) ;;
    */*) DOCS_ONLY=0 ;;
    *.md | *.markdown) ;;
    *) DOCS_ONLY=0 ;;
  esac
done < <(git diff --name-only -z --no-renames "$BASE_COMMIT" "$HEAD_COMMIT")

if [[ "$DOCS_ONLY" -eq 1 ]]; then
  emit $'release=false\nchanged=false\nready=true'
  exit 0
fi

OWNED_PATHS=(
  'version.env'
  'Sources/UpdateBarCLI/UpdateBarVersion.swift'
  'CHANGELOG.md'
)
for owned_path in "${OWNED_PATHS[@]}"; do
  [[ -f "$owned_path" && ! -L "$owned_path" ]] || reject "$owned_path is not a regular file"
done

UTC_DATE="$(date -u +%F)"

set +e
PREPARE_RESULT="$(
  /usr/bin/ruby - "$BASE_COMMIT" "$RELEASE_KIND" "$UTC_DATE" <<'RUBY'
require "date"
require "open3"

class PreparationError < StandardError; end

VERSION_FILE = "version.env"
SWIFT_FILE = "Sources/UpdateBarCLI/UpdateBarVersion.swift"
CHANGELOG_FILE = "CHANGELOG.md"
VERSION_COMPONENT = "(?:0|[1-9][0-9]*)"
VERSION_PATTERN = /\AUPDATEBAR_VERSION=(#{VERSION_COMPONENT})\.(#{VERSION_COMPONENT})\.(#{VERSION_COMPONENT})\n\z/
CANDIDATE_VERSION_PATTERN = /\A## (#{VERSION_COMPONENT}\.#{VERSION_COMPONENT}\.#{VERSION_COMPONENT})(?:\z|[ \t])/
CANDIDATE_PATTERN = /\A## (#{VERSION_COMPONENT}\.#{VERSION_COMPONENT}\.#{VERSION_COMPONENT}) - ([0-9]{4}-[0-9]{2}-[0-9]{2})\z/

def parse_version(source, location)
  match = VERSION_PATTERN.match(source)
  unless match
    raise PreparationError,
      "#{VERSION_FILE} at #{location} must contain exactly one canonical UPDATEBAR_VERSION=X.Y.Z line"
  end

  match.captures.map { |component| Integer(component, 10) }
end

def bumped_version(components, release_kind)
  bumped = components.dup
  case release_kind
  when "patch"
    bumped[2] += 1
  when "minor"
    bumped[1] += 1
    bumped[2] = 0
  when "major"
    bumped[0] += 1
    bumped[1] = 0
    bumped[2] = 0
  else
    raise PreparationError, "unsupported release kind: #{release_kind}"
  end
  bumped.join(".")
end

def level_two_headings(changelog)
  headings = []
  changelog.to_enum(:scan, /^##[ \t]+[^\n]*$/).each do
    match = Regexp.last_match
    headings << { text: match[0], begin: match.begin(0), end: match.end(0) }
  end
  headings
end

def section_body(changelog, headings, index)
  body_end = headings.fetch(index + 1, { begin: changelog.length })[:begin]
  changelog[headings.fetch(index)[:end]...body_end]
end

def parsed_candidate(heading, allowed_versions)
  version_match = CANDIDATE_VERSION_PATTERN.match(heading[:text])
  return nil unless version_match && allowed_versions.include?(version_match[1])

  match = CANDIDATE_PATTERN.match(heading[:text])
  unless match
    raise PreparationError, "#{CHANGELOG_FILE} has a malformed candidate heading for #{version_match[1]}"
  end

  begin
    parsed_date = Date.iso8601(match[2])
  rescue Date::Error
    raise PreparationError, "#{CHANGELOG_FILE} has a malformed candidate date for #{match[1]}"
  end
  unless parsed_date.iso8601 == match[2]
    raise PreparationError, "#{CHANGELOG_FILE} has a malformed candidate date for #{match[1]}"
  end

  { heading: heading, version: match[1], date: match[2] }
end

def prepared_changelog(changelog, targets, target_version, utc_date)
  headings = level_two_headings(changelog)
  unreleased_headings = headings.select do |heading|
    heading[:text].sub(/[ \t]+\z/, "") == "## Unreleased"
  end
  unless unreleased_headings.length == 1 && unreleased_headings.first[:text] == "## Unreleased"
    raise PreparationError, "#{CHANGELOG_FILE} must contain exactly one canonical ## Unreleased heading"
  end

  unreleased = unreleased_headings.first
  unreleased_index = headings.index(unreleased)
  unreleased_body = section_body(changelog, headings, unreleased_index)
  candidates = headings.map { |heading| parsed_candidate(heading, targets) }.compact

  unless unreleased_body.strip.empty?
    unless candidates.empty?
      raise PreparationError, "#{CHANGELOG_FILE} has an ambiguous existing candidate heading"
    end

    replacement = "\n\n## #{target_version} - #{utc_date}#{unreleased_body}"
    updated = changelog.dup
    body_end = headings.fetch(unreleased_index + 1, { begin: changelog.length })[:begin]
    updated[unreleased[:end]...body_end] = replacement
    return updated
  end

  unless candidates.length == 1
    raise PreparationError,
      "#{CHANGELOG_FILE} Unreleased body is empty without exactly one unambiguous bot-owned candidate heading"
  end

  candidate = candidates.first
  candidate_index = headings.index(candidate[:heading])
  unless candidate_index == unreleased_index + 1
    raise PreparationError, "#{CHANGELOG_FILE} bot-owned candidate heading is ambiguous"
  end

  candidate_body = section_body(changelog, headings, candidate_index)
  if candidate_body.strip.empty?
    raise PreparationError, "#{CHANGELOG_FILE} candidate body is empty"
  end

  updated = changelog.dup
  replacement = "## #{target_version} - #{candidate[:date]}"
  updated[candidate[:heading][:begin]...candidate[:heading][:end]] = replacement
  updated
end

begin
  base_commit, release_kind, utc_date = ARGV
  base_source, status = Open3.capture2e("git", "show", "#{base_commit}:#{VERSION_FILE}")
  unless status.success?
    raise PreparationError, "#{VERSION_FILE} is missing from the base commit"
  end

  base_components = parse_version(base_source, "the base commit")
  parse_version(File.binread(VERSION_FILE), "the pull-request head")

  targets = %w[patch minor major].map { |kind| bumped_version(base_components, kind) }
  target_version = bumped_version(base_components, release_kind)
  expected_version_source = "UPDATEBAR_VERSION=#{target_version}\n"
  expected_swift_source = <<~SWIFT
    // Generated from version.env by Scripts/generate-version-source.sh.
    enum UpdateBarVersion {
        static let current = "#{target_version}"
    }
  SWIFT
  current_swift_source = File.binread(SWIFT_FILE)
  current_changelog = File.binread(CHANGELOG_FILE)
  expected_changelog = prepared_changelog(
    current_changelog,
    targets,
    target_version,
    utc_date,
  )

  changed =
    expected_version_source != File.binread(VERSION_FILE) ||
    expected_swift_source != current_swift_source ||
    expected_changelog != current_changelog

  if changed
    File.binwrite(VERSION_FILE, expected_version_source)
    File.binwrite(SWIFT_FILE, expected_swift_source)
    File.binwrite(CHANGELOG_FILE, expected_changelog)
  end

  puts "release=true"
  puts "changed=#{changed}"
  puts "ready=#{!changed}"
  puts "version=#{target_version}"
rescue PreparationError, Errno::EACCES, Errno::ENOENT, Errno::EISDIR => error
  warn "prepare PR version rejected: #{error.message}"
  exit 65
end
RUBY
)"
PREPARE_STATUS=$?
set -e

if [[ "$PREPARE_STATUS" -ne 0 ]]; then
  exit "$PREPARE_STATUS"
fi

emit "$PREPARE_RESULT"
