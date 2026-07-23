#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/release.yml"

[[ -f "$WORKFLOW" ]] || { echo "release workflow is missing" >&2; exit 1; }

ruby -rpsych - "$WORKFLOW" <<'RUBY'
path = ARGV.fetch(0)
source = File.binread(path)
workflow = Psych.safe_load(source, permitted_classes: [], permitted_symbols: [], aliases: false)

def assert(value, message)
  raise "FAIL: #{message}" unless value
end

def step_map(job)
  steps = job.fetch("steps")
  grouped = steps.group_by { |step| step["name"] }
  assert(grouped.none? { |name, entries| name.nil? || entries.length != 1 }, "step names must be present and unique")
  grouped.transform_values(&:first)
end

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def move_step(job, name, before_name)
  steps = job.fetch("steps")
  moving = steps.delete_at(steps.index { |step| step["name"] == name })
  steps.insert(steps.index { |step| step["name"] == before_name }, moving)
end

def validate_release_graph(workflow)
  assert(workflow["name"] == "Release", "workflow name must remain Release")
  triggers = workflow["on"]
  assert(triggers.is_a?(Hash) && triggers.keys.sort == %w[push workflow_dispatch], "only release tag pushes and manual recovery may trigger")
  assert(triggers.dig("push", "tags") == ["v*"], "push trigger must be restricted to version tags")
  tag_input = triggers.dig("workflow_dispatch", "inputs", "tag")
  assert(tag_input.is_a?(Hash) && tag_input["required"] == true && tag_input["type"] == "string", "manual recovery must require an exact tag")
  assert(workflow["permissions"] == { "contents" => "read" }, "top-level permissions must be read-only")
  assert(workflow["concurrency"] == { "group" => "updatebar-release", "cancel-in-progress" => false }, "release runs must use one non-cancelling concurrency group")

  jobs = workflow.fetch("jobs")
  assert(jobs.keys == %w[verify publish notify], "job graph must be verify, protected publish, protected notify")
  %w[softprops/action-gh-release NOTARY_APPLE_ID NOTARY_PASSWORD MACOS_SIGNING_CERT_P12].each do |retired|
    assert(!workflow.to_s.include?(retired), "retired or optional release path must be absent: #{retired}")
  end
  jobs.each_value do |job|
    job.fetch("steps").each do |step|
      next unless step.key?("uses")
      assert(step.fetch("uses").match?(/\A[^@]+@[0-9a-f]{40}\z/), "every external action must use a full reviewed commit SHA")
    end
  end
  verify = jobs.fetch("verify")
  publish = jobs.fetch("publish")
  notify = jobs.fetch("notify")

  assert(verify["strategy"] == {
    "fail-fast" => false,
    "matrix" => { "include" => [
      { "os" => "macos-15", "artifact" => "macos-arm64" },
      { "os" => "ubuntu-24.04", "artifact" => "linux-x86_64" }
    ] }
  }, "verification matrix must pin the canonical macOS and Linux runners")
  assert(verify["runs-on"] == "${{ matrix.os }}", "verify must use the pinned matrix runner")
  assert(verify["permissions"] == { "contents" => "read" }, "verify must be read-only")
  assert(!verify.key?("environment"), "verify must not enter the release environment")
  assert(!verify.to_s.include?("secrets."), "verify must not receive production secrets")
  assert(verify.dig("outputs", "release_commit") == "${{ steps.provenance.outputs.release_commit }}", "verify must expose the validated tag commit")
  assert(verify.dig("env", "RELEASE_TAG") == "${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}", "verify must resolve push and recovery tags")

  verify_steps = step_map(verify)
  expected_verify = [
    "Checkout release tag", "Validate release provenance", "Setup Swift on Linux",
    "Install Linux link dependencies", "Run Swift tests", "Build CLI archive",
    "Smoke-test CLI archive", "Verify checksums", "Upload CLI artifact"
  ]
  assert(verify.fetch("steps").map { |step| step["name"] } == expected_verify, "verification steps must be exact and ordered")
  checkout = verify_steps.fetch("Checkout release tag")
  assert(checkout["uses"] == "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", "checkout must use the reviewed SHA")
  assert(checkout["with"] == {
    "ref" => "refs/tags/${{ env.RELEASE_TAG }}", "fetch-depth" => 0, "persist-credentials" => false
  }, "verify checkout must use the exact tag with no persisted credential")
  provenance = verify_steps.fetch("Validate release provenance")
  assert(provenance["id"] == "provenance" && provenance["shell"] == "bash", "provenance step must expose a stable output")
  provenance_run = provenance.fetch("run")
  [
    "refs/tags/$RELEASE_TAG", "git show-ref --verify --quiet", "^{commit}",
    "refs/heads/main:", "refs/tags/$RELEASE_TAG:", "git merge-base --is-ancestor",
    "^v[0-9]+([.][0-9]+){1,2}$", "^UPDATEBAR_VERSION=", "^([0-9a-f]{40})$",
    "release_commit=%s"
  ].each { |fragment| assert(provenance_run.include?(fragment), "provenance is missing #{fragment}") }
  assert(!provenance_run.match?(/rev-parse[^\n]*\$RELEASE_TAG(?![^\n]*tag_ref)/), "provenance must not resolve a bare tag")
  assert(provenance_run.index("git fetch") < provenance_run.index("git merge-base --is-ancestor"), "remote refs must be fetched before ancestry validation")
  assert(verify_steps.fetch("Setup Swift on Linux")["uses"] == "swift-actions/setup-swift@7591e4f04c00624cb043783da51a7fd6ee0a6bf6", "Swift setup must use the reviewed SHA")
  assert(verify_steps.fetch("Upload CLI artifact")["uses"] == "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02", "artifact upload must use the reviewed SHA")
  assert(verify_steps.fetch("Upload CLI artifact").dig("with", "path") == "dist/*.tar.gz\ndist/*.tar.gz.sha256\n", "verify may upload only CLI archives and checksums")
  assert(!verify.to_s.match?(/build-app|generate-appcast|publish-release|softprops|verify-homebrew/i), "verify must not package or publish the app")

  assert(publish["needs"] == "verify", "publish must depend only on verification")
  assert(publish["environment"] == "release", "publish must use the protected release environment")
  assert(publish["runs-on"] == "macos-15", "publish must run on the canonical macOS runner")
  assert(publish["permissions"] == { "contents" => "write" }, "publish must receive only contents write")
  assert(!publish.key?("if"), "manual recovery and tag pushes must both reach protected publication")
  assert(publish.dig("env", "RELEASE_TAG") == "${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}", "publish must reuse the exact selected tag")
  assert(publish.dig("env", "NOTARYTOOL_KEYCHAIN_PROFILE") == "updatebar-notary", "notary profile must be fixed")
  publish_steps = step_map(publish)
  expected_publish = [
    "Checkout verified release commit", "Verify release commit", "Download CLI artifacts",
    "Verify downloaded checksums", "Setup Node.js", "Install release tooling",
    "Prepare signing workspace", "Install Apple credentials", "Build notarized app DMG",
    "Smoke-test app DMG", "Generate signed appcast", "Generate release manifest",
    "Publish release", "Cleanup Apple credentials"
  ]
  assert(publish.fetch("steps").map { |step| step["name"] } == expected_publish, "publish steps must be exact and ordered")
  publish_checkout = publish_steps.fetch("Checkout verified release commit")
  assert(publish_checkout["uses"] == "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", "publish checkout must use the reviewed SHA")
  assert(publish_checkout["with"] == {
    "ref" => "${{ needs.verify.outputs.release_commit }}", "fetch-depth" => 0, "persist-credentials" => false
  }, "publish checkout must use only the verified commit")
  publish_commit_check = publish_steps.fetch("Verify release commit").fetch("run")
  assert(publish_commit_check.include?('head_commit="$(git rev-parse HEAD)"') &&
    publish_commit_check.include?('[[ "$head_commit" != "$VERIFIED_RELEASE_COMMIT" ]]'),
    "publish must compare HEAD with the verified output")
  download = publish_steps.fetch("Download CLI artifacts")
  assert(download["uses"] == "actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093", "artifact download must use the reviewed SHA")
  assert(download["with"] == {
    "pattern" => "updatebar-*", "path" => "dist", "merge-multiple" => true
  }, "publish must download only UpdateBar CLI matrix artifacts")
  downloaded_checks = publish_steps.fetch("Verify downloaded checksums").fetch("run")
  %w[macos-arm64 linux-x86_64 tar.gz.sha256 Dir.children].each do |fragment|
    assert(downloaded_checks.include?(fragment), "download verification must enforce the exact CLI set: #{fragment}")
  end
  assert(publish_steps.fetch("Setup Node.js")["uses"] == "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020", "Node setup must use the reviewed SHA")
  assert(publish_steps.fetch("Setup Node.js").dig("with", "node-version") == "24.18.0", "Node must pin the reviewed LTS patch")

  apple_names = %w[APPLE_CERTIFICATE_P12_BASE64 APPLE_CERTIFICATE_PASSWORD APPLE_NOTARY_KEY_P8_BASE64 APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID]
  credentials = publish_steps.fetch("Install Apple credentials")
  apple_names.each { |name| assert(credentials.dig("env", name) == "${{ secrets.#{name} }}", "#{name} must be required from secrets") }
  credential_run = credentials.fetch("run")
  apple_names.each { |name| assert(credential_run.include?("${#{name}:?"), "credential setup must fail closed for #{name}") }
  ["umask 077", "/usr/bin/base64 -D", "/usr/bin/security create-keychain", "/usr/bin/security import", "notarytool store-credentials"].each do |fragment|
    assert(credential_run.include?(fragment), "credential setup is missing #{fragment}")
  end
  assert(!credential_run.match?(/--apple-id|--password\s+\"\$APPLE_NOTARY/), "notary authentication must use the API key, not Apple ID credentials")

  prepare_run = publish_steps.fetch("Prepare signing workspace").fetch("run")
  assert(prepare_run.include?('mktemp -d "$RUNNER_TEMP/updatebar-release.XXXXXX"'), "signing workspace must be randomized below runner temp")
  assert(prepare_run.include?("umask 077"), "signing workspace must be private")
  build = publish_steps.fetch("Build notarized app DMG")
  assert(build["env"] == {
    "DEVELOPER_ID_APPLICATION" => "${{ vars.DEVELOPER_ID_APPLICATION }}",
    "SPARKLE_PUBLIC_ED_KEY" => "${{ vars.SPARKLE_PUBLIC_ED_KEY }}"
  }, "DMG build must receive only the public signing inputs")
  assert(build.fetch("run").include?('APP_DMG="$(bash Scripts/build-app-dmg.sh)"'), "canonical DMG builder must run once and capture its exact path")
  appcast = publish_steps.fetch("Generate signed appcast")
  assert(appcast["env"] == {
    "SPARKLE_PUBLIC_ED_KEY" => "${{ vars.SPARKLE_PUBLIC_ED_KEY }}",
    "SPARKLE_PRIVATE_ED_KEY" => "${{ secrets.SPARKLE_PRIVATE_ED_KEY }}",
    "UPDATE_DOMAIN" => "updates.updatebar.sonim1.com"
  }, "appcast must receive the separate UpdateBar Sparkle key and fixed domain")
  assert(appcast["run"] == "Scripts/generate-appcast.sh", "canonical appcast generator must run once")
  assert(publish_steps.fetch("Generate release manifest")["run"] == 'Scripts/generate-release-manifest.sh "$RELEASE_TAG"', "manifest must bind the exact tag")
  publication = publish_steps.fetch("Publish release")
  assert(publication["env"] == {
    "GH_TOKEN" => "${{ github.token }}",
    "CLOUDFLARE_ACCOUNT_ID" => "${{ vars.CLOUDFLARE_ACCOUNT_ID }}",
    "R2_ACCESS_KEY_ID" => "${{ secrets.R2_ACCESS_KEY_ID }}",
    "R2_SECRET_ACCESS_KEY" => "${{ secrets.R2_SECRET_ACCESS_KEY }}",
    "R2_BUCKET_NAME" => "updatebar-updates",
    "UPDATE_DOMAIN" => "updates.updatebar.sonim1.com"
  }, "publisher must use the fixed UpdateBar release destination")
  assert(publication["run"] == 'Scripts/publish-release.sh "$RELEASE_TAG"', "coordinated publisher must run once")
  assert(!publish.to_s.include?("create-github-app-token"), "tap token must not enter the publish job")
  assert(!publish.to_s.include?("dispatch-homebrew-update"), "tap dispatch must not enter the publish job")
  cleanup = publish_steps.fetch("Cleanup Apple credentials")
  assert(cleanup["if"] == "always()", "credential cleanup must always run")
  cleanup_run = cleanup.fetch("run")
  ["RUNNER_TEMP", "updatebar-release", "updatebar-release.keychain-db", "updatebar-release-certificate.p12", "updatebar-notary-auth-key.p8"].each do |fragment|
    assert(cleanup_run.include?(fragment), "cleanup is missing the validated #{fragment} boundary")
  end
  assert(!cleanup_run.match?(/rm\s+-rf|rm\s+-f\s+[^\n]*[*?]|\$RUNNER_TEMP\/(?!updatebar-release)/), "cleanup must not use recursive, globbed, or broad deletion")

  assert(notify["needs"] == ["verify", "publish"], "notify must wait for verification and publication")
  assert(notify["environment"] == "release", "notify must use the protected release environment")
  assert(notify["runs-on"] == "ubuntu-24.04", "notify must use the pinned Linux runner")
  assert(notify["permissions"] == { "contents" => "read" }, "notify must remain read-only")
  assert(!notify.key?("if"), "manual recovery must be able to retry notification")
  notify_steps = step_map(notify)
  assert(notify.fetch("steps").map { |step| step["name"] } == [
    "Checkout verified release commit", "Verify release commit", "Create tap GitHub App token", "Notify Homebrew tap"
  ], "notify must remain an isolated retryable job")
  notify_checkout = notify_steps.fetch("Checkout verified release commit")
  assert(notify_checkout["uses"] == "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", "notify checkout must use the reviewed SHA")
  assert(notify_checkout["with"] == {
    "ref" => "${{ needs.verify.outputs.release_commit }}", "fetch-depth" => 1, "persist-credentials" => false
  }, "notify checkout must use the verified commit without credentials")
  notify_commit_check = notify_steps.fetch("Verify release commit").fetch("run")
  assert(notify_commit_check.include?('head_commit="$(git rev-parse HEAD)"') &&
    notify_commit_check.include?('[[ "$head_commit" != "$VERIFIED_RELEASE_COMMIT" ]]'),
    "notify must compare HEAD with the verified output")
  token = notify_steps.fetch("Create tap GitHub App token")
  assert(token["uses"] == "actions/create-github-app-token@67018539274d69449ef7c02e8e71183d1719ab42", "tap token action must use the reviewed SHA")
  assert(token["with"] == {
    "app-id" => "${{ vars.TAP_GITHUB_APP_ID }}", "private-key" => "${{ secrets.TAP_GITHUB_APP_PRIVATE_KEY }}",
    "owner" => "sonim1", "repositories" => "homebrew-tap", "permission-contents" => "write"
  }, "tap token must be scoped to homebrew-tap contents write")
  dispatch = notify_steps.fetch("Notify Homebrew tap")
  assert(dispatch["env"] == { "TAP_GH_TOKEN" => "${{ steps.tap-token.outputs.token }}" }, "dispatch may receive only the app installation token")
  assert(dispatch["run"] == 'Scripts/dispatch-homebrew-update.sh "$RELEASE_TAG"', "dispatch must bind the exact published tag")
  %w[build-app generate-appcast generate-release-manifest publish-release SPARKLE_PRIVATE R2_ACCESS APPLE_CERTIFICATE APPLE_NOTARY].each do |forbidden|
    assert(!notify.to_s.include?(forbidden), "notify must not rebuild or republish: #{forbidden}")
  end
end

validate_release_graph(workflow)

mutations = {}
mutations["publish bypasses verify"] = deep_copy(workflow).tap { |w| w["jobs"]["publish"].delete("needs") }
mutations["publication precedes appcast"] = deep_copy(workflow).tap { |w| move_step(w["jobs"]["publish"], "Publish release", "Generate signed appcast") }
mutations["Apple secret becomes optional"] = deep_copy(workflow).tap do |w|
  run = step_map(w["jobs"]["publish"]).fetch("Install Apple credentials")["run"]
  step_map(w["jobs"]["publish"]).fetch("Install Apple credentials")["run"] = run.gsub('${APPLE_CERTIFICATE_PASSWORD:?', '${APPLE_CERTIFICATE_PASSWORD:-')
end
mutations["verify checks out bare tag"] = deep_copy(workflow).tap { |w| step_map(w["jobs"]["verify"]).fetch("Checkout release tag")["with"]["ref"] = "${{ env.RELEASE_TAG }}" }
mutations["checkout persists credentials"] = deep_copy(workflow).tap { |w| step_map(w["jobs"]["publish"]).fetch("Checkout verified release commit")["with"]["persist-credentials"] = true }
mutations["tap token enters publish"] = deep_copy(workflow).tap do |w|
  w["jobs"]["publish"]["steps"].insert(-2, deep_copy(step_map(w["jobs"]["notify"]).fetch("Create tap GitHub App token")))
end
mutations["notify is merged into publish"] = deep_copy(workflow).tap { |w| w["jobs"].delete("notify") }
mutations["cleanup becomes recursive"] = deep_copy(workflow).tap do |w|
  step_map(w["jobs"]["publish"]).fetch("Cleanup Apple credentials")["run"] << "\nrm -rf \"$RUNNER_TEMP\"\n"
end

mutations.each do |label, mutation|
  begin
    validate_release_graph(mutation)
  rescue RuntimeError => error
    raise unless error.message.start_with?("FAIL:")
  else
    raise "FAIL: workflow contract accepted mutation: #{label}"
  end
end

puts "release workflow structure and mutation tests passed"
RUBY

PROVENANCE_RUN="$(ruby -rpsych - "$WORKFLOW" <<'RUBY'
workflow = Psych.safe_load(File.binread(ARGV.fetch(0)), permitted_classes: [], permitted_symbols: [], aliases: false)
steps = workflow.fetch("jobs").fetch("verify").fetch("steps")
matches = steps.select { |step| step["name"] == "Validate release provenance" }
abort "expected exactly one provenance step" unless matches.length == 1
run = matches.first["run"]
abort "provenance step has no shell body" unless run.is_a?(String)
print run
RUBY
)"

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/updatebar-workflow-provenance.XXXXXX")"
cleanup_fixture() {
  rm -rf "$FIXTURE"
}
trap cleanup_fixture EXIT

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
[[ "$(<"$FIXTURE/github-output")" == "release_commit=$EXPECTED_COMMIT" ]] || {
  echo "provenance shell did not emit the exact verified tag commit" >&2
  exit 1
}

git -C "$FIXTURE/source" checkout --orphan off-main >/dev/null 2>&1
git -C "$FIXTURE/source" rm -f version.env >/dev/null
printf 'UPDATEBAR_VERSION=1.2.4\n' > "$FIXTURE/source/version.env"
git -C "$FIXTURE/source" add version.env
git -C "$FIXTURE/source" commit -m "off-main release fixture" >/dev/null
git -C "$FIXTURE/source" tag v1.2.4
git -C "$FIXTURE/source" push origin refs/tags/v1.2.4 >/dev/null 2>&1
git -C "$FIXTURE/checkout" fetch --no-tags origin refs/tags/v1.2.4:refs/tags/v1.2.4 >/dev/null 2>&1
git -C "$FIXTURE/checkout" checkout --detach refs/tags/v1.2.4 >/dev/null 2>&1
if (
  cd "$FIXTURE/checkout"
  RELEASE_TAG=v1.2.4 GITHUB_OUTPUT="$FIXTURE/github-output" bash -euo pipefail -c "$PROVENANCE_RUN"
) >/dev/null 2>&1; then
  echo "provenance shell accepted a release tag that is not on remote main" >&2
  exit 1
fi

echo "release workflow tests passed"
