#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

usage() {
  echo 'Usage: Scripts/plan-release.sh <base-commit> <head-commit> [output-file]' >&2
}

reject() {
  echo "plan release rejected: $1" >&2
  exit 65
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage
  exit 64
fi

BASE_INPUT="$1"
HEAD_INPUT="$2"
OUTPUT_FILE="${3:-}"

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

if ! git merge-base --is-ancestor "$BASE_COMMIT" "$HEAD_COMMIT" 2>/dev/null; then
  reject "base commit is not an ancestor of head commit: $BASE_INPUT"
fi

set +e
PLAN_RESULT="$(
  /usr/bin/ruby - "$REPOSITORY_ROOT" "$BASE_COMMIT" "$HEAD_COMMIT" "$OUTPUT_FILE" <<'RUBY'
require "date"
require "open3"

class PlanningError < StandardError; end

VERSION_FILE = "version.env"
SWIFT_FILE = "Sources/UpdateBarCLI/UpdateBarVersion.swift"
CHANGELOG_FILE = "CHANGELOG.md"
REPOSITORY_ARTIFACTS = [VERSION_FILE, SWIFT_FILE, CHANGELOG_FILE].freeze
VERSION_COMPONENT = "(?:0|[1-9][0-9]*)"
VERSION_PATTERN = /\AUPDATEBAR_VERSION=(#{VERSION_COMPONENT})\.(#{VERSION_COMPONENT})\.(#{VERSION_COMPONENT})\n\z/n
NUMERIC_RELEASE_HEADING_PATTERN = /\A {0,3}##[ \t]+[0-9]/n
RELEASE_HEADING_PATTERN = /\A## (#{VERSION_COMPONENT}\.#{VERSION_COMPONENT}\.#{VERSION_COMPONENT})(?: - ([0-9]{4}-[0-9]{2}-[0-9]{2}))?\z/n
FENCE_OPENING_PATTERN = /\A {0,3}(`{3,}|~{3,})([^\n]*)\z/n
FENCE_CLOSING_PATTERN = /\A {0,3}(`+|~+)[ \t]*\z/n
LEVEL_TWO_HEADING_PATTERN = /\A {0,3}##[ \t]+[^\n]*\z/n

def canonical_destination(path)
  unresolved = []
  ancestor = path

  until File.exist?(ancestor) || File.symlink?(ancestor)
    parent = File.dirname(ancestor)
    raise PlanningError, "output path has no resolvable parent" if parent == ancestor

    unresolved.unshift(File.basename(ancestor))
    ancestor = parent
  end

  File.join(File.realpath(ancestor), *unresolved)
end

def parent_components(path)
  components = []
  current = File.dirname(path)

  loop do
    components.unshift(current)
    parent = File.dirname(current)
    break if parent == current

    current = parent
  end

  components
end

def same_file?(left_stat, right_stat)
  left_stat.dev == right_stat.dev && left_stat.ino == right_stat.ino
end

def require_single_link(stat)
  return if stat.nlink == 1

  raise PlanningError, "output file must have exactly one hard link"
end

def inside_directory?(path, directory)
  path == directory || path.start_with?("#{directory}#{File::SEPARATOR}")
end

def open_output_file(repository_root, output_file)
  return nil if output_file.empty?

  expanded_output = File.expand_path(output_file, repository_root)
  resolved_output = canonical_destination(expanded_output)
  artifact_paths = REPOSITORY_ARTIFACTS.map do |artifact|
    File.expand_path(artifact, repository_root)
  end
  conflict = artifact_paths.find do |artifact_path|
    artifact_resolved = canonical_destination(artifact_path)
    expanded_output == artifact_path || resolved_output == artifact_resolved ||
      ((File.exist?(expanded_output) || File.symlink?(expanded_output)) &&
        (File.exist?(artifact_path) || File.symlink?(artifact_path)) &&
        File.identical?(expanded_output, artifact_path))
  rescue Errno::ENOENT
    expanded_output == artifact_path
  end
  if conflict
    artifact = REPOSITORY_ARTIFACTS.fetch(artifact_paths.index(conflict))
    raise PlanningError, "output file overlaps repository artifact: #{artifact}"
  end
  if inside_directory?(expanded_output, repository_root) ||
      inside_directory?(resolved_output, repository_root)
    raise PlanningError, "output file must be outside the repository"
  end

  repository_stat = File.stat(repository_root)
  parent_states = parent_components(expanded_output).map do |component|
    begin
      stat = File.lstat(component)
    rescue Errno::ENOENT
      raise PlanningError, "output parent component does not exist: #{component}"
    end
    unless stat.directory? && !stat.symlink?
      raise PlanningError,
        "output parent component is not a directory or is a symlink: #{component}"
    end
    if same_file?(stat, repository_stat)
      raise PlanningError, "output file must be outside the repository"
    end
    [component, stat]
  end

  output_parent = File.dirname(expanded_output)
  unless File.writable?(output_parent)
    raise PlanningError, "output parent directory is not writable: #{output_parent}"
  end

  endpoint_stat = nil
  if File.exist?(expanded_output) || File.symlink?(expanded_output)
    endpoint_stat = File.lstat(expanded_output)
    unless endpoint_stat.file? && !endpoint_stat.symlink?
      raise PlanningError, "output file is not a regular non-symlink file"
    end
    require_single_link(endpoint_stat)
    unless File.writable?(expanded_output)
      raise PlanningError, "output file is not writable"
    end
  end

  flags = File::WRONLY | File::CREAT | File::APPEND
  flags |= File.const_get(:NOFOLLOW) if File.const_defined?(:NOFOLLOW)
  output = File.open(expanded_output, flags, 0o666)

  parent_states.each do |component, previous_stat|
    current_stat = File.lstat(component)
    unless current_stat.directory? && !current_stat.symlink? &&
        same_file?(current_stat, previous_stat)
      raise PlanningError, "output parent component changed while opening: #{component}"
    end
  end

  opened_stat = output.stat
  require_single_link(opened_stat)
  current_endpoint_stat = File.lstat(expanded_output)
  require_single_link(current_endpoint_stat)
  unless current_endpoint_stat.file? && !current_endpoint_stat.symlink? &&
      same_file?(opened_stat, current_endpoint_stat)
    raise PlanningError, "output file changed while opening"
  end
  if endpoint_stat && !same_file?(current_endpoint_stat, endpoint_stat)
    raise PlanningError, "output file changed while opening"
  end

  REPOSITORY_ARTIFACTS.each do |artifact|
    artifact_path = File.expand_path(artifact, repository_root)
    next unless File.exist?(artifact_path) || File.symlink?(artifact_path)

    if same_file?(output.stat, File.stat(artifact_path))
      raise PlanningError, "output file overlaps repository artifact: #{artifact}"
    end
  rescue Errno::ENOENT
    next
  end

  output
rescue PlanningError
  output&.close
  raise
rescue SystemCallError => error
  output&.close
  raise PlanningError, "could not validate or open output file: #{error.message}"
end

def git_capture(*arguments)
  stdout, stderr, status = Open3.capture3("git", *arguments)
  [stdout.b, stderr.b, status]
end

def read_revision_file(commit, path, location, missing_label = path)
  source, _stderr, status = git_capture("show", "#{commit}:#{path}")
  unless status.success?
    raise PlanningError, "#{missing_label} is missing from the #{location}"
  end

  source
end

def parse_version(source, location)
  match = VERSION_PATTERN.match(source)
  unless match
    raise PlanningError,
      "#{VERSION_FILE} at the #{location} must contain exactly one canonical UPDATEBAR_VERSION=X.Y.Z line"
  end

  {
    components: match.captures.map { |component| Integer(component, 10) },
    value: match.captures.join("."),
  }
end

def expected_swift_source(version)
  <<~SWIFT.b
    // Generated from version.env by Scripts/generate-version-source.sh.
    enum UpdateBarVersion {
        static let current = "#{version}"
    }
  SWIFT
end

def validated_revision_version(commit, location)
  version = parse_version(read_revision_file(commit, VERSION_FILE, location), location)
  swift_source = read_revision_file(commit, SWIFT_FILE, location, "generated version source")
  unless swift_source == expected_swift_source(version[:value])
    raise PlanningError, "generated version source at the #{location} does not match #{VERSION_FILE}"
  end

  version
end

def level_two_headings(changelog)
  headings = []
  offset = 0
  fence = nil

  changelog.each_line do |line|
    text = line.end_with?("\n".b) ? line.byteslice(0, line.bytesize - 1) : line

    if fence
      closing = FENCE_CLOSING_PATTERN.match(text)
      if closing && closing[1].start_with?(fence[:character]) &&
          closing[1].bytesize >= fence[:length]
        fence = nil
      end
      offset += line.bytesize
      next
    end

    opening = FENCE_OPENING_PATTERN.match(text)
    if opening && !(opening[1].start_with?("`".b) && opening[2].include?("`".b))
      fence = { character: opening[1].byteslice(0, 1), length: opening[1].bytesize }
    elsif LEVEL_TWO_HEADING_PATTERN.match?(text)
      headings << { text: text, begin: offset, end: offset + text.bytesize }
    end

    offset += line.bytesize
  end
  headings
end

def validate_release_date(version, date)
  return if date.nil?

  begin
    parsed = Date.iso8601(date)
  rescue ArgumentError
    raise PlanningError, "#{CHANGELOG_FILE} has a malformed release date for #{version}"
  end
  unless parsed.iso8601 == date
    raise PlanningError, "#{CHANGELOG_FILE} has a malformed release date for #{version}"
  end
end

def validate_changelog(changelog, target_version, base_components)
  headings = level_two_headings(changelog)
  parsed_headings = []
  versions = Hash.new(0)

  headings.each do |heading|
    next unless NUMERIC_RELEASE_HEADING_PATTERN.match?(heading[:text])

    match = RELEASE_HEADING_PATTERN.match(heading[:text])
    unless match
      raise PlanningError,
        "#{CHANGELOG_FILE} has a malformed numeric release heading: #{heading[:text]}"
    end

    version = match[1]
    date = match[2]
    validate_release_date(version, date)
    versions[version] += 1
    parsed_headings << {
      heading: heading,
      version: version,
      components: version.split(".").map { |component| Integer(component, 10) },
      date: date,
    }
  end

  duplicate = versions.find { |_version, count| count > 1 }
  if duplicate
    raise PlanningError,
      "#{CHANGELOG_FILE} has a duplicate release version heading: #{duplicate[0]}"
  end

  future_bare = parsed_headings.find do |parsed|
    parsed[:date].nil? && (parsed[:components] <=> base_components) == 1
  end
  if future_bare
    raise PlanningError,
      "#{CHANGELOG_FILE} bare release heading is not historical: #{future_bare[:version]}"
  end

  targets = parsed_headings.select do |parsed|
    parsed[:version] == target_version && !parsed[:date].nil?
  end
  unless targets.length == 1
    raise PlanningError,
      "#{CHANGELOG_FILE} must contain exactly one dated section for #{target_version}"
  end

  target_heading = targets.first[:heading]
  target_index = headings.index(target_heading)
  body_end = headings.fetch(target_index + 1, { begin: changelog.length })[:begin]
  body = changelog[target_heading[:end]...body_end]
  if body.strip.empty?
    raise PlanningError, "#{CHANGELOG_FILE} section body is empty for #{target_version}"
  end
end

def documentation_only?(base_commit, head_commit)
  changed, stderr, status = git_capture(
    "diff",
    "--name-only",
    "-z",
    "--no-renames",
    base_commit,
    head_commit,
  )
  unless status.success?
    raise PlanningError, "could not inspect changed paths: #{stderr.strip}"
  end

  paths = changed.split("\0", -1)
  paths.pop if paths.last == ""
  paths.all? do |path|
    path.start_with?("docs/".b, "openspec/".b) ||
      (!path.include?("/".b) && (path.end_with?(".md".b) || path.end_with?(".markdown".b)))
  end
end

repository_root, base_commit, head_commit, output_file = ARGV
repository_root = File.realpath(repository_root)
output = nil

begin
  output = open_output_file(repository_root, output_file)
  base_version = validated_revision_version(base_commit, "base commit")
  head_version = validated_revision_version(head_commit, "head commit")
  changelog = read_revision_file(head_commit, CHANGELOG_FILE, "head commit")
  validate_changelog(changelog, head_version[:value], base_version[:components])

  if documentation_only?(base_commit, head_commit)
    result = "release=false"
  else
    unless (head_version[:components] <=> base_version[:components]) == 1
      raise PlanningError,
        "head version #{head_version[:value]} must be strictly greater than base version #{base_version[:value]}"
    end
    result = "release=true\ntag=v#{head_version[:value]}\nversion=#{head_version[:value]}"
  end

  if output
    require_single_link(output.stat)
    output.write("#{result}\n")
    output.flush
  end
  puts result
rescue PlanningError, SystemCallError => error
  warn "plan release rejected: #{error.message}"
  exit 65
ensure
  output&.close
end
RUBY
)"
PLAN_STATUS=$?
set -e

if [[ "$PLAN_STATUS" -ne 0 ]]; then
  exit "$PLAN_STATUS"
fi

printf '%s\n' "$PLAN_RESULT"
