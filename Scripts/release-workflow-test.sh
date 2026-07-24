#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/release.yml"
[[ -f "$WORKFLOW" ]] || { echo "release workflow is missing" >&2; exit 1; }

ruby -rpsych - "$WORKFLOW" <<'RUBY'
workflow = Psych.safe_load(File.binread(ARGV.fetch(0)), permitted_classes: [], permitted_symbols: [], aliases: false)

def assert(value, message)
  raise "FAIL: #{message}" unless value
end

def step_map(job)
  grouped = job.fetch("steps").group_by { |step| step["name"] }
  assert(grouped.none? { |name, entries| name.nil? || entries.length != 1 }, "step names must be present and unique")
  grouped.transform_values(&:first)
end

def copy(value)
  Marshal.load(Marshal.dump(value))
end

def move_step(job, name, before_name)
  steps = job.fetch("steps")
  moving = steps.delete_at(steps.index { |step| step["name"] == name })
  steps.insert(steps.index { |step| step["name"] == before_name }, moving)
end

def assert_commit_checkout(job, needs_expression, label, fetch_depth)
  checkout = step_map(job).fetch("Checkout verified release commit")
  assert(checkout["uses"] == "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", "#{label} checkout must use the reviewed SHA")
  assert(checkout["with"] == {
    "ref" => needs_expression, "fetch-depth" => fetch_depth, "persist-credentials" => false
  }, "#{label} must check out only the singleton verified commit")
end

def assert_commit_check(job, expression, label)
  step = step_map(job).fetch("Verify release commit")
  assert(step.dig("env", "VERIFIED_RELEASE_COMMIT") == expression, "#{label} commit check must receive singleton provenance")
  run = step.fetch("run")
  assert(run.include?('head_commit="$(git rev-parse HEAD)"') &&
    run.include?('[[ "$head_commit" != "$VERIFIED_RELEASE_COMMIT" ]]') &&
    run.include?('^([0-9a-f]{40})$'), "#{label} must compare canonical HEAD with singleton provenance")
end

def validate(workflow)
  assert(workflow["name"] == "Release", "workflow name must remain Release")
  triggers = workflow["on"]
  assert(triggers.is_a?(Hash) && triggers.keys.sort == %w[push workflow_dispatch], "only tag push and manual recovery may trigger")
  assert(triggers.dig("push", "tags") == ["v*"], "push trigger must be version tags")
  manual = triggers.dig("workflow_dispatch", "inputs", "tag")
  assert(manual.is_a?(Hash) && manual["required"] == true && manual["type"] == "string", "manual recovery must require an exact tag")
  assert(workflow["permissions"] == { "contents" => "read" }, "workflow default must be read-only")
  assert(workflow["concurrency"] == { "group" => "updatebar-release", "queue" => "max", "cancel-in-progress" => false }, "release concurrency must preserve the full non-cancelling tag queue")
  assert(!workflow.to_s.match?(/re[- ]?run all/i), "recovery must not promise an all-jobs rerun that could replace immutable bytes")

  jobs = workflow.fetch("jobs")
  assert(jobs.keys == %w[provenance verify package publish notify], "graph must be provenance, verify, protected package, protected publish, notify")
  jobs.each_value do |job|
    job.fetch("steps").each do |step|
      next unless step.key?("uses")
      assert(step.fetch("uses").match?(/\A[^@]+@[0-9a-f]{40}\z/), "all external actions must use reviewed full SHAs")
    end
  end
  %w[softprops/action-gh-release NOTARY_APPLE_ID NOTARY_PASSWORD MACOS_SIGNING_CERT_P12].each do |retired|
    assert(!workflow.to_s.include?(retired), "retired release path must be absent: #{retired}")
  end

  provenance = jobs.fetch("provenance")
  verify = jobs.fetch("verify")
  package = jobs.fetch("package")
  publish = jobs.fetch("publish")
  notify = jobs.fetch("notify")
  commit_output = "${{ needs.provenance.outputs.release_commit }}"

  assert(!provenance.key?("strategy"), "provenance must be a singleton, never a matrix")
  assert(provenance["runs-on"] == "ubuntu-24.04", "provenance must use the pinned Linux runner")
  assert(provenance["permissions"] == { "contents" => "read" }, "provenance must be read-only")
  assert(!provenance.key?("environment") && !provenance.to_s.include?("secrets."), "provenance must not enter production scope")
  assert(provenance.dig("outputs", "release_commit") == "${{ steps.provenance.outputs.release_commit }}", "singleton must expose the only release commit output")
  assert(provenance.dig("env", "RELEASE_TAG") == "${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}", "singleton must resolve push and recovery tags")
  assert(provenance.fetch("steps").map { |step| step["name"] } == ["Checkout release tag", "Validate release provenance"], "singleton provenance steps must be exact")
  provenance_steps = step_map(provenance)
  provenance_checkout = provenance_steps.fetch("Checkout release tag")
  assert(provenance_checkout["with"] == {
    "ref" => "refs/tags/${{ env.RELEASE_TAG }}", "fetch-depth" => 0, "persist-credentials" => false
  }, "singleton provenance must initially check out the exact tag ref")
  provenance_run = provenance_steps.fetch("Validate release provenance").fetch("run")
  ["refs/tags/$RELEASE_TAG", "git show-ref --verify --quiet", "refs/heads/main:",
   "refs/tags/$RELEASE_TAG:", "git merge-base --is-ancestor", "^UPDATEBAR_VERSION=",
   "^([0-9a-f]{40})$", "release_commit=%s"].each do |fragment|
    assert(provenance_run.include?(fragment), "singleton provenance is missing #{fragment}")
  end
  assert(provenance_run.index("git fetch") < provenance_run.index("git merge-base --is-ancestor"), "remote refs must be fetched before ancestry validation")

  assert(verify["needs"] == "provenance", "matrix verification must consume singleton provenance")
  assert(!verify.key?("outputs"), "matrix verification must never expose a last-matrix release commit")
  assert(verify["strategy"] == {
    "fail-fast" => false,
    "matrix" => { "include" => [
      { "os" => "macos-15", "artifact" => "macos-arm64" },
      { "os" => "ubuntu-24.04", "artifact" => "linux-x86_64" }
    ] }
  }, "verification matrix must pin both runners")
  assert(verify["runs-on"] == "${{ matrix.os }}" && verify["permissions"] == { "contents" => "read" }, "matrix verification must be pinned and read-only")
  assert(!verify.key?("environment") && !verify.to_s.include?("secrets."), "matrix verification must not receive release secrets")
  expected_verify = ["Checkout verified release commit", "Verify release commit", "Setup Swift on Linux",
    "Install Linux link dependencies", "Run Swift tests", "Build CLI archive", "Smoke-test CLI archive",
    "Verify checksums", "Write artifact provenance marker", "Upload CLI artifact"]
  assert(verify.fetch("steps").map { |step| step["name"] } == expected_verify, "matrix verification steps must be exact and ordered")
  assert_commit_checkout(verify, commit_output, "verify", 0)
  assert_commit_check(verify, commit_output, "verify")
  verify_steps = step_map(verify)
  marker = verify_steps.fetch("Write artifact provenance marker")
  assert(marker["env"] == { "VERIFIED_RELEASE_COMMIT" => commit_output, "ARTIFACT_LABEL" => "${{ matrix.artifact }}" }, "marker must bind singleton provenance to its matrix artifact")
  marker_run = marker.fetch("run")
  ["archive_sha", "archive_name", "VERIFIED_RELEASE_COMMIT", "release-marker", "printf '%s  %s  %s\\n'"].each do |fragment|
    assert(marker_run.include?(fragment), "artifact marker is missing #{fragment}")
  end
  upload = verify_steps.fetch("Upload CLI artifact")
  assert(upload["uses"] == "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02", "CLI upload must use reviewed SHA")
  assert(upload.dig("with", "path").include?("release-marker"), "each CLI artifact must carry its provenance marker")
  assert(upload.dig("with", "retention-days") == 7, "intermediate CLI artifacts must keep their short retention")
  assert(!verify.to_s.match?(/build-app|generate-appcast|publish-release|R2_ACCESS/i), "verify must not package or publish")

  assert(package["needs"] == ["provenance", "verify"], "package must wait for singleton provenance and the whole matrix")
  assert(package["environment"] == "release" && package["runs-on"] == "macos-15", "package must be protected on canonical macOS")
  assert(package["permissions"] == { "contents" => "read" }, "package needs no repository write permission")
  assert(!package.key?("if"), "workflow_dispatch and tag pushes must both package")
  expected_package = ["Checkout verified release commit", "Verify release commit", "Download verified CLI artifacts",
    "Verify downloaded checksums", "Prepare signing workspace", "Install Apple credentials",
    "Build notarized app DMG", "Smoke-test app DMG", "Generate signed appcast", "Generate release manifest",
    "Stage immutable release bundle", "Upload immutable release bundle for failed-job retry", "Cleanup Apple credentials"]
  assert(package.fetch("steps").map { |step| step["name"] } == expected_package, "protected package steps must be exact and ordered")
  assert_commit_checkout(package, commit_output, "package", 0)
  assert_commit_check(package, commit_output, "package")
  package_steps = step_map(package)
  cli_download = package_steps.fetch("Download verified CLI artifacts")
  assert(cli_download["with"] == { "pattern" => "updatebar-*", "path" => "dist", "merge-multiple" => true }, "package must download only matrix CLI artifacts")
  marker_validation = package_steps.fetch("Verify downloaded checksums")
  assert(marker_validation.dig("env", "VERIFIED_RELEASE_COMMIT") == commit_output, "marker validation must use singleton provenance")
  marker_validation_run = marker_validation.fetch("run")
  %w[macos-arm64 linux-x86_64 release-marker Dir.children expected_file marker_commit marker_sha archive_sha].each do |fragment|
    assert(marker_validation_run.include?(fragment), "package marker validation is missing #{fragment}")
  end
  assert(marker_validation_run.include?('for expected_file in "${expected_files[@]}"') &&
    marker_validation_run.include?('-L "dist/$expected_file"'), "package must reject unsafe CLI artifact entry types")
  apple_names = %w[APPLE_CERTIFICATE_P12_BASE64 APPLE_CERTIFICATE_PASSWORD APPLE_NOTARY_KEY_P8_BASE64 APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID]
  credentials = package_steps.fetch("Install Apple credentials")
  apple_names.each do |name|
    assert(credentials.dig("env", name) == "${{ secrets.#{name} }}", "package is missing #{name}")
    assert(credentials.fetch("run").include?("${#{name}:?"), "package must fail closed for #{name}")
  end
  assert(package_steps.fetch("Build notarized app DMG")["env"] == {
    "DEVELOPER_ID_APPLICATION" => "${{ vars.DEVELOPER_ID_APPLICATION }}",
    "SPARKLE_PUBLIC_ED_KEY" => "${{ vars.SPARKLE_PUBLIC_ED_KEY }}"
  }, "DMG build must receive only public signing settings")
  appcast = package_steps.fetch("Generate signed appcast")
  assert(appcast.dig("env", "SPARKLE_PRIVATE_ED_KEY") == "${{ secrets.SPARKLE_PRIVATE_ED_KEY }}", "only package may receive the UpdateBar Sparkle private key")
  assert(appcast.dig("env", "UPDATE_DOMAIN") == "updates.updatebar.sonim1.com", "appcast domain must be fixed")
  assert(package_steps.fetch("Generate release manifest")["run"] == 'Scripts/generate-release-manifest.sh "$RELEASE_TAG"', "manifest must bind the exact tag")
  stage = package_steps.fetch("Stage immutable release bundle").fetch("run")
  %w[release-bundle release-commit.txt bundle-sha256.txt dist/updates release-manifest.json].each do |fragment|
    assert(stage.include?(fragment), "immutable bundle staging is missing #{fragment}")
  end
  bundle_upload = package_steps.fetch("Upload immutable release bundle for failed-job retry")
  assert(bundle_upload["uses"] == "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02", "bundle upload must use reviewed SHA")
  assert(bundle_upload["with"] == {
    "name" => "updatebar-release-${{ env.RELEASE_TAG }}", "path" => "release-bundle/",
    "if-no-files-found" => "error", "retention-days" => 30, "include-hidden-files" => false
  }, "one immutable bundle must remain available for the full failed-job rerun window")
  assert(!package.to_s.match?(/publish-release|R2_ACCESS|CLOUDFLARE_ACCOUNT_ID|GH_TOKEN|create-github-app-token/), "package must never perform external publication")
  assert(!package.to_s.include?("setup-node") && !package.to_s.include?("npm ci"), "package does not need Node or Wrangler")
  cleanup = package_steps.fetch("Cleanup Apple credentials")
  assert(cleanup["if"] == "always()" && !cleanup.fetch("run").match?(/rm\s+-rf|rm\s+-f\s+[^\n]*[*?]/), "package cleanup must always stay within validated paths")

  assert(publish["needs"] == ["provenance", "package"], "publish must consume only singleton provenance and the completed bundle")
  assert(publish["environment"] == "release" && publish["runs-on"] == "macos-15", "publish must remain protected on macOS for DMG verification")
  assert(publish["permissions"] == { "contents" => "write" }, "only publish receives repository write")
  expected_publish = ["Checkout verified release commit", "Verify release commit", "Download immutable release bundle",
    "Validate immutable release bundle", "Materialize immutable release bundle", "Publish release"]
  assert(publish.fetch("steps").map { |step| step["name"] } == expected_publish, "publish steps must only validate and publish the immutable bundle")
  assert_commit_checkout(publish, commit_output, "publish", 0)
  assert_commit_check(publish, commit_output, "publish")
  publish_steps = step_map(publish)
  bundle_download = publish_steps.fetch("Download immutable release bundle")
  assert(bundle_download["with"] == { "name" => "updatebar-release-${{ env.RELEASE_TAG }}", "path" => "${{ runner.temp }}/updatebar-release-bundle" }, "publish must download exactly the completed bundle")
  bundle_validation = publish_steps.fetch("Validate immutable release bundle")
  assert(bundle_validation.dig("env", "VERIFIED_RELEASE_COMMIT") == commit_output, "bundle validation must bind singleton provenance")
  %w[release-commit.txt bundle-sha256.txt Dir.glob expected_dirs File.symlink? checksum_names shasum release-manifest.json dist/updates].each do |fragment|
    assert(bundle_validation.fetch("run").include?(fragment), "bundle validation is missing #{fragment}")
  end
  publication = publish_steps.fetch("Publish release")
  assert(publication["env"] == {
    "GH_TOKEN" => "${{ github.token }}", "CLOUDFLARE_ACCOUNT_ID" => "${{ vars.CLOUDFLARE_ACCOUNT_ID }}",
    "R2_ACCESS_KEY_ID" => "${{ secrets.R2_ACCESS_KEY_ID }}", "R2_SECRET_ACCESS_KEY" => "${{ secrets.R2_SECRET_ACCESS_KEY }}",
    "R2_BUCKET_NAME" => "updatebar-updates", "UPDATE_DOMAIN" => "updates.updatebar.sonim1.com"
  }, "publish must use only release publication credentials and fixed destinations")
  assert(publication["run"] == 'Scripts/publish-release.sh "$RELEASE_TAG"', "publish must call the coordinator exactly once")
  assert(!publish.to_s.match?(/build-app|generate-appcast|generate-release-manifest|APPLE_CERTIFICATE|APPLE_NOTARY|SPARKLE_PRIVATE|setup-node|npm ci/), "failed publish reruns must never rebuild, sign, notarize, or regenerate")
  assert(!publish.to_s.include?("create-github-app-token"), "tap token must not enter publish")

  assert(notify["needs"] == ["provenance", "publish"], "notify must wait for singleton provenance and publication")
  assert(notify["environment"] == "release" && notify["runs-on"] == "ubuntu-24.04", "notify must be isolated and protected")
  assert(notify["permissions"] == { "contents" => "read" }, "notify must be read-only")
  assert_commit_checkout(notify, commit_output, "notify", 1)
  assert_commit_check(notify, commit_output, "notify")
  notify_steps = step_map(notify)
  assert(notify.fetch("steps").map { |step| step["name"] } == ["Checkout verified release commit", "Verify release commit", "Create tap GitHub App token", "Notify Homebrew tap"], "notify steps must stay retryable and isolated")
  token = notify_steps.fetch("Create tap GitHub App token")
  assert(token["uses"] == "actions/create-github-app-token@67018539274d69449ef7c02e8e71183d1719ab42", "tap token action must use reviewed SHA")
  assert(token["with"] == { "app-id" => "${{ vars.TAP_GITHUB_APP_ID }}", "private-key" => "${{ secrets.TAP_GITHUB_APP_PRIVATE_KEY }}", "owner" => "sonim1", "repositories" => "homebrew-tap", "permission-contents" => "write" }, "tap token must be scoped to homebrew-tap contents write")
  assert(notify_steps.fetch("Notify Homebrew tap")["run"] == 'Scripts/dispatch-homebrew-update.sh "$RELEASE_TAG"', "notify must dispatch the exact published tag")
  assert(!notify.to_s.match?(/build-app|generate-appcast|publish-release|R2_ACCESS|APPLE_CERTIFICATE/), "notify must not rebuild or republish")
end

validate(workflow)

mutations = {}
mutations["release queue is removed"] = copy(workflow).tap { |w| w["concurrency"].delete("queue") }
mutations["release queue replaces pending tags"] = copy(workflow).tap { |w| w["concurrency"]["queue"] = "single" }
mutations["singleton becomes matrix"] = copy(workflow).tap { |w| w["jobs"]["provenance"]["strategy"] = { "matrix" => { "os" => ["ubuntu-24.04"] } } }
mutations["last matrix output becomes authoritative"] = copy(workflow).tap { |w| w["jobs"]["verify"]["outputs"] = { "release_commit" => "${{ steps.commit.outputs.value }}" } }
mutations["verify uses a movable tag"] = copy(workflow).tap { |w| step_map(w["jobs"]["verify"]).fetch("Checkout verified release commit")["with"]["ref"] = "refs/tags/${{ env.RELEASE_TAG }}" }
mutations["matrix marker is removed"] = copy(workflow).tap { |w| w["jobs"]["verify"]["steps"].reject! { |step| step["name"] == "Write artifact provenance marker" } }
mutations["package stops comparing marker commit"] = copy(workflow).tap do |w|
  step = step_map(w["jobs"]["package"]).fetch("Verify downloaded checksums")
  step["run"] = step["run"].gsub("marker_commit", "ignored_commit")
end
mutations["package publishes externally"] = copy(workflow).tap do |w|
  w["jobs"]["package"]["steps"].insert(-1, { "name" => "Publish release", "run" => 'Scripts/publish-release.sh "$RELEASE_TAG"' })
end
mutations["bundle upload moves after publication"] = copy(workflow).tap do |w|
  w["jobs"]["publish"]["steps"].insert(-1, copy(step_map(w["jobs"]["package"]).fetch("Upload immutable release bundle for failed-job retry")))
end
mutations["publish rebuilds the DMG"] = copy(workflow).tap { |w| w["jobs"]["publish"]["steps"].insert(-1, { "name" => "Build notarized app DMG", "run" => "Scripts/build-app-dmg.sh" }) }
mutations["publish bypasses singleton"] = copy(workflow).tap { |w| w["jobs"]["publish"]["needs"] = ["package"] }
mutations["bundle download is broad"] = copy(workflow).tap { |w| step_map(w["jobs"]["publish"]).fetch("Download immutable release bundle")["with"].delete("name") }
mutations["Apple secret becomes optional"] = copy(workflow).tap do |w|
  step = step_map(w["jobs"]["package"]).fetch("Install Apple credentials")
  step["run"] = step["run"].gsub('${APPLE_CERTIFICATE_PASSWORD:?', '${APPLE_CERTIFICATE_PASSWORD:-')
end
mutations["checkout credentials persist"] = copy(workflow).tap { |w| step_map(w["jobs"]["package"]).fetch("Checkout verified release commit")["with"]["persist-credentials"] = true }
mutations["notify is merged away"] = copy(workflow).tap { |w| w["jobs"].delete("notify") }
mutations["cleanup becomes recursive"] = copy(workflow).tap { |w| step_map(w["jobs"]["package"]).fetch("Cleanup Apple credentials")["run"] << "\nrm -rf \"$RUNNER_TEMP\"\n" }

mutations.each do |label, mutation|
  begin
    validate(mutation)
  rescue RuntimeError => error
    raise unless error.message.start_with?("FAIL:")
  else
    raise "FAIL: workflow contract accepted mutation: #{label}"
  end
end

puts "release workflow structure and mutation tests passed"
RUBY

extract_run() {
  ruby -rpsych - "$WORKFLOW" "$1" "$2" <<'RUBY'
workflow = Psych.safe_load(File.binread(ARGV.fetch(0)), permitted_classes: [], permitted_symbols: [], aliases: false)
steps = workflow.fetch("jobs").fetch(ARGV.fetch(1)).fetch("steps")
matches = steps.select { |step| step["name"] == ARGV.fetch(2) }
abort "expected exactly one step" unless matches.length == 1 && matches.first["run"].is_a?(String)
print matches.first["run"]
RUBY
}

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/updatebar-workflow-contract.XXXXXX")"
cleanup_fixture() { rm -rf "$FIXTURE"; }
trap cleanup_fixture EXIT

PROVENANCE_RUN="$(extract_run provenance "Validate release provenance")"
git init --bare "$FIXTURE/origin.git" >/dev/null
git init "$FIXTURE/source" >/dev/null
git -C "$FIXTURE/source" config user.name "Release Contract"
git -C "$FIXTURE/source" config user.email "release-contract@example.invalid"
printf 'UPDATEBAR_VERSION=1.2.3\n' > "$FIXTURE/source/version.env"
git -C "$FIXTURE/source" add version.env
git -C "$FIXTURE/source" commit -m "release fixture" >/dev/null
git -C "$FIXTURE/source" branch -M main
git -C "$FIXTURE/source" tag v1.2.3
git -C "$FIXTURE/source" remote add origin "$FIXTURE/origin.git"
git -C "$FIXTURE/source" push origin main refs/tags/v1.2.3 >/dev/null 2>&1
git clone "$FIXTURE/origin.git" "$FIXTURE/checkout" >/dev/null 2>&1
git -C "$FIXTURE/checkout" checkout --detach refs/tags/v1.2.3 >/dev/null 2>&1
: > "$FIXTURE/github-output"
(
  cd "$FIXTURE/checkout"
  RELEASE_TAG=v1.2.3 GITHUB_OUTPUT="$FIXTURE/github-output" bash -euo pipefail -c "$PROVENANCE_RUN"
) >/dev/null 2>&1
EXPECTED_COMMIT="$(git -C "$FIXTURE/source" rev-parse refs/tags/v1.2.3^{commit})"
[[ "$(<"$FIXTURE/github-output")" == "release_commit=$EXPECTED_COMMIT" ]] || { echo "singleton provenance emitted the wrong commit" >&2; exit 1; }

git -C "$FIXTURE/source" checkout --orphan off-main >/dev/null 2>&1
git -C "$FIXTURE/source" rm -f version.env >/dev/null
printf 'UPDATEBAR_VERSION=1.2.4\n' > "$FIXTURE/source/version.env"
git -C "$FIXTURE/source" add version.env
git -C "$FIXTURE/source" commit -m "off-main release fixture" >/dev/null
git -C "$FIXTURE/source" tag v1.2.4
git -C "$FIXTURE/source" push origin refs/tags/v1.2.4 >/dev/null 2>&1
git -C "$FIXTURE/checkout" fetch --no-tags origin refs/tags/v1.2.4:refs/tags/v1.2.4 >/dev/null 2>&1
git -C "$FIXTURE/checkout" checkout --detach refs/tags/v1.2.4 >/dev/null 2>&1
if (cd "$FIXTURE/checkout" && RELEASE_TAG=v1.2.4 GITHUB_OUTPUT="$FIXTURE/github-output" bash -euo pipefail -c "$PROVENANCE_RUN") >/dev/null 2>&1; then
  echo "singleton provenance accepted an off-main movable tag" >&2
  exit 1
fi

MARKER_RUN="$(extract_run verify "Write artifact provenance marker")"
mkdir -p "$FIXTURE/marker/dist"
printf 'archive bytes\n' > "$FIXTURE/marker/dist/updatebar-1.2.3-macos-arm64.tar.gz"
(
  cd "$FIXTURE/marker"
  (cd dist && shasum -a 256 updatebar-1.2.3-macos-arm64.tar.gz > updatebar-1.2.3-macos-arm64.tar.gz.sha256)
  VERIFIED_RELEASE_COMMIT="$EXPECTED_COMMIT" ARTIFACT_LABEL=macos-arm64 bash -euo pipefail -c "$MARKER_RUN"
)
MARKER_LINE="$(<"$FIXTURE/marker/dist/updatebar-macos-arm64.release-marker")"
[[ "$MARKER_LINE" == "$EXPECTED_COMMIT  "*"  updatebar-1.2.3-macos-arm64.tar.gz" ]] || { echo "matrix marker did not bind commit, checksum, and archive" >&2; exit 1; }

BUNDLE_RUN="$(extract_run publish "Validate immutable release bundle")"
BUNDLE_CHECKOUT="$FIXTURE/bundle-checkout"
BUNDLE_ROOT="$FIXTURE/runner/updatebar-release-bundle"
mkdir -p "$BUNDLE_CHECKOUT" "$BUNDLE_ROOT/dist/updates"
printf 'UPDATEBAR_VERSION=1.2.3\n' > "$BUNDLE_CHECKOUT/version.env"
bundle_files=(
  dist/updatebar-1.2.3-macos-arm64.tar.gz
  dist/updatebar-1.2.3-macos-arm64.tar.gz.sha256
  dist/updatebar-1.2.3-linux-x86_64.tar.gz
  dist/updatebar-1.2.3-linux-x86_64.tar.gz.sha256
  dist/UpdateBar-1.2.3-macos-arm64.dmg
  dist/UpdateBar-1.2.3-macos-arm64.dmg.sha256
  dist/release-manifest.json
  dist/updates/UpdateBar-1.2.3-macos-arm64.dmg
  dist/updates/UpdateBar-1.2.3-macos-arm64.dmg.sha256
  dist/updates/appcast.xml
)
for bundle_file in "${bundle_files[@]}"; do
  printf 'fixture: %s\n' "$bundle_file" > "$BUNDLE_ROOT/$bundle_file"
done
printf '{"commit":"%s"}\n' "$EXPECTED_COMMIT" > "$BUNDLE_ROOT/dist/release-manifest.json"
printf '%s\n' "$EXPECTED_COMMIT" > "$BUNDLE_ROOT/release-commit.txt"
(
  cd "$BUNDLE_ROOT"
  shasum -a 256 release-commit.txt "${bundle_files[@]}" > bundle-sha256.txt
)
(
  cd "$BUNDLE_CHECKOUT"
  RUNNER_TEMP="$FIXTURE/runner" VERIFIED_RELEASE_COMMIT="$EXPECTED_COMMIT" bash -euo pipefail -c "$BUNDLE_RUN"
) >/dev/null
printf 'unexpected\n' > "$BUNDLE_ROOT/dist/unexpected"
if (
  cd "$BUNDLE_CHECKOUT"
  RUNNER_TEMP="$FIXTURE/runner" VERIFIED_RELEASE_COMMIT="$EXPECTED_COMMIT" bash -euo pipefail -c "$BUNDLE_RUN"
) >/dev/null 2>&1; then
  echo "immutable bundle validation accepted an extra file" >&2
  exit 1
fi

echo "release workflow tests passed"
