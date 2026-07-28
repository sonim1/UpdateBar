#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SCRIPT_SOURCE="$PROJECT_ROOT/Scripts/prepare-pr-version.sh"
GENERATOR_SOURCE="$PROJECT_ROOT/Scripts/generate-version-source.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[[ -f "$SCRIPT_SOURCE" ]] || fail "prepare script is missing: $SCRIPT_SOURCE"
[[ -f "$GENERATOR_SOURCE" ]] || fail "version source generator is missing: $GENERATOR_SOURCE"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/updatebar-prepare-pr-version.XXXXXX")"
TEMP_ROOT="$(cd -- "$TEMP_ROOT" && pwd -P)"
trap 'rm -rf "$TEMP_ROOT"' EXIT
mkdir -p "$TEMP_ROOT/home"
export HOME="$TEMP_ROOT/home"
export XDG_CONFIG_HOME="$TEMP_ROOT/home/.config"
export GIT_CONFIG_NOSYSTEM=1

FIXTURE_INDEX=0
REPOSITORY=''
BASE_COMMIT=''
HEAD_COMMIT=''
PREPARE_OUTPUT=''
PREPARE_STATUS=0

commit_all() {
  local message="$1"

  git -C "$REPOSITORY" add -A
  git -C "$REPOSITORY" commit --quiet -m "$message"
  git -C "$REPOSITORY" rev-parse HEAD
}

write_version_files() {
  local version="$1"

  printf 'UPDATEBAR_VERSION=%s\n' "$version" > "$REPOSITORY/version.env"
  (
    cd -- "$REPOSITORY"
    Scripts/generate-version-source.sh
  )
}

write_standard_changelog() {
  local version="$1"

  cat > "$REPOSITORY/CHANGELOG.md" <<EOF
# Changelog

## Unreleased

### Added

- Preserve this release note exactly.

## $version - 2026-07-20

- Previous release.
EOF
}

create_fixture() {
  local version="${1:-1.2.3}"

  FIXTURE_INDEX=$((FIXTURE_INDEX + 1))
  REPOSITORY="$TEMP_ROOT/repository-$FIXTURE_INDEX"
  mkdir -p "$REPOSITORY/Scripts" "$REPOSITORY/Sources/UpdateBarCLI" "$REPOSITORY/Sources/Feature"
  cp "$SCRIPT_SOURCE" "$REPOSITORY/Scripts/prepare-pr-version.sh"
  cp "$GENERATOR_SOURCE" "$REPOSITORY/Scripts/generate-version-source.sh"
  chmod +x "$REPOSITORY/Scripts/prepare-pr-version.sh" "$REPOSITORY/Scripts/generate-version-source.sh"
  git -C "$REPOSITORY" init -q
  git -C "$REPOSITORY" config user.name 'UpdateBar Test'
  git -C "$REPOSITORY" config user.email 'updatebar@example.invalid'
  write_version_files "$version"
  write_standard_changelog "$version"
  printf 'func fixtureFeature() {}\n' > "$REPOSITORY/Sources/Feature/Feature.swift"
  printf '# UpdateBar\n' > "$REPOSITORY/README.md"
  BASE_COMMIT="$(commit_all 'base')"
  HEAD_COMMIT="$BASE_COMMIT"
}

make_relevant_head() {
  local label="$1"

  printf '// %s\n' "$label" >> "$REPOSITORY/Sources/Feature/Feature.swift"
  HEAD_COMMIT="$(commit_all "$label")"
}

run_prepare() {
  set +e
  PREPARE_OUTPUT="$({
    cd -- "$REPOSITORY"
    Scripts/prepare-pr-version.sh "$@"
  } 2>&1)"
  PREPARE_STATUS=$?
  set -e
}

assert_status() {
  local expected="$1"

  [[ "$PREPARE_STATUS" -eq "$expected" ]] ||
    fail "expected status $expected, got $PREPARE_STATUS: $PREPARE_OUTPUT"
}

assert_output_contains() {
  local expected="$1"

  [[ "$PREPARE_OUTPUT" == *"$expected"* ]] ||
    fail "output did not contain <$expected>: $PREPARE_OUTPUT"
}

assert_output_equals() {
  local expected="$1"

  [[ "$PREPARE_OUTPUT" == "$expected" ]] ||
    fail "expected output <$expected>, got <$PREPARE_OUTPUT>"
}

assert_worktree_clean() {
  local status

  status="$(git -C "$REPOSITORY" status --short)"
  [[ -z "$status" ]] || fail "expected an unmodified fixture, got: $status"
}

assert_only_owned_files_changed() {
  local changed
  local untracked

  changed="$(git -C "$REPOSITORY" diff --name-only)"
  untracked="$(git -C "$REPOSITORY" ls-files --others --exclude-standard)"
  [[ "$changed" == $'CHANGELOG.md\nSources/UpdateBarCLI/UpdateBarVersion.swift\nversion.env' ]] ||
    fail "version preparation changed the wrong tracked paths: $changed"
  [[ -z "$untracked" ]] || fail "version preparation created unexpected paths: $untracked"
}

owned_fingerprint() {
  shasum -a 256 \
    "$REPOSITORY/version.env" \
    "$REPOSITORY/Sources/UpdateBarCLI/UpdateBarVersion.swift" \
    "$REPOSITORY/CHANGELOG.md"
}

assert_canonical_version_files() {
  local version="$1"
  local expected="$TEMP_ROOT/expected-file"
  local generated_before="$TEMP_ROOT/generated-before.swift"

  printf 'UPDATEBAR_VERSION=%s\n' "$version" > "$expected"
  cmp -s "$expected" "$REPOSITORY/version.env" || fail "version.env is not canonical for $version"

  cat > "$expected" <<EOF
// Generated from version.env by Scripts/generate-version-source.sh.
enum UpdateBarVersion {
    static let current = "$version"
}
EOF
  cmp -s "$expected" "$REPOSITORY/Sources/UpdateBarCLI/UpdateBarVersion.swift" ||
    fail "generated Swift source is not exact for $version"

  cp "$REPOSITORY/Sources/UpdateBarCLI/UpdateBarVersion.swift" "$generated_before"
  (
    cd -- "$REPOSITORY"
    Scripts/generate-version-source.sh
  )
  cmp -s "$generated_before" "$REPOSITORY/Sources/UpdateBarCLI/UpdateBarVersion.swift" ||
    fail 'prepare output does not match generate-version-source.sh'
}

# Bad arguments, release kinds, and refs fail closed without mutation.
create_fixture
make_relevant_head 'invalid invocation'
run_prepare
assert_status 64
assert_output_contains 'Usage:'
assert_worktree_clean

run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" banana
assert_status 65
assert_output_contains 'release kind'
assert_worktree_clean

run_prepare missing-base "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'commit does not exist'
assert_worktree_clean

run_prepare "$BASE_COMMIT" missing-head patch
assert_status 65
assert_output_contains 'commit does not exist'
assert_worktree_clean

# A resolved requested head must be the exact checked-out HEAD.
git -C "$REPOSITORY" checkout --quiet --detach "$BASE_COMMIT"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'does not match requested head'
assert_worktree_clean

# Root Markdown, docs/**, and openspec/** changes are documentation-only.
create_fixture
printf '\nDocumentation update.\n' >> "$REPOSITORY/README.md"
printf '# Root notes\n' > "$REPOSITORY/NOTES.markdown"
mkdir -p "$REPOSITORY/docs/guide" "$REPOSITORY/openspec/changes/example"
printf '# Guide\n' > "$REPOSITORY/docs/guide/index.md"
printf '# Spec\n' > "$REPOSITORY/openspec/changes/example/spec.md"
HEAD_COMMIT="$(commit_all 'docs only')"
DOCS_BEFORE="$(owned_fingerprint)"
OUTPUT_FILE="$TEMP_ROOT/docs-output.env"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" major "$OUTPUT_FILE"
assert_status 0
assert_output_equals $'release=false\nchanged=false\nready=true'
[[ -f "$OUTPUT_FILE" && "$(<"$OUTPUT_FILE")" == "$PREPARE_OUTPUT" ]] ||
  fail 'output file did not exactly match docs-only stdout'
[[ "$(owned_fingerprint)" == "$DOCS_BEFORE" ]] || fail 'docs-only preparation mutated an owned file'
assert_worktree_clean

# Existing output content is preserved while the new result is appended.
EXISTING_OUTPUT="$TEMP_ROOT/docs-existing-output.env"
printf 'existing=value\n' > "$EXISTING_OUTPUT"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" major "$EXISTING_OUTPUT"
assert_status 0
assert_output_equals $'release=false\nchanged=false\nready=true'
[[ "$(<"$EXISTING_OUTPUT")" == $'existing=value\nrelease=false\nchanged=false\nready=true' ]] ||
  fail 'existing output content was not preserved before the docs-only result'
[[ "$(owned_fingerprint)" == "$DOCS_BEFORE" ]] ||
  fail 'appending docs-only output mutated an owned file'

# Docs-only output must reject a symlink alias to any owned artifact.
create_fixture
printf '\nDocumentation alias test.\n' >> "$REPOSITORY/README.md"
HEAD_COMMIT="$(commit_all 'docs output symlink alias')"
OUTPUT_ALIAS="$TEMP_ROOT/owned-output-alias-$FIXTURE_INDEX"
ln -s "$REPOSITORY/CHANGELOG.md" "$OUTPUT_ALIAS"
OUTPUT_ALIAS_BEFORE="$(owned_fingerprint)"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch "$OUTPUT_ALIAS"
[[ "$(owned_fingerprint)" == "$OUTPUT_ALIAS_BEFORE" ]] ||
  fail 'docs-only output symlink alias corrupted an owned artifact'
assert_status 65
assert_output_contains 'output file overlaps owned artifact'

# Lexical aliases to owned files are rejected before docs-only output as well.
create_fixture
printf '\nDocumentation direct output test.\n' >> "$REPOSITORY/README.md"
HEAD_COMMIT="$(commit_all 'docs output direct alias')"
DIRECT_ALIAS_BEFORE="$(owned_fingerprint)"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch "$REPOSITORY/./version.env"
[[ "$(owned_fingerprint)" == "$DIRECT_ALIAS_BEFORE" ]] ||
  fail 'docs-only direct output alias corrupted an owned artifact'
assert_status 65
assert_output_contains 'output file overlaps owned artifact'

# A missing output parent is rejected before release artifacts are mutated.
create_fixture
make_relevant_head 'missing output parent'
MISSING_OUTPUT_PARENT="$TEMP_ROOT/missing-output-parent-$FIXTURE_INDEX"
MISSING_OUTPUT="$MISSING_OUTPUT_PARENT/github-output.env"
MISSING_OUTPUT_BEFORE="$(owned_fingerprint)"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch "$MISSING_OUTPUT"
[[ "$(owned_fingerprint)" == "$MISSING_OUTPUT_BEFORE" ]] ||
  fail 'missing output parent rejection partially mutated an owned file'
assert_status 65
assert_output_contains 'output parent component does not exist'
[[ ! -e "$MISSING_OUTPUT_PARENT" ]] || fail 'output preflight created a missing parent'

# Docs-only preparation applies the same missing-parent preflight.
create_fixture
printf '\nDocumentation missing output parent.\n' >> "$REPOSITORY/README.md"
HEAD_COMMIT="$(commit_all 'docs missing output parent')"
DOCS_MISSING_PARENT="$TEMP_ROOT/docs-missing-output-parent-$FIXTURE_INDEX"
DOCS_MISSING_BEFORE="$(owned_fingerprint)"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch "$DOCS_MISSING_PARENT/github-output.env"
assert_status 65
assert_output_contains 'output parent component does not exist'
[[ "$(owned_fingerprint)" == "$DOCS_MISSING_BEFORE" ]] ||
  fail 'docs-only missing output parent rejection mutated an owned file'
[[ ! -e "$DOCS_MISSING_PARENT" ]] || fail 'docs-only output preflight created a missing parent'

# Every output parent component must be a real directory, not a symlink.
create_fixture
make_relevant_head 'symlinked output parent'
REAL_OUTPUT_PARENT="$TEMP_ROOT/real-output-parent-$FIXTURE_INDEX"
SYMLINKED_OUTPUT_PARENT="$TEMP_ROOT/symlinked-output-parent-$FIXTURE_INDEX"
mkdir -p "$REAL_OUTPUT_PARENT/nested"
ln -s "$REAL_OUTPUT_PARENT" "$SYMLINKED_OUTPUT_PARENT"
SYMLINKED_OUTPUT_BEFORE="$(owned_fingerprint)"
run_prepare \
  "$BASE_COMMIT" \
  "$HEAD_COMMIT" \
  patch \
  "$SYMLINKED_OUTPUT_PARENT/nested/github-output.env"
assert_status 65
assert_output_contains 'output parent component is not a directory or is a symlink'
[[ "$(owned_fingerprint)" == "$SYMLINKED_OUTPUT_BEFORE" ]] ||
  fail 'symlinked output parent rejection partially mutated an owned file'
[[ ! -e "$REAL_OUTPUT_PARENT/nested/github-output.env" ]] ||
  fail 'output preflight followed a symlinked parent'

# A missing output requires a writable immediate parent before release mutation.
create_fixture
make_relevant_head 'non-writable output parent'
NON_WRITABLE_OUTPUT_PARENT="$TEMP_ROOT/non-writable-output-parent-$FIXTURE_INDEX"
mkdir "$NON_WRITABLE_OUTPUT_PARENT"
chmod a-w "$NON_WRITABLE_OUTPUT_PARENT"
NON_WRITABLE_PARENT_BEFORE="$(owned_fingerprint)"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch "$NON_WRITABLE_OUTPUT_PARENT/github-output.env"
chmod u+w "$NON_WRITABLE_OUTPUT_PARENT"
assert_status 65
assert_output_contains 'output parent directory is not writable'
[[ "$(owned_fingerprint)" == "$NON_WRITABLE_PARENT_BEFORE" ]] ||
  fail 'non-writable output parent rejection partially mutated an owned file'
[[ ! -e "$NON_WRITABLE_OUTPUT_PARENT/github-output.env" ]] ||
  fail 'output preflight created a file in a non-writable parent'

# Existing output paths must be writable regular files and never symlinks.
create_fixture
make_relevant_head 'symlinked output file'
OUTPUT_TARGET="$TEMP_ROOT/output-target-$FIXTURE_INDEX"
OUTPUT_SYMLINK="$TEMP_ROOT/output-symlink-$FIXTURE_INDEX"
printf 'target sentinel\n' > "$OUTPUT_TARGET"
ln -s "$OUTPUT_TARGET" "$OUTPUT_SYMLINK"
OUTPUT_SYMLINK_BEFORE="$(owned_fingerprint)"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch "$OUTPUT_SYMLINK"
assert_status 65
assert_output_contains 'output file is not a regular non-symlink file'
[[ "$(owned_fingerprint)" == "$OUTPUT_SYMLINK_BEFORE" ]] ||
  fail 'output symlink rejection partially mutated an owned file'
[[ "$(<"$OUTPUT_TARGET")" == 'target sentinel' ]] || fail 'output preflight followed an output symlink'

create_fixture
make_relevant_head 'non-writable output file'
NON_WRITABLE_OUTPUT="$TEMP_ROOT/non-writable-output-$FIXTURE_INDEX"
printf 'output sentinel\n' > "$NON_WRITABLE_OUTPUT"
chmod a-w "$NON_WRITABLE_OUTPUT"
NON_WRITABLE_OUTPUT_BEFORE="$(owned_fingerprint)"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch "$NON_WRITABLE_OUTPUT"
chmod u+w "$NON_WRITABLE_OUTPUT"
assert_status 65
assert_output_contains 'output file is not writable'
[[ "$(owned_fingerprint)" == "$NON_WRITABLE_OUTPUT_BEFORE" ]] ||
  fail 'non-writable output rejection partially mutated an owned file'
[[ "$(<"$NON_WRITABLE_OUTPUT")" == 'output sentinel' ]] ||
  fail 'output preflight changed a non-writable output file'

# Markdown below a non-docs directory is release-relevant, not a root Markdown path.
create_fixture
printf '# Implementation note\n' > "$REPOSITORY/Sources/Feature/note.md"
HEAD_COMMIT="$(commit_all 'nested source markdown')"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 0
assert_output_equals $'release=true\nchanged=true\nready=false\nversion=1.2.4'
assert_canonical_version_files '1.2.4'

# A real version/source mismatch is repaired to the target generated bytes.
create_fixture
cat > "$REPOSITORY/Sources/UpdateBarCLI/UpdateBarVersion.swift" <<'EOF'
// Generated from version.env by Scripts/generate-version-source.sh.
enum UpdateBarVersion {
    static let current = "7.7.7"
}
EOF
make_relevant_head 'mismatched generated Swift'
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 0
assert_output_equals $'release=true\nchanged=true\nready=false\nversion=1.2.4'
assert_canonical_version_files '1.2.4'
assert_only_owned_files_changed

# First preparation derives patch from the base, moves the Unreleased body, and owns only three paths.
create_fixture
write_version_files '9.9.9'
make_relevant_head 'patch with manual head version'
DATE_BEFORE="$(date -u +%F)"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
DATE_AFTER="$(date -u +%F)"
assert_status 0
assert_output_equals $'release=true\nchanged=true\nready=false\nversion=1.2.4'
assert_canonical_version_files '1.2.4'
PATCH_DATE="$(sed -n 's/^## 1\.2\.4 - \([0-9][0-9-]*\)$/\1/p' "$REPOSITORY/CHANGELOG.md")"
[[ "$PATCH_DATE" == "$DATE_BEFORE" || "$PATCH_DATE" == "$DATE_AFTER" ]] ||
  fail "candidate heading did not use the current UTC date: $PATCH_DATE"
cat > "$TEMP_ROOT/expected-changelog" <<EOF
# Changelog

## Unreleased

## 1.2.4 - $PATCH_DATE

### Added

- Preserve this release note exactly.

## 1.2.3 - 2026-07-20

- Previous release.
EOF
cmp -s "$TEMP_ROOT/expected-changelog" "$REPOSITORY/CHANGELOG.md" ||
  fail 'first preparation did not preserve the Unreleased body exactly'
assert_only_owned_files_changed

# A canonical rerun is idempotent and becomes ready.
PATCH_FINGERPRINT="$(owned_fingerprint)"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 0
assert_output_equals $'release=true\nchanged=false\nready=true\nversion=1.2.4'
[[ "$(owned_fingerprint)" == "$PATCH_FINGERPRINT" ]] || fail 'idempotent rerun changed owned files'

# Changing the label kind replaces only the bot candidate heading and generated versions.
PATCH_CHANGELOG="$(<"$REPOSITORY/CHANGELOG.md")"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" minor
assert_status 0
assert_output_equals $'release=true\nchanged=true\nready=false\nversion=1.3.0'
assert_canonical_version_files '1.3.0'
MINOR_CHANGELOG="$(<"$REPOSITORY/CHANGELOG.md")"
EXPECTED_MINOR_CHANGELOG="$(
  printf '%s\n' "$PATCH_CHANGELOG" |
    sed "s/^## 1\\.2\\.4 - $PATCH_DATE$/## 1.3.0 - $PATCH_DATE/"
)"
if [[ "$MINOR_CHANGELOG" != "$EXPECTED_MINOR_CHANGELOG" ]]; then
  printf '%s\n' "$EXPECTED_MINOR_CHANGELOG" > "$TEMP_ROOT/expected-minor-changelog"
  printf '%s\n' "$MINOR_CHANGELOG" > "$TEMP_ROOT/actual-minor-changelog"
  diff -u "$TEMP_ROOT/expected-minor-changelog" "$TEMP_ROOT/actual-minor-changelog" >&2 || true
  fail 'release-kind change did not preserve the candidate date and body'
fi
assert_only_owned_files_changed

run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" minor
assert_status 0
assert_output_equals $'release=true\nchanged=false\nready=true\nversion=1.3.0'

# Minor and major bumps reset lower components.
create_fixture
make_relevant_head 'minor bump'
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" minor
assert_status 0
assert_output_contains 'version=1.3.0'
assert_canonical_version_files '1.3.0'

create_fixture
make_relevant_head 'major bump'
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" major
assert_status 0
assert_output_contains 'version=2.0.0'
assert_canonical_version_files '2.0.0'

# The base version.env must exist and contain exactly one canonical three-component value.
create_fixture
printf 'UPDATEBAR_VERSION=1.2\n' > "$REPOSITORY/version.env"
BAD_BASE="$(commit_all 'malformed base version')"
write_version_files '1.2.3'
make_relevant_head 'head after malformed base'
run_prepare "$BAD_BASE" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'canonical'
assert_worktree_clean

create_fixture
printf 'UPDATEBAR_VERSION=1.2.3\nUPDATEBAR_VERSION=1.2.3\n' > "$REPOSITORY/version.env"
BAD_BASE="$(commit_all 'duplicate base version')"
write_version_files '1.2.3'
make_relevant_head 'head after duplicate base'
run_prepare "$BAD_BASE" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'canonical'
assert_worktree_clean

create_fixture
git -C "$REPOSITORY" rm --quiet version.env
MISSING_BASE="$(commit_all 'missing base version')"
write_version_files '1.2.3'
make_relevant_head 'head after missing base'
run_prepare "$MISSING_BASE" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'version.env'
assert_worktree_clean

create_fixture
printf 'UPDATEBAR_VERSION=broken\n' > "$REPOSITORY/version.env"
make_relevant_head 'malformed head version'
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'canonical'
assert_worktree_clean

create_fixture
git -C "$REPOSITORY" rm --quiet version.env
make_relevant_head 'missing head version'
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'regular file'
assert_worktree_clean

# Missing, empty, and duplicate Unreleased sections are rejected without partial writes.
create_fixture
sed 's/^## Unreleased$/## Upcoming/' "$REPOSITORY/CHANGELOG.md" > "$TEMP_ROOT/changelog"
mv "$TEMP_ROOT/changelog" "$REPOSITORY/CHANGELOG.md"
make_relevant_head 'missing Unreleased'
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'Unreleased'
assert_worktree_clean

create_fixture
cat > "$REPOSITORY/CHANGELOG.md" <<'EOF'
# Changelog

## Unreleased

## 1.2.3 - 2026-07-20

- Previous release.
EOF
make_relevant_head 'empty Unreleased'
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'empty'
assert_worktree_clean

create_fixture
cat >> "$REPOSITORY/CHANGELOG.md" <<'EOF'

## Unreleased

- Duplicate section.
EOF
make_relevant_head 'duplicate Unreleased'
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'exactly one'
assert_worktree_clean

# Numeric-looking release headings must use an exact bare or dated canonical form.
create_fixture
cat >> "$REPOSITORY/CHANGELOG.md" <<'EOF'

## 1.2.4- 2026-07-21

- Malformed competing release.
EOF
make_relevant_head 'malformed numeric release heading'
MALFORMED_NUMERIC_BEFORE="$(owned_fingerprint)"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'malformed numeric release heading'
[[ "$(owned_fingerprint)" == "$MALFORMED_NUMERIC_BEFORE" ]] ||
  fail 'malformed numeric heading rejection partially mutated an owned file'

create_fixture
cat >> "$REPOSITORY/CHANGELOG.md" <<'EOF'

## 01.2.4 - 2026-07-21

- Noncanonical numeric release.
EOF
make_relevant_head 'noncanonical numeric release heading'
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'malformed numeric release heading'
assert_worktree_clean

# The repository's exact legacy bare release form remains valid.
create_fixture
cat >> "$REPOSITORY/CHANGELOG.md" <<'EOF'

## 0.1.0

- Legacy release.
EOF
make_relevant_head 'legacy bare release heading'
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 0
assert_output_contains 'version=1.2.4'
assert_canonical_version_files '1.2.4'

# Historical release versions must also be unique across level-two headings.
create_fixture
cat >> "$REPOSITORY/CHANGELOG.md" <<'EOF'

## 1.2.3 - 2026-07-21

- Duplicate historical release.
EOF
make_relevant_head 'duplicate historical release heading'
DUPLICATE_HISTORY_BEFORE="$(owned_fingerprint)"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'duplicate release version heading'
[[ "$(owned_fingerprint)" == "$DUPLICATE_HISTORY_BEFORE" ]] ||
  fail 'duplicate historical heading rejection partially mutated an owned file'

# Existing or duplicate bump candidates are ambiguous and never overwritten.
create_fixture
cat >> "$REPOSITORY/CHANGELOG.md" <<'EOF'

## 1.2.4 - 2026-07-21

- Unexpected future release.
EOF
make_relevant_head 'ambiguous first candidate'
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'candidate'
assert_worktree_clean

create_fixture
cat >> "$REPOSITORY/CHANGELOG.md" <<'EOF'

## 1.2.4 - not-a-date

- Malformed future candidate.
EOF
make_relevant_head 'malformed first candidate'
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'malformed numeric release heading'
assert_worktree_clean

create_fixture
make_relevant_head 'duplicate prepared candidate'
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 0
cat >> "$REPOSITORY/CHANGELOG.md" <<EOF

## 1.2.4 - $PATCH_DATE

- Duplicate candidate.
EOF
DUPLICATE_BEFORE="$(owned_fingerprint)"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'duplicate release version heading'
[[ "$(owned_fingerprint)" == "$DUPLICATE_BEFORE" ]] || fail 'candidate rejection partially mutated owned files'

create_fixture
make_relevant_head 'empty prepared candidate'
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 0
EMPTY_CANDIDATE_DATE="$(sed -n 's/^## 1\.2\.4 - \([0-9][0-9-]*\)$/\1/p' "$REPOSITORY/CHANGELOG.md")"
cat > "$REPOSITORY/CHANGELOG.md" <<EOF
# Changelog

## Unreleased

## 1.2.4 - $EMPTY_CANDIDATE_DATE

## 1.2.3 - 2026-07-20

- Previous release.
EOF
EMPTY_CANDIDATE_BEFORE="$(owned_fingerprint)"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'candidate body is empty'
[[ "$(owned_fingerprint)" == "$EMPTY_CANDIDATE_BEFORE" ]] || fail 'empty candidate rejection partially mutated owned files'

# Symlinks and other non-regular owned paths are rejected before writes.
for owned_path in version.env Sources/UpdateBarCLI/UpdateBarVersion.swift CHANGELOG.md; do
  create_fixture
  make_relevant_head "symlink $owned_path"
  OUTSIDE_FILE="$TEMP_ROOT/outside-$FIXTURE_INDEX"
  printf 'outside sentinel\n' > "$OUTSIDE_FILE"
  rm "$REPOSITORY/$owned_path"
  ln -s "$OUTSIDE_FILE" "$REPOSITORY/$owned_path"
  run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
  assert_status 65
  assert_output_contains 'regular file'
  [[ "$(<"$OUTSIDE_FILE")" == 'outside sentinel' ]] || fail "followed unsafe symlink for $owned_path"
done

# A symlinked parent component must not redirect owned writes outside the repository.
create_fixture
make_relevant_head 'symlinked owned parent'
OUTSIDE_PARENT="$TEMP_ROOT/outside-parent-$FIXTURE_INDEX"
mkdir "$OUTSIDE_PARENT"
cp "$REPOSITORY/Sources/UpdateBarCLI/UpdateBarVersion.swift" "$OUTSIDE_PARENT/UpdateBarVersion.swift"
rm "$REPOSITORY/Sources/UpdateBarCLI/UpdateBarVersion.swift"
rmdir "$REPOSITORY/Sources/UpdateBarCLI"
ln -s "$OUTSIDE_PARENT" "$REPOSITORY/Sources/UpdateBarCLI"
PARENT_SYMLINK_BEFORE="$(owned_fingerprint)"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
[[ "$(owned_fingerprint)" == "$PARENT_SYMLINK_BEFORE" ]] ||
  fail 'symlinked parent allowed an owned mutation to escape the repository'
assert_status 65
assert_output_contains 'parent component'

# A non-directory parent component is rejected without touching other owned files.
create_fixture
make_relevant_head 'non-directory owned parent'
rm "$REPOSITORY/Sources/UpdateBarCLI/UpdateBarVersion.swift"
rmdir "$REPOSITORY/Sources/UpdateBarCLI"
printf 'not a directory\n' > "$REPOSITORY/Sources/UpdateBarCLI"
NON_DIRECTORY_PARENT_BEFORE="$(
  shasum -a 256 \
    "$REPOSITORY/version.env" \
    "$REPOSITORY/Sources/UpdateBarCLI" \
    "$REPOSITORY/CHANGELOG.md"
)"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'parent component'
[[ "$(
  shasum -a 256 \
    "$REPOSITORY/version.env" \
    "$REPOSITORY/Sources/UpdateBarCLI" \
    "$REPOSITORY/CHANGELOG.md"
)" == "$NON_DIRECTORY_PARENT_BEFORE" ]] ||
  fail 'non-directory parent rejection mutated an owned path'

create_fixture
make_relevant_head 'directory owned path'
rm "$REPOSITORY/Sources/UpdateBarCLI/UpdateBarVersion.swift"
mkdir "$REPOSITORY/Sources/UpdateBarCLI/UpdateBarVersion.swift"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
assert_output_contains 'regular file'

# A non-writable later artifact is rejected before any earlier artifact changes.
create_fixture
make_relevant_head 'non-writable generated Swift'
NON_WRITABLE_BEFORE="$(owned_fingerprint)"
chmod a-w "$REPOSITORY/Sources/UpdateBarCLI/UpdateBarVersion.swift"
run_prepare "$BASE_COMMIT" "$HEAD_COMMIT" patch
assert_status 65
[[ "$(owned_fingerprint)" == "$NON_WRITABLE_BEFORE" ]] ||
  fail 'non-writable Swift rejection partially mutated an owned file'
assert_output_contains 'Sources/UpdateBarCLI/UpdateBarVersion.swift'

echo 'prepare-pr-version-test: PASS'
