#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SCRIPT_SOURCE="$PROJECT_ROOT/Scripts/plan-release.sh"
GENERATOR_SOURCE="$PROJECT_ROOT/Scripts/generate-version-source.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[[ -f "$SCRIPT_SOURCE" ]] || fail "release planner is missing: $SCRIPT_SOURCE"
[[ -f "$GENERATOR_SOURCE" ]] || fail "version source generator is missing: $GENERATOR_SOURCE"

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/updatebar-plan-release.XXXXXX")"
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
BASE_VERSION=''
PLAN_OUTPUT=''
PLAN_STATUS=0

commit_all() {
  local message="$1"

  git -C "$REPOSITORY" add -A
  git -C "$REPOSITORY" commit --quiet -m "$message"
  git -C "$REPOSITORY" rev-parse HEAD
}

write_version_artifacts() {
  local version="$1"

  mkdir -p "$REPOSITORY/Sources/UpdateBarCLI"
  printf 'UPDATEBAR_VERSION=%s\n' "$version" > "$REPOSITORY/version.env"
  (
    cd -- "$REPOSITORY"
    Scripts/generate-version-source.sh
  )
}

write_base_changelog() {
  local version="$1"

  cat > "$REPOSITORY/CHANGELOG.md" <<EOF
# Changelog

## Unreleased

## $version - 2026-07-20

- Existing release notes.
EOF
}

write_release_changelog() {
  local version="$1"
  local historical_form="${2:-dated}"

  cat > "$REPOSITORY/CHANGELOG.md" <<EOF
# Changelog

## Unreleased

## $version - 2026-07-21

- Release notes for $version.

EOF
  if [[ "$historical_form" == 'bare' ]]; then
    printf '## %s\n' "$BASE_VERSION" >> "$REPOSITORY/CHANGELOG.md"
  else
    printf '## %s - 2026-07-20\n' "$BASE_VERSION" >> "$REPOSITORY/CHANGELOG.md"
  fi
  printf '\n- Existing release notes.\n' >> "$REPOSITORY/CHANGELOG.md"
}

create_fixture() {
  local version="${1:-1.2.3}"

  FIXTURE_INDEX=$((FIXTURE_INDEX + 1))
  REPOSITORY="$TEMP_ROOT/repository-$FIXTURE_INDEX"
  mkdir -p "$REPOSITORY/Scripts" "$REPOSITORY/Sources/UpdateBarCLI" "$REPOSITORY/Sources/Feature"
  cp "$SCRIPT_SOURCE" "$REPOSITORY/Scripts/plan-release.sh"
  cp "$GENERATOR_SOURCE" "$REPOSITORY/Scripts/generate-version-source.sh"
  chmod +x "$REPOSITORY/Scripts/plan-release.sh" "$REPOSITORY/Scripts/generate-version-source.sh"
  git -C "$REPOSITORY" init -q
  git -C "$REPOSITORY" config user.name 'UpdateBar Test'
  git -C "$REPOSITORY" config user.email 'updatebar@example.invalid'
  BASE_VERSION="$version"
  write_version_artifacts "$version"
  write_base_changelog "$version"
  printf 'func fixtureFeature() {}\n' > "$REPOSITORY/Sources/Feature/Feature.swift"
  printf '# UpdateBar\n' > "$REPOSITORY/README.md"
  BASE_COMMIT="$(commit_all 'base')"
  HEAD_COMMIT="$BASE_COMMIT"
}

make_release_head() {
  local version="$1"
  local message="${2:-release $version}"
  local historical_form="${3:-dated}"

  write_version_artifacts "$version"
  write_release_changelog "$version" "$historical_form"
  printf '// %s\n' "$message" >> "$REPOSITORY/Sources/Feature/Feature.swift"
  HEAD_COMMIT="$(commit_all "$message")"
}

run_plan() {
  local executable_path="${PLAN_PATH_OVERRIDE:-$PATH}"

  set +e
  PLAN_OUTPUT="$({
    cd -- "$REPOSITORY"
    PATH="$executable_path" Scripts/plan-release.sh "$@"
  } 2>&1)"
  PLAN_STATUS=$?
  set -e
}

assert_status() {
  local expected="$1"

  [[ "$PLAN_STATUS" -eq "$expected" ]] ||
    fail "expected status $expected, got $PLAN_STATUS: $PLAN_OUTPUT"
}

assert_output_equals() {
  local expected="$1"

  [[ "$PLAN_OUTPUT" == "$expected" ]] ||
    fail "expected output <$expected>, got <$PLAN_OUTPUT>"
}

assert_output_contains() {
  local expected="$1"

  [[ "$PLAN_OUTPUT" == *"$expected"* ]] ||
    fail "output did not contain <$expected>: $PLAN_OUTPUT"
}

assert_clean() {
  local status

  status="$(git -C "$REPOSITORY" status --short)"
  [[ -z "$status" ]] || fail "planner mutated the fixture: $status"
}

assert_release_increase() {
  local base="$1"
  local head="$2"
  local label="$3"

  create_fixture "$base"
  make_release_head "$head" "$label"
  run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
  assert_status 0
  assert_output_equals "release=true
tag=v$head
version=$head"
  assert_clean
}

# Invocation and revision resolution fail closed.
create_fixture
run_plan
assert_status 64
assert_output_contains 'Usage:'
assert_clean

run_plan "$BASE_COMMIT" "$HEAD_COMMIT" one two
assert_status 64
assert_output_contains 'Usage:'
assert_clean

run_plan missing-base "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'commit does not exist'
assert_clean

TREE_OBJECT="$(git -C "$REPOSITORY" rev-parse "$BASE_COMMIT^{tree}")"
run_plan "$TREE_OBJECT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'commit does not exist'
assert_clean

# Base must be an ancestor of head; both reversed and unrelated commits are rejected.
create_fixture
make_release_head '1.2.4' 'ancestry fixture'
run_plan "$HEAD_COMMIT" "$BASE_COMMIT"
assert_status 65
assert_output_contains 'not an ancestor'
assert_clean

UNRELATED_TREE="$(git -C "$REPOSITORY" rev-parse "$BASE_COMMIT^{tree}")"
UNRELATED_COMMIT="$(git -C "$REPOSITORY" commit-tree "$UNRELATED_TREE" -m 'unrelated')"
run_plan "$BASE_COMMIT" "$UNRELATED_COMMIT"
assert_status 65
assert_output_contains 'not an ancestor'
assert_clean

# Root Markdown, docs/**, and openspec/** changes do not require a version change.
create_fixture
printf '\nDocumentation update.\n' >> "$REPOSITORY/README.md"
printf '# Root notes\n' > "$REPOSITORY/NOTES.markdown"
mkdir -p "$REPOSITORY/docs/guide" "$REPOSITORY/openspec/changes/example"
printf '# Guide\n' > "$REPOSITORY/docs/guide/index.md"
printf '# Spec\n' > "$REPOSITORY/openspec/changes/example/spec.md"
HEAD_COMMIT="$(commit_all 'docs only')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 0
assert_output_equals 'release=false'
assert_clean

# Markdown below any other directory remains release-relevant.
create_fixture
write_version_artifacts '1.2.4'
write_release_changelog '1.2.4'
printf '# Source note\n' > "$REPOSITORY/Sources/Feature/note.md"
HEAD_COMMIT="$(commit_all 'nested source markdown')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 0
assert_output_equals $'release=true\ntag=v1.2.4\nversion=1.2.4'
assert_clean

# Patch, minor, major, and arbitrary-size numeric increases are accepted.
assert_release_increase '1.2.3' '1.2.4' 'patch increase'
assert_release_increase '1.2.4' '1.3.0' 'minor increase'
assert_release_increase '1.3.0' '2.0.0' 'major increase'
assert_release_increase \
  '999999999999999999999999999999.9.9' \
  '1000000000000000000000000000000.0.0' \
  'arbitrary-size increase'

# Equal and decreasing versions are rejected for release-relevant changes.
create_fixture
printf '// equal version\n' >> "$REPOSITORY/Sources/Feature/Feature.swift"
HEAD_COMMIT="$(commit_all 'equal version')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'strictly greater'
assert_clean

create_fixture '2.0.0'
make_release_head '1.99.99' 'decreasing version'
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'strictly greater'
assert_clean

# version.env must exist and be one exact, unambiguous canonical line at both revisions.
create_fixture
printf 'UPDATEBAR_VERSION=01.2.3\n' > "$REPOSITORY/version.env"
BASE_COMMIT="$(commit_all 'malformed base version')"
make_release_head '1.2.4' 'head after malformed base'
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'base commit'
assert_output_contains 'canonical'
assert_clean

create_fixture
git -C "$REPOSITORY" rm --quiet version.env
BASE_COMMIT="$(commit_all 'missing base version')"
make_release_head '1.2.4' 'head after missing base'
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'version.env is missing from the base commit'
assert_clean

create_fixture
make_release_head '1.2.4' 'canonical head before malformed version'
printf 'UPDATEBAR_VERSION=1.2.4\nUPDATEBAR_VERSION=1.2.4\n' > "$REPOSITORY/version.env"
HEAD_COMMIT="$(commit_all 'malformed head version')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'head commit'
assert_output_contains 'canonical'
assert_clean

create_fixture
make_release_head '1.2.4' 'canonical head before missing version'
git -C "$REPOSITORY" rm --quiet version.env
HEAD_COMMIT="$(commit_all 'missing head version')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'version.env is missing from the head commit'
assert_clean

# The generated Swift source must exist and byte-match the canonical generator at both revisions.
create_fixture
printf '// drifted base source\n' > "$REPOSITORY/Sources/UpdateBarCLI/UpdateBarVersion.swift"
BASE_COMMIT="$(commit_all 'drifted base source')"
make_release_head '1.2.4' 'head after base source drift'
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'generated version source at the base commit does not match'
assert_clean

create_fixture
git -C "$REPOSITORY" rm --quiet Sources/UpdateBarCLI/UpdateBarVersion.swift
BASE_COMMIT="$(commit_all 'missing base source')"
make_release_head '1.2.4' 'head after missing base source'
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'generated version source is missing from the base commit'
assert_clean

create_fixture
make_release_head '1.2.4' 'canonical head before source drift'
printf '// drifted head source\n' > "$REPOSITORY/Sources/UpdateBarCLI/UpdateBarVersion.swift"
HEAD_COMMIT="$(commit_all 'drifted head source')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'generated version source at the head commit does not match'
assert_clean

create_fixture
make_release_head '1.2.4' 'canonical head before missing source'
git -C "$REPOSITORY" rm --quiet Sources/UpdateBarCLI/UpdateBarVersion.swift
HEAD_COMMIT="$(commit_all 'missing head source')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'generated version source is missing from the head commit'
assert_clean

# The head changelog needs one dated target section with a non-whitespace body.
create_fixture
make_release_head '1.2.4' 'canonical head before missing changelog'
git -C "$REPOSITORY" rm --quiet CHANGELOG.md
HEAD_COMMIT="$(commit_all 'missing changelog')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'CHANGELOG.md is missing from the head commit'
assert_clean

create_fixture
make_release_head '1.2.4' 'canonical head before missing target'
write_base_changelog "$BASE_VERSION"
HEAD_COMMIT="$(commit_all 'missing target heading')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'exactly one dated section for 1.2.4'
assert_clean

create_fixture
make_release_head '1.2.4' 'canonical head before empty target'
cat > "$REPOSITORY/CHANGELOG.md" <<EOF
# Changelog

## Unreleased

## 1.2.4 - 2026-07-21

## $BASE_VERSION - 2026-07-20

- Existing release notes.
EOF
HEAD_COMMIT="$(commit_all 'empty target section')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'section body is empty'
assert_clean

create_fixture
make_release_head '1.2.4' 'canonical head before duplicate target'
cat >> "$REPOSITORY/CHANGELOG.md" <<'EOF'

## 1.2.4 - 2026-07-22

- Duplicate target notes.
EOF
HEAD_COMMIT="$(commit_all 'duplicate target heading')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'duplicate release version heading'
assert_clean

# CommonMark permits up to three leading spaces on an H2; indentation cannot hide a duplicate.
create_fixture
make_release_head '1.2.4' 'canonical head before indented duplicate target'
cat >> "$REPOSITORY/CHANGELOG.md" <<'EOF'

 ## 1.2.4 - 2026-07-22

- Indented duplicate target notes.
EOF
HEAD_COMMIT="$(commit_all 'indented duplicate target heading')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'malformed numeric release heading'
assert_clean

create_fixture
make_release_head '1.2.4' 'canonical head before malformed competitor'
cat >> "$REPOSITORY/CHANGELOG.md" <<'EOF'

## 9.9.9- 2026-07-22

- Malformed competing release.
EOF
HEAD_COMMIT="$(commit_all 'malformed numeric heading')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'malformed numeric release heading'
assert_clean

# Heading-shaped text inside fenced code is not release metadata.
create_fixture
make_release_head '1.2.4' 'canonical head before fenced examples'
cat >> "$REPOSITORY/CHANGELOG.md" <<'EOF'

## Examples

```text
## 9.9.9- 2026-07-22
## 1.2.4 - 2026-07-22
```
EOF
HEAD_COMMIT="$(commit_all 'fenced heading examples')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 0
assert_output_equals $'release=true\ntag=v1.2.4\nversion=1.2.4'
assert_clean

create_fixture
write_version_artifacts '1.2.4'
cat > "$REPOSITORY/CHANGELOG.md" <<EOF
# Changelog

## Unreleased

\`\`\`text
## 1.2.4 - 2026-07-21

- This is only an example.
\`\`\`

## $BASE_VERSION - 2026-07-20

- Existing release notes.
EOF
printf '// fenced target only\n' >> "$REPOSITORY/Sources/Feature/Feature.swift"
HEAD_COMMIT="$(commit_all 'target heading only in fence')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'exactly one dated section for 1.2.4'
assert_clean

create_fixture
make_release_head '1.2.4' 'canonical head before invalid date'
sed 's/## 1\.2\.4 - 2026-07-21/## 1.2.4 - 2026-02-30/' \
  "$REPOSITORY/CHANGELOG.md" > "$TEMP_ROOT/changelog-invalid-date"
mv "$TEMP_ROOT/changelog-invalid-date" "$REPOSITORY/CHANGELOG.md"
HEAD_COMMIT="$(commit_all 'invalid target date')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'malformed release date'
assert_clean

create_fixture
make_release_head '1.2.4' 'canonical head before bare target'
sed 's/## 1\.2\.4 - 2026-07-21/## 1.2.4/' \
  "$REPOSITORY/CHANGELOG.md" > "$TEMP_ROOT/changelog-bare-target"
mv "$TEMP_ROOT/changelog-bare-target" "$REPOSITORY/CHANGELOG.md"
HEAD_COMMIT="$(commit_all 'bare current target')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'bare release heading is not historical'
assert_clean

# A bare version is historical only when it is no newer than the base version.
create_fixture
make_release_head '1.2.4' 'canonical head before future bare heading'
cat > "$REPOSITORY/CHANGELOG.md" <<EOF
# Changelog

## Unreleased

## 9.9.9

- Competing future release.

## 1.2.4 - 2026-07-21

- Release notes for 1.2.4.

## $BASE_VERSION - 2026-07-20

- Existing release notes.
EOF
HEAD_COMMIT="$(commit_all 'future bare release heading')"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 65
assert_output_contains 'bare release heading is not historical'
assert_clean

# Exact legacy bare historical headings remain accepted.
create_fixture
make_release_head '1.2.4' 'legacy historical heading' bare
run_plan "$BASE_COMMIT" "$HEAD_COMMIT"
assert_status 0
assert_output_equals $'release=true\ntag=v1.2.4\nversion=1.2.4'
assert_clean

# Optional output appends without replacing existing data and still mirrors stdout.
create_fixture
make_release_head '1.2.4' 'output append fixture'
EXTERNAL_OUTPUT_DIRECTORY="$TEMP_ROOT/external-output-$FIXTURE_INDEX"
mkdir "$EXTERNAL_OUTPUT_DIRECTORY"
OUTPUT_FILE="$EXTERNAL_OUTPUT_DIRECTORY/github-output.env"
printf 'existing=value\n' > "$OUTPUT_FILE"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT" "$OUTPUT_FILE"
assert_status 0
assert_output_equals $'release=true\ntag=v1.2.4\nversion=1.2.4'
printf 'existing=value\nrelease=true\ntag=v1.2.4\nversion=1.2.4\n' > "$TEMP_ROOT/expected-output"
cmp -s "$TEMP_ROOT/expected-output" "$OUTPUT_FILE" || fail 'output file was not appended exactly'
assert_clean

# An output destination anywhere inside the repository is rejected before opening.
README_BEFORE="$(<"$REPOSITORY/README.md")"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT" "$REPOSITORY/README.md"
assert_status 65
assert_output_contains 'output file must be outside the repository'
[[ "$(<"$REPOSITORY/README.md")" == "$README_BEFORE" ]] || fail 'repository output changed README.md'
assert_clean

# On case-insensitive macOS filesystems, alternate spelling cannot hide repository ancestry.
CASE_VARIANT_REPOSITORY="$TEMP_ROOT/REPOSITORY-$FIXTURE_INDEX"
CASE_VARIANT_README="$CASE_VARIANT_REPOSITORY/readme.MD"
if [[ "$(uname -s)" == 'Darwin' && -f "$CASE_VARIANT_README" ]]; then
  run_plan "$BASE_COMMIT" "$HEAD_COMMIT" "$CASE_VARIANT_README"
  assert_status 65
  assert_output_contains 'output file must be outside the repository'
  [[ "$(<"$REPOSITORY/README.md")" == "$README_BEFORE" ]] ||
    fail 'case-variant repository output changed README.md'
  assert_clean
fi

# An external hard link to a repository file cannot disguise the destination inode.
README_HARDLINK_ALIAS="$TEMP_ROOT/readme-hardlink-$FIXTURE_INDEX"
ln "$REPOSITORY/README.md" "$README_HARDLINK_ALIAS"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT" "$README_HARDLINK_ALIAS"
assert_status 65
assert_output_contains 'exactly one hard link'
[[ "$(<"$REPOSITORY/README.md")" == "$README_BEFORE" ]] || fail 'hard-link output alias changed README.md'
assert_clean

# Direct, hard-link, and symlink aliases to repository metadata are rejected.
VERSION_BEFORE="$(<"$REPOSITORY/version.env")"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT" "$REPOSITORY/./version.env"
assert_status 65
assert_output_contains 'output file overlaps repository artifact'
[[ "$(<"$REPOSITORY/version.env")" == "$VERSION_BEFORE" ]] || fail 'direct output alias changed version.env'
assert_clean

HARDLINK_ALIAS="$TEMP_ROOT/version-hardlink-$FIXTURE_INDEX"
ln "$REPOSITORY/version.env" "$HARDLINK_ALIAS"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT" "$HARDLINK_ALIAS"
assert_status 65
assert_output_contains 'output file overlaps repository artifact'
[[ "$(<"$REPOSITORY/version.env")" == "$VERSION_BEFORE" ]] || fail 'hard-link output alias changed version.env'
assert_clean

EXTERNAL_TARGET="$TEMP_ROOT/external-output-target-$FIXTURE_INDEX"
SYMLINK_ENDPOINT="$TEMP_ROOT/symlink-output-$FIXTURE_INDEX"
printf 'external sentinel\n' > "$EXTERNAL_TARGET"
ln -s "$EXTERNAL_TARGET" "$SYMLINK_ENDPOINT"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT" "$SYMLINK_ENDPOINT"
assert_status 65
assert_output_contains 'regular non-symlink file'
[[ "$(<"$EXTERNAL_TARGET")" == 'external sentinel' ]] || fail 'output endpoint symlink was followed'
assert_clean

# Missing and symlinked output parents are rejected without creating an output.
MISSING_PARENT="$TEMP_ROOT/missing-parent-$FIXTURE_INDEX"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT" "$MISSING_PARENT/github-output.env"
assert_status 65
assert_output_contains 'output parent component does not exist'
[[ ! -e "$MISSING_PARENT" ]] || fail 'planner created a missing output parent'
assert_clean

REAL_PARENT="$TEMP_ROOT/real-parent-$FIXTURE_INDEX"
SYMLINK_PARENT="$TEMP_ROOT/symlink-parent-$FIXTURE_INDEX"
mkdir "$REAL_PARENT"
ln -s "$REAL_PARENT" "$SYMLINK_PARENT"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT" "$SYMLINK_PARENT/github-output.env"
assert_status 65
assert_output_contains 'output parent component is not a directory or is a symlink'
[[ ! -e "$REAL_PARENT/github-output.env" ]] || fail 'planner followed an output parent symlink'
assert_clean

# Renaming the validated output pathname cannot redirect the eventual write.
SWAP_GIT_DIRECTORY="$TEMP_ROOT/swap-git-$FIXTURE_INDEX"
mkdir "$SWAP_GIT_DIRECTORY"
cat > "$SWAP_GIT_DIRECTORY/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == 'diff' ]]; then
  mv -- "$SWAP_OUTPUT_PATH" "$SWAP_PRESERVED_OUTPUT"
  ln -s -- "$SWAP_TARGET_PATH" "$SWAP_OUTPUT_PATH"
fi

exec "$REAL_GIT_BINARY" "$@"
EOF
chmod +x "$SWAP_GIT_DIRECTORY/git"
REAL_GIT_BINARY="$(command -v git)"
SWAP_OUTPUT_PATH="$TEMP_ROOT/swap-output-$FIXTURE_INDEX.env"
SWAP_PRESERVED_OUTPUT="$TEMP_ROOT/swap-output-preserved-$FIXTURE_INDEX.env"
SWAP_TARGET_PATH="$REPOSITORY/version.env"
printf 'existing=value\n' > "$SWAP_OUTPUT_PATH"
export REAL_GIT_BINARY SWAP_OUTPUT_PATH SWAP_PRESERVED_OUTPUT SWAP_TARGET_PATH
PLAN_PATH_OVERRIDE="$SWAP_GIT_DIRECTORY:$PATH"
run_plan "$BASE_COMMIT" "$HEAD_COMMIT" "$SWAP_OUTPUT_PATH"
unset PLAN_PATH_OVERRIDE
assert_status 0
assert_output_equals $'release=true\ntag=v1.2.4\nversion=1.2.4'
printf 'existing=value\nrelease=true\ntag=v1.2.4\nversion=1.2.4\n' > "$TEMP_ROOT/expected-preserved-output"
cmp -s "$TEMP_ROOT/expected-preserved-output" "$SWAP_PRESERVED_OUTPUT" ||
  fail 'held output descriptor did not receive the result after rename'
[[ "$(<"$REPOSITORY/version.env")" == "$VERSION_BEFORE" ]] ||
  fail 'renamed output pathname redirected the result into version.env'
assert_clean
unset REAL_GIT_BINARY SWAP_OUTPUT_PATH SWAP_PRESERVED_OUTPUT SWAP_TARGET_PATH

echo 'plan-release-test: PASS'
