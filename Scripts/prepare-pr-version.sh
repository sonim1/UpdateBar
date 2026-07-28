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

OUTPUT_FD_OPEN=0

close_output_file() {
  if [[ "$OUTPUT_FD_OPEN" -eq 1 ]]; then
    exec 9>&-
    OUTPUT_FD_OPEN=0
  fi
}

trap close_output_file EXIT

emit() {
  local result="$1"

  if [[ "$OUTPUT_FD_OPEN" -eq 1 ]]; then
    if ! printf '%s\n' "$result" >&9; then
      close_output_file
      reject "could not append to output file: $OUTPUT_FILE"
    fi
    close_output_file
  fi
  printf '%s\n' "$result"
}

OWNED_PATHS=(
  'version.env'
  'Sources/UpdateBarCLI/UpdateBarVersion.swift'
  'CHANGELOG.md'
)

validate_parent_components() {
  local path="$1"
  local parent
  local next_parent

  parent="$(dirname -- "$path")"
  while [[ "$parent" != '.' ]]; do
    [[ -d "$parent" && ! -L "$parent" ]] ||
      reject "$path parent component is not a directory: $parent"
    next_parent="$(dirname -- "$parent")"
    [[ "$next_parent" != "$parent" ]] || reject "$path has an invalid parent path"
    parent="$next_parent"
  done
}

for owned_path in "${OWNED_PATHS[@]}"; do
  validate_parent_components "$owned_path"
  [[ -f "$owned_path" && ! -L "$owned_path" ]] || reject "$owned_path is not a regular file"
done

validate_output_file() {
  local validation_result

  [[ -n "$OUTPUT_FILE" ]] || return 0
  if ! validation_result="$(
    /usr/bin/ruby - "$REPOSITORY_ROOT" "$OUTPUT_FILE" "${OWNED_PATHS[@]}" <<'RUBY'
require "tempfile"

root, output_file, *owned_paths = ARGV
root = File.realpath(root)

def canonical_destination(root, path)
  expanded = File.expand_path(path, root)
  unresolved = []
  ancestor = expanded

  until File.exist?(ancestor) || File.symlink?(ancestor)
    parent = File.dirname(ancestor)
    raise "output path has no resolvable parent" if parent == ancestor

    unresolved.unshift(File.basename(ancestor))
    ancestor = parent
  end

  File.join(File.realpath(ancestor), *unresolved)
end

def parent_components(path)
  components = []
  current = File.dirname(path)

  loop do
    parent = File.dirname(current)
    break if parent == current

    components.unshift(current)
    current = parent
  end

  components
end

begin
  expanded_output = File.expand_path(output_file, root)
  resolved_output = canonical_destination(root, output_file)
  conflict = owned_paths.find do |owned_path|
    absolute_owned = File.join(root, owned_path)
    resolved_output == File.realpath(absolute_owned) ||
      (File.exist?(expanded_output) && File.identical?(expanded_output, absolute_owned))
  end

  if conflict
    puts "output file overlaps owned artifact: #{conflict}"
    exit 65
  end

  parent_components(expanded_output).each do |component|
    begin
      stat = File.lstat(component)
    rescue Errno::ENOENT
      raise "output parent component does not exist: #{component}"
    end
    unless stat.directory? && !stat.symlink?
      raise "output parent component is not a directory or is a symlink: #{component}"
    end
  end

  output_parent = File.dirname(expanded_output)
  unless File.writable?(output_parent)
    raise "output parent directory is not writable: #{output_parent}"
  end

  if File.exist?(expanded_output) || File.symlink?(expanded_output)
    stat = File.lstat(expanded_output)
    unless stat.file? && !stat.symlink?
      raise "output file is not a regular non-symlink file"
    end
    unless File.writable?(expanded_output)
      raise "output file is not writable"
    end
  else
    probe = Tempfile.new([".prepare-pr-version-output-", ".probe"], output_parent)
    probe.close!
  end
rescue StandardError => error
  puts "could not validate output file: #{error.message}"
  exit 65
end
RUBY
  )"; then
    reject "${validation_result:-could not validate output file}"
  fi
}

open_output_file() {
  [[ -n "$OUTPUT_FILE" ]] || return 0

  if ! exec 9>> "$OUTPUT_FILE"; then
    reject "could not open output file for append: $OUTPUT_FILE"
  fi
  OUTPUT_FD_OPEN=1
}

validate_output_file
open_output_file

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

for owned_path in "${OWNED_PATHS[@]}"; do
  [[ -w "$owned_path" ]] || reject "$owned_path is not writable"
  owned_directory="$(dirname -- "$owned_path")"
  [[ -d "$owned_directory" && -w "$owned_directory" ]] ||
    reject "$owned_path parent directory is not writable"
done

UTC_DATE="$(date -u +%F)"

set +e
PREPARE_RESULT="$(
  /usr/bin/ruby - "$BASE_COMMIT" "$RELEASE_KIND" "$UTC_DATE" <<'RUBY'
require "date"
require "open3"
require "tempfile"

class PreparationError < StandardError; end

VERSION_FILE = "version.env"
SWIFT_FILE = "Sources/UpdateBarCLI/UpdateBarVersion.swift"
CHANGELOG_FILE = "CHANGELOG.md"
VERSION_COMPONENT = "(?:0|[1-9][0-9]*)"
VERSION_PATTERN = /\AUPDATEBAR_VERSION=(#{VERSION_COMPONENT})\.(#{VERSION_COMPONENT})\.(#{VERSION_COMPONENT})\n\z/
NUMERIC_RELEASE_HEADING_PATTERN = /\A##[ \t]+[0-9]/
RELEASE_VERSION_PREFIX_PATTERN = /\A## (#{VERSION_COMPONENT}\.#{VERSION_COMPONENT}\.#{VERSION_COMPONENT})(?:\z|[ \t])/
CANDIDATE_PATTERN = /\A## (#{VERSION_COMPONENT}\.#{VERSION_COMPONENT}\.#{VERSION_COMPONENT}) - ([0-9]{4}-[0-9]{2}-[0-9]{2})\z/
RELEASE_HEADING_PATTERN = /\A## (#{VERSION_COMPONENT}\.#{VERSION_COMPONENT}\.#{VERSION_COMPONENT})(?: - ([0-9]{4}-[0-9]{2}-[0-9]{2}))?\z/

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

def validate_release_headings(headings)
  versions = Hash.new(0)

  headings.each do |heading|
    next unless NUMERIC_RELEASE_HEADING_PATTERN.match?(heading[:text])

    match = RELEASE_HEADING_PATTERN.match(heading[:text])
    unless match
      raise PreparationError,
        "#{CHANGELOG_FILE} has a malformed numeric release heading: #{heading[:text]}"
    end

    if match[2]
      begin
        parsed_date = Date.iso8601(match[2])
      rescue Date::Error
        raise PreparationError, "#{CHANGELOG_FILE} has a malformed release date for #{match[1]}"
      end
      unless parsed_date.iso8601 == match[2]
        raise PreparationError, "#{CHANGELOG_FILE} has a malformed release date for #{match[1]}"
      end
    end
    versions[match[1]] += 1
  end

  duplicate = versions.find { |_version, count| count > 1 }
  if duplicate
    raise PreparationError, "#{CHANGELOG_FILE} has a duplicate release version heading: #{duplicate[0]}"
  end
end

def parsed_candidate(heading, allowed_versions)
  version_match = RELEASE_VERSION_PREFIX_PATTERN.match(heading[:text])
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

def writable_regular_stat(path)
  parent = File.dirname(path)
  until parent == "."
    parent_stat = File.lstat(parent)
    unless parent_stat.directory? && !parent_stat.symlink?
      raise PreparationError, "#{path} parent component is not a directory: #{parent}"
    end
    next_parent = File.dirname(parent)
    raise PreparationError, "#{path} has an invalid parent path" if next_parent == parent

    parent = next_parent
  end

  stat = File.lstat(path)
  unless stat.file? && !stat.symlink?
    raise PreparationError, "#{path} is not a regular file"
  end
  unless File.writable?(path)
    raise PreparationError, "#{path} is not writable"
  end

  directory = File.dirname(path)
  unless File.directory?(directory) && File.writable?(directory)
    raise PreparationError, "#{path} parent directory is not writable"
  end
  stat
end

def staged_file(path, content, mode, label)
  tempfile = Tempfile.new([".prepare-pr-version-#{File.basename(path)}-", ".#{label}"], File.dirname(path))
  tempfile.binmode
  tempfile.write(content)
  tempfile.flush
  tempfile.fsync
  File.chmod(mode & 0o777, tempfile.path)
  tempfile.close
  tempfile
rescue StandardError
  tempfile&.close!
  raise
end

def replace_artifacts(artifacts)
  states = []
  committed = []

  begin
    artifacts.each do |artifact|
      state = artifact.merge(stat: writable_regular_stat(artifact[:path]))
      states << state
    end

    states.each do |state|
      state[:replacement] = staged_file(
        state[:path],
        state[:expected],
        state[:stat].mode,
        "replacement",
      )
      state[:backup] = staged_file(
        state[:path],
        state[:current],
        state[:stat].mode,
        "backup",
      )
    end

    states.each do |state|
      current_stat = writable_regular_stat(state[:path])
      unless current_stat.dev == state[:stat].dev && current_stat.ino == state[:stat].ino
        raise PreparationError, "#{state[:path]} changed during version preparation"
      end
    end

    states.each do |state|
      File.rename(state[:replacement].path, state[:path])
      committed << state
    end
  rescue StandardError => error
    rollback_errors = []
    committed.reverse_each do |state|
      begin
        File.rename(state[:backup].path, state[:path])
      rescue StandardError => rollback_error
        rollback_errors << "#{state[:path]}: #{rollback_error.message}"
      end
    end

    unless rollback_errors.empty?
      raise PreparationError,
        "artifact replacement failed (#{error.message}); rollback failed for #{rollback_errors.join(', ')}"
    end
    raise error if error.is_a?(PreparationError)

    raise PreparationError, "artifact replacement failed: #{error.message}"
  ensure
    states.each do |state|
      [state[:replacement], state[:backup]].compact.each do |tempfile|
        begin
          tempfile.close!
        rescue Errno::ENOENT
          nil
        end
      end
    end
  end
end

def prepared_changelog(changelog, targets, target_version, utc_date)
  headings = level_two_headings(changelog)
  validate_release_headings(headings)
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
  [VERSION_FILE, SWIFT_FILE, CHANGELOG_FILE].each { |path| writable_regular_stat(path) }
  base_source, status = Open3.capture2e("git", "show", "#{base_commit}:#{VERSION_FILE}")
  unless status.success?
    raise PreparationError, "#{VERSION_FILE} is missing from the base commit"
  end

  base_components = parse_version(base_source, "the base commit")
  current_version_source = File.binread(VERSION_FILE)
  parse_version(current_version_source, "the pull-request head")

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

  artifacts = [
    { path: VERSION_FILE, current: current_version_source, expected: expected_version_source },
    { path: SWIFT_FILE, current: current_swift_source, expected: expected_swift_source },
    { path: CHANGELOG_FILE, current: current_changelog, expected: expected_changelog },
  ]
  changed = artifacts.any? { |artifact| artifact[:current] != artifact[:expected] }

  if changed
    replace_artifacts(artifacts)
  end

  puts "release=true"
  puts "changed=#{changed}"
  puts "ready=#{!changed}"
  puts "version=#{target_version}"
rescue PreparationError, SystemCallError => error
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
