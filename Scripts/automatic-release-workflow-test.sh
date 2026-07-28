#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/automatic-release.yml"
[[ -f "$WORKFLOW" ]] || { echo "automatic release workflow is missing" >&2; exit 1; }

ruby -ropen3 -rpsych - "$WORKFLOW" <<'RUBY'
CHECKOUT_ACTION = "actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"
RELEASE_IF = "${{ steps.plan.outputs.release == 'true' }}"
WRITE_PERMISSIONS = { "contents" => "write", "actions" => "write" }.freeze

def assert(value, message)
  raise "FAIL: #{message}" unless value
end

def copy(value)
  Marshal.load(Marshal.dump(value))
end

def step_map(job)
  grouped = job.fetch("steps").group_by { |step| step["name"] }
  assert(grouped.none? { |name, entries| name.nil? || entries.length != 1 },
    "step names must be present and unique")
  grouped.transform_values(&:first)
end

def validate(workflow)
  assert(workflow["name"] == "Automatic Release", "workflow name must remain Automatic Release")
  assert(workflow["on"] == { "push" => { "branches" => ["main"] } },
    "only pushes to main may trigger automatic release")
  assert(workflow["permissions"] == WRITE_PERMISSIONS,
    "workflow permissions must be contents and actions write only")
  assert(workflow["concurrency"] == {
    "group" => "updatebar-automatic-release",
    "queue" => "max",
    "cancel-in-progress" => false,
  }, "automatic releases must use the fixed non-cancelling maximum queue")

  jobs = workflow.fetch("jobs")
  assert(jobs.keys == ["automatic-release"], "workflow must contain one serialized release-planning job")
  job = jobs.fetch("automatic-release")
  assert(job.keys.sort == %w[permissions runs-on steps timeout-minutes],
    "automatic release job must contain only reviewed fields")
  assert(job["runs-on"] == "ubuntu-24.04", "automatic release must use the pinned Ubuntu runner")
  assert(job["timeout-minutes"].is_a?(Integer) && job["timeout-minutes"].between?(1, 10),
    "automatic release timeout must stay short")
  assert(job["permissions"] == WRITE_PERMISSIONS,
    "job permissions must be contents and actions write only")
  assert(!job.key?("environment"), "automatic release must not enter the release environment")

  expected_names = [
    "Checkout pushed commit",
    "Verify pushed commit",
    "Plan release",
    "Create or verify release tag",
    "Dispatch release workflow",
  ]
  assert(job.fetch("steps").map { |step| step["name"] } == expected_names,
    "automatic release steps must be exact and ordered")
  steps = step_map(job)

  checkout = steps.fetch("Checkout pushed commit")
  assert(checkout == {
    "name" => "Checkout pushed commit",
    "uses" => CHECKOUT_ACTION,
    "with" => {
      "ref" => "${{ github.sha }}",
      "fetch-depth" => 0,
      "token" => "${{ github.token }}",
      "persist-credentials" => true,
    },
  }, "checkout must persist the repository token at the exact pushed SHA with full history")

  verify = steps.fetch("Verify pushed commit")
  assert(verify.keys.sort == %w[env name run shell], "pushed SHA verification must contain only reviewed fields")
  assert(verify["shell"] == "bash" && verify["env"] == { "EXPECTED_SHA" => "${{ github.sha }}" },
    "pushed SHA verification must receive only the exact event SHA")
  verify_run = verify.fetch("run")
  [
    '[[ ! "$EXPECTED_SHA" =~ ^[0-9a-f]{40}$ ]]',
    'actual_sha="$(git rev-parse HEAD)"',
    '[[ "$actual_sha" != "$EXPECTED_SHA" ]]',
  ].each do |fragment|
    assert(verify_run.include?(fragment), "pushed SHA verification is missing: #{fragment}")
  end

  plan = steps.fetch("Plan release")
  assert(plan == {
    "name" => "Plan release",
    "id" => "plan",
    "shell" => "bash",
    "env" => {
      "BASE_SHA" => "${{ github.event.before }}",
      "HEAD_SHA" => "${{ github.sha }}",
    },
    "run" => 'bash Scripts/plan-release.sh "$BASE_SHA" "$HEAD_SHA" "$GITHUB_OUTPUT"',
  }, "release planning must bind the push range and append exact step outputs")

  tag = steps.fetch("Create or verify release tag")
  assert(tag.keys.sort == %w[env if name run shell], "tag step must contain only reviewed fields")
  assert(tag["if"] == RELEASE_IF && tag["shell"] == "bash",
    "tag creation must run only for an affirmative release plan")
  assert(tag["env"] == {
    "EXPECTED_SHA" => "${{ github.sha }}",
    "RELEASE_TAG" => "${{ steps.plan.outputs.tag }}",
    "RELEASE_VERSION" => "${{ steps.plan.outputs.version }}",
  }, "tag creation must bind the pushed SHA and planner outputs")
  tag_run = tag.fetch("run")
  required_tag_fragments = [
    '[[ ! "$EXPECTED_SHA" =~ ^[0-9a-f]{40}$ ]]',
    '[[ ! "$RELEASE_VERSION" =~ ^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$ ]]',
    '[[ "$RELEASE_TAG" != "v$RELEASE_VERSION" ]]',
    'tag_ref="refs/tags/$RELEASE_TAG"',
    'git fetch --tags origin',
    'git config user.name "github-actions[bot]"',
    'git config user.email "41898282+github-actions[bot]@users.noreply.github.com"',
    'git show-ref --verify --quiet "$tag_ref"',
    'git tag -a "$RELEASE_TAG" "$EXPECTED_SHA" -m "UpdateBar $RELEASE_VERSION"',
    'tag_type="$(git cat-file -t "$tag_ref")"',
    '[[ "$tag_type" != "tag" ]]',
    'tag_commit="$(git rev-parse "$tag_ref^{commit}")"',
    '[[ ! "$tag_commit" =~ ^[0-9a-f]{40}$ ]]',
    '[[ "$tag_commit" != "$EXPECTED_SHA" ]]',
    'git push origin "$tag_ref:$tag_ref"',
  ]
  required_tag_fragments.each do |fragment|
    assert(tag_run.include?(fragment), "tag creation is missing safety fragment: #{fragment}")
  end
  assert(tag_run.scan(/\bgit push\b/).length == 1, "tag creation must perform exactly one push")
  assert(!tag_run.match?(/git push[^\n]*(?:--force(?:-with-lease)?|-f(?:\s|$)|--all|--tags)/),
    "tag push must be exact, singular, and non-force")
  assert(tag_run.index('git fetch --tags origin') < tag_run.index('git show-ref --verify --quiet "$tag_ref"'),
    "remote tags must be fetched before deciding whether the release tag exists")
  assert(tag_run.index('tag_type="$(git cat-file -t "$tag_ref")"') <
    tag_run.index('git push origin "$tag_ref:$tag_ref"'),
    "the tag must be verified as annotated before it is pushed")
  assert(tag_run.index('[[ "$tag_commit" != "$EXPECTED_SHA" ]]') <
    tag_run.index('git push origin "$tag_ref:$tag_ref"'),
    "the peeled tag commit must match the pushed SHA before publication")

  dispatch = steps.fetch("Dispatch release workflow")
  assert(dispatch == {
    "name" => "Dispatch release workflow",
    "if" => RELEASE_IF,
    "shell" => "bash",
    "env" => {
      "GH_TOKEN" => "${{ github.token }}",
      "RELEASE_TAG" => "${{ steps.plan.outputs.tag }}",
    },
    "run" => 'gh workflow run release.yml --ref "$RELEASE_TAG" -f tag="$RELEASE_TAG"',
  }, "release.yml must be explicitly dispatched from the immutable planned tag")

  serialized = workflow.to_s
  assert(!serialized.include?("secrets."), "automatic release must not receive repository secrets")
  assert(!serialized.include?("vars."), "automatic release must not receive repository variables")
  %w[APPLE_ SPARKLE_PRIVATE R2_ CLOUDFLARE TAP_GITHUB_APP VERSION_GITHUB_APP].each do |sensitive|
    assert(!serialized.upcase.include?(sensitive), "automatic release must not contain #{sensitive} credentials")
  end
end

def validate_shell_blocks(workflow)
  count = 0
  workflow.fetch("jobs").each_value do |job|
    job.fetch("steps", []).each do |step|
      next unless step["run"].is_a?(String)

      _stdout, stderr, status = Open3.capture3("bash", "-n", stdin_data: step.fetch("run"))
      assert(status.success?, "shell syntax failed for #{step.fetch("name")}: #{stderr.strip}")
      count += 1
    end
  end
  count
end

workflow = Psych.safe_load(
  File.binread(ARGV.fetch(0)),
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false,
)
validate(workflow)
shell_blocks = validate_shell_blocks(workflow)

mutations = {
  "non-main push trigger" => ->(value) { value.fetch("on").fetch("push")["branches"] = ["develop"] },
  "tag push trigger" => ->(value) { value.fetch("on").fetch("push")["tags"] = ["v*"] },
  "workflow actions permission removed" => ->(value) { value.fetch("permissions").delete("actions") },
  "job contents permission weakened" => ->(value) { value.fetch("jobs").fetch("automatic-release").fetch("permissions")["contents"] = "read" },
  "release cancellation enabled" => ->(value) { value.fetch("concurrency")["cancel-in-progress"] = true },
  "release queue removed" => ->(value) { value.fetch("concurrency").delete("queue") },
  "release queue weakened" => ->(value) { value.fetch("concurrency")["queue"] = "single" },
  "movable checkout" => ->(value) { step_map(value.fetch("jobs").fetch("automatic-release")).fetch("Checkout pushed commit").fetch("with")["ref"] = "main" },
  "shallow checkout" => ->(value) { step_map(value.fetch("jobs").fetch("automatic-release")).fetch("Checkout pushed commit").fetch("with")["fetch-depth"] = 1 },
  "checkout token not persisted" => ->(value) { step_map(value.fetch("jobs").fetch("automatic-release")).fetch("Checkout pushed commit").fetch("with")["persist-credentials"] = false },
  "conflicting HEAD SHA accepted" => ->(value) {
    step = step_map(value.fetch("jobs").fetch("automatic-release")).fetch("Verify pushed commit")
    step["run"] = step.fetch("run").sub('[[ "$actual_sha" != "$EXPECTED_SHA" ]]', '[[ -z "$actual_sha" ]]')
  },
  "planner commits swapped" => ->(value) {
    step_map(value.fetch("jobs").fetch("automatic-release")).fetch("Plan release")["run"] =
      'bash Scripts/plan-release.sh "$HEAD_SHA" "$BASE_SHA" "$GITHUB_OUTPUT"'
  },
  "docs-only plan creates a tag" => ->(value) { step_map(value.fetch("jobs").fetch("automatic-release")).fetch("Create or verify release tag").delete("if") },
  "lightweight tag accepted" => ->(value) {
    step = step_map(value.fetch("jobs").fetch("automatic-release")).fetch("Create or verify release tag")
    step["run"] = step.fetch("run").sub('[[ "$tag_type" != "tag" ]]', '[[ "$tag_type" != "commit" ]]')
  },
  "conflicting tag SHA accepted" => ->(value) {
    step = step_map(value.fetch("jobs").fetch("automatic-release")).fetch("Create or verify release tag")
    step["run"] = step.fetch("run").sub('[[ "$tag_commit" != "$EXPECTED_SHA" ]]', '[[ -z "$tag_commit" ]]')
  },
  "broad tag push" => ->(value) {
    step = step_map(value.fetch("jobs").fetch("automatic-release")).fetch("Create or verify release tag")
    step["run"] = step.fetch("run").sub('git push origin "$tag_ref:$tag_ref"', 'git push origin --tags')
  },
  "force tag push" => ->(value) {
    step = step_map(value.fetch("jobs").fetch("automatic-release")).fetch("Create or verify release tag")
    step["run"] = step.fetch("run").sub('git push origin "$tag_ref:$tag_ref"', 'git push --force origin "$tag_ref:$tag_ref"')
  },
  "missing dispatch GH_TOKEN" => ->(value) { step_map(value.fetch("jobs").fetch("automatic-release")).fetch("Dispatch release workflow").fetch("env").delete("GH_TOKEN") },
  "movable dispatch ref" => ->(value) {
    step_map(value.fetch("jobs").fetch("automatic-release")).fetch("Dispatch release workflow")["run"] =
      'gh workflow run release.yml --ref main -f tag="$RELEASE_TAG"'
  },
  "tag-push-only recursion reliance" => ->(value) {
    value.fetch("on").fetch("push")["tags"] = ["v*"]
    value.fetch("jobs").fetch("automatic-release").fetch("steps").reject! do |step|
      step["name"] == "Dispatch release workflow"
    end
  },
  "release secret added" => ->(value) {
    value.fetch("jobs").fetch("automatic-release")["env"] = {
      "APPLE_CERTIFICATE_PASSWORD" => "${{ secrets.APPLE_CERTIFICATE_PASSWORD }}",
    }
  },
  "release environment added" => ->(value) { value.fetch("jobs").fetch("automatic-release")["environment"] = "release" },
  "version App credential added" => ->(value) {
    dispatch = step_map(value.fetch("jobs").fetch("automatic-release")).fetch("Dispatch release workflow")
    dispatch.fetch("env")["VERSION_GITHUB_APP_PRIVATE_KEY"] = "${{ secrets.VERSION_GITHUB_APP_PRIVATE_KEY }}"
  },
}

mutations.each do |name, mutate|
  changed = copy(workflow)
  mutate.call(changed)
  assert(changed != workflow, "mutation did not alter workflow: #{name}")
  begin
    validate(changed)
  rescue RuntimeError => error
    raise unless error.message.start_with?("FAIL:")
  else
    raise "FAIL: validator accepted mutation: #{name}"
  end
end

puts "automatic release workflow structure and mutation tests passed " \
  "(#{mutations.length} mutations rejected; #{shell_blocks} shell blocks parsed)"
RUBY
