#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/ci.yml"
[[ -f "$WORKFLOW" ]] || { echo "CI workflow is missing" >&2; exit 1; }

ruby -rpsych - "$WORKFLOW" <<'RUBY'
CHECKOUT_ACTION = "actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"
TOKEN_ACTION = "actions/create-github-app-token@67018539274d69449ef7c02e8e71183d1719ab42"
LANE_IF = "${{ always() }}"
GUARD_IF = "${{ always() && github.event_name == 'pull_request' && (needs.policy.result != 'success' || needs.version.result != 'success' || needs.version.outputs.ready != 'true') }}"
CI_REF = "${{ github.event_name == 'pull_request' && github.event.pull_request.head.sha || github.sha }}"

def assert(value, message)
  raise "FAIL: #{message}" unless value
end

def copy(value)
  Marshal.load(Marshal.dump(value))
end

def step_map(job)
  grouped = job.fetch("steps").group_by { |step| step["name"] }
  assert(grouped.none? { |name, entries| name.nil? || entries.length != 1 }, "step names must be present and unique")
  grouped.transform_values(&:first)
end

def named_step(job, name)
  matches = job.fetch("steps").select { |step| step["name"] == name }
  assert(matches.length == 1, "#{name} step must be present exactly once")
  matches.first
end

def action_step(job, action)
  matches = job.fetch("steps").select { |step| step["uses"] == action }
  assert(matches.length == 1, "#{action} step must be present exactly once")
  matches.first
end

def validate(workflow)
  assert(workflow["name"] == "CI", "workflow name must remain CI")
  triggers = workflow["on"]
  assert(triggers.is_a?(Hash) && triggers.keys.sort == %w[pull_request push], "only push and pull_request may trigger CI")
  assert(triggers["push"].nil? || triggers["push"] == {}, "push behavior must remain unrestricted")
  assert(triggers["pull_request"] == {
    "branches" => ["main"],
    "types" => %w[opened reopened synchronize labeled unlabeled],
  }, "pull requests must target main and rerun for the five version-policy activities")
  assert(workflow["permissions"] == { "contents" => "read" }, "workflow permissions must remain read-only")
  assert(workflow["concurrency"] == {
    "group" => "${{ github.workflow }}-${{ github.event_name }}-${{ github.event_name == 'pull_request' && github.event.pull_request.number || github.ref }}",
    "cancel-in-progress" => true,
  }, "concurrency must cancel superseded runs per pull request or push ref")

  jobs = workflow.fetch("jobs")
  assert(jobs.keys == %w[policy version macos linux], "job graph must be policy, version, macos, and linux")
  jobs.each_value do |job|
    job.fetch("steps", []).each do |step|
      next unless step.key?("uses")

      assert(step.fetch("uses").match?(/\A[^@]+@[0-9a-f]{40}\z/), "all external actions must use reviewed full SHAs")
    end
  end

  policy = jobs.fetch("policy")
  version = jobs.fetch("version")
  macos = jobs.fetch("macos")
  linux = jobs.fetch("linux")

  assert(!policy.key?("needs"), "policy must be the first job in the PR dependency graph")
  assert(policy["if"] == "${{ github.event_name == 'pull_request' }}", "policy must be PR-only")
  assert(policy["runs-on"] == "ubuntu-24.04", "policy must use the pinned metadata runner")
  assert(policy["permissions"] == {}, "policy must have no repository permissions")
  assert(policy["outputs"] == {
    "trusted" => "${{ steps.policy.outputs.trusted }}",
    "release_kind" => "${{ steps.policy.outputs.release_kind }}",
  }, "policy must expose only trust and release kind")
  assert(policy.fetch("steps").length == 1, "policy must contain only its metadata validation step")
  policy_step = policy.fetch("steps").first
  assert(policy_step["name"] == "Validate pull request policy" && policy_step["id"] == "policy" && policy_step["shell"] == "bash", "policy validation step must remain explicit")
  assert(policy_step.keys.sort == %w[env id name run shell], "policy validation must not tolerate errors or receive extra inputs")
  assert(!policy.to_s.include?("uses") && !policy.to_s.include?("checkout") &&
    !policy.to_s.include?("secrets.") && !policy.to_s.match?(/token/i),
    "policy must not check out code or receive a token")
  assert(policy_step["env"] == {
    "BASE_REF" => "${{ github.event.pull_request.base.ref }}",
    "HEAD_REPOSITORY" => "${{ github.event.pull_request.head.repo.full_name }}",
    "REPOSITORY" => "${{ github.repository }}",
    "AUTHOR_ASSOCIATION" => "${{ github.event.pull_request.author_association }}",
    "ACTOR" => "${{ github.actor }}",
    "AUTHOR_LOGIN" => "${{ github.event.pull_request.user.login }}",
    "LABELS_JSON" => "${{ toJSON(github.event.pull_request.labels.*.name) }}",
  }, "policy must consume only immutable PR metadata")
  policy_run = policy_step.fetch("run")
  [
    "printf 'trusted=false\\n' >> \"$GITHUB_OUTPUT\"",
    "[[ \"$BASE_REF\" != \"main\" ]]",
    "[[ \"$HEAD_REPOSITORY\" != \"$REPOSITORY\" ]]",
    "[[ \"$ACTOR\" == \"dependabot[bot]\" || \"$AUTHOR_LOGIN\" == \"dependabot[bot]\" ]]",
    "OWNER | MEMBER | COLLABORATOR)",
    '*) reject "author association is not trusted: $AUTHOR_ASSOCIATION" ;;',
    'labels & %w[release:minor release:major]',
    "release_labels.length > 1",
    'release_labels.empty? ? "patch" : release_labels.fetch(0).delete_prefix("release:")',
    "printf 'release_kind=%s\\n' \"$release_kind\" >> \"$GITHUB_OUTPUT\"",
    "printf 'trusted=true\\n' >> \"$GITHUB_OUTPUT\"",
  ].each do |fragment|
    assert(policy_run.include?(fragment), "policy is missing trust-boundary fragment: #{fragment}")
  end
  assert(!policy_run.include?("CONTRIBUTOR") && !policy_run.include?("FIRST_TIME_CONTRIBUTOR"), "untrusted author associations must fail closed")
  assert(policy_run.index("printf 'trusted=false") < policy_run.index("[[ \"$BASE_REF\""), "policy must default to untrusted before validation")
  assert(policy_run.index("printf 'trusted=true") > policy_run.index("release_labels.length > 1"), "policy may trust only after label validation")

  assert(version["needs"] == "policy", "version must wait for policy")
  assert(version["if"] == "${{ always() && github.event_name == 'pull_request' && needs.policy.result == 'success' && needs.policy.outputs.trusted == 'true' }}", "version must run only for a successful trusted PR policy")
  assert(version["runs-on"] == "ubuntu-24.04", "version must use the pinned Linux runner")
  assert(version["permissions"] == {}, "the job GITHUB_TOKEN must have no repository permissions")
  assert(version["outputs"] == {
    "ready" => "${{ steps.prepare.outputs.ready }}",
    "release" => "${{ steps.prepare.outputs.release }}",
    "version" => "${{ steps.prepare.outputs.version }}",
  }, "version must expose release readiness and version metadata")
  assert(version.fetch("steps").map { |step| step["name"] } == [
    "Create version GitHub App token",
    "Checkout pull request head",
    "Verify pull request head",
    "Prepare pull request version",
    "Commit prepared version",
  ], "version steps must be exact and ordered")
  version_steps = step_map(version)
  token = version_steps.fetch("Create version GitHub App token")
  assert(token["id"] == "version-token" && token["uses"] == TOKEN_ACTION, "version token action must use the reviewed SHA")
  assert(token.keys.sort == %w[id name uses with], "version token step must contain only its reviewed inputs")
  assert(token["with"] == {
    "app-id" => "${{ vars.VERSION_GITHUB_APP_ID }}",
    "private-key" => "${{ secrets.VERSION_GITHUB_APP_PRIVATE_KEY }}",
    "owner" => "sonim1",
    "repositories" => "UpdateBar",
    "permission-contents" => "write",
  }, "version App token must be scoped to UpdateBar contents write only")
  assert(workflow.to_s.scan("actions/create-github-app-token@").length == 1, "only version may create an App token")
  assert(workflow.to_s.scan("secrets.VERSION_GITHUB_APP_PRIVATE_KEY").length == 1, "the App private key may enter only version")
  assert(workflow.to_s.scan(/secrets[.][A-Za-z0-9_]+/).sort == ["secrets.VERSION_GITHUB_APP_PRIVATE_KEY"], "CI may receive only the version App private key")

  checkout = version_steps.fetch("Checkout pull request head")
  assert(checkout["uses"] == CHECKOUT_ACTION, "version checkout must use the reviewed SHA")
  assert(checkout["with"] == {
    "ref" => "${{ github.event.pull_request.head.sha }}",
    "fetch-depth" => 0,
    "token" => "${{ steps.version-token.outputs.token }}",
    "persist-credentials" => true,
  }, "version must check out the exact PR head with full history and persisted App credentials")
  verify = version_steps.fetch("Verify pull request head")
  assert(verify["env"] == { "EXPECTED_HEAD_SHA" => "${{ github.event.pull_request.head.sha }}" }, "HEAD verification must receive the event SHA")
  verify_run = verify.fetch("run")
  assert(verify_run.include?('[[ ! "$EXPECTED_HEAD_SHA" =~ ^[0-9a-f]{40}$ ]]') &&
    verify_run.include?('actual_head="$(git rev-parse HEAD)"') &&
    verify_run.include?('[[ "$actual_head" != "$EXPECTED_HEAD_SHA" ]]'),
    "version must verify canonical HEAD against the exact event SHA")

  prepare = version_steps.fetch("Prepare pull request version")
  assert(prepare["id"] == "prepare" && prepare["shell"] == "bash", "version preparation must expose script outputs")
  assert(prepare["env"] == {
    "BASE_SHA" => "${{ github.event.pull_request.base.sha }}",
    "HEAD_SHA" => "${{ github.event.pull_request.head.sha }}",
    "RELEASE_KIND" => "${{ needs.policy.outputs.release_kind }}",
  }, "version preparation must bind event commits and trusted policy output")
  assert(prepare["run"] == 'bash Scripts/prepare-pr-version.sh "$BASE_SHA" "$HEAD_SHA" "$RELEASE_KIND" "$GITHUB_OUTPUT"', "version preparation invocation must be exact")

  commit = version_steps.fetch("Commit prepared version")
  assert(commit["if"] == "${{ steps.prepare.outputs.changed == 'true' }}", "commit must run only when preparation changed artifacts")
  assert(commit["env"] == {
    "HEAD_REF" => "${{ github.event.pull_request.head.ref }}",
    "VERSION" => "${{ steps.prepare.outputs.version }}",
  }, "commit must bind the event branch and prepared version")
  commit_run = commit.fetch("run")
  expected_allowlist = <<~SHELL.chomp
    allowed_paths=(
      "version.env"
      "Sources/UpdateBarCLI/UpdateBarVersion.swift"
      "CHANGELOG.md"
    )
  SHELL
  assert(commit_run.include?(expected_allowlist), "commit allowlist must contain exactly the three version artifacts")
  [
    "git diff --name-only -z",
    "git ls-files --others --exclude-standard -z",
    'git add -- "${allowed_paths[@]}"',
    "git diff --cached --name-only -z",
    'git config user.name "github-actions[bot]"',
    'git config user.email "41898282+github-actions[bot]@users.noreply.github.com"',
    'git commit -m "Prepare UpdateBar $VERSION release"',
    'git check-ref-format --branch "$HEAD_REF"',
    'git push origin "HEAD:refs/heads/$HEAD_REF"',
  ].each do |fragment|
    assert(commit_run.include?(fragment), "version commit is missing safety fragment: #{fragment}")
  end
  assert(commit_run.scan(/git add --/).length == 1, "version commit must stage exactly once")
  assert(commit_run.scan(/git push /).length == 1 && !commit_run.match?(/git push[^\n]*(?:--force(?:-with-lease)?|-f(?:\s|$))/), "version push must be singular and non-force")
  assert(commit_run.index('git diff --name-only -z') < commit_run.index('git add --'), "worktree allowlist must be checked before staging")
  assert(commit_run.index('git diff --cached --name-only -z') > commit_run.index('git add --'), "staged allowlist must be rechecked")
  assert(commit_run.index('git check-ref-format --branch "$HEAD_REF"') < commit_run.index('git push origin'), "head ref must be validated before push")

  { "macos" => macos, "linux" => linux }.each do |name, job|
    assert(job["needs"].is_a?(Array) && job["needs"].sort == %w[policy version], "#{name} must directly wait for policy and version")
    assert(job["if"] == LANE_IF, "#{name} must always materialize as a required check")
    assert(!job.key?("continue-on-error"), "#{name} must not tolerate a failing version guard")
    guard = job.fetch("steps").first
    assert(guard["name"] == "Enforce pull request version gate", "#{name} must start with the explicit version guard")
    assert(guard.keys.sort == %w[env if name run shell], "#{name} guard must contain only reviewed fields")
    assert(guard["if"] == GUARD_IF && guard["shell"] == "bash", "#{name} guard must run for every unready PR state")
    assert(guard["env"] == {
      "POLICY_RESULT" => "${{ needs.policy.result }}",
      "VERSION_RESULT" => "${{ needs.version.result }}",
      "VERSION_READY" => "${{ needs.version.outputs.ready }}",
    }, "#{name} guard diagnostics must receive dependency state through the environment")
    assert(guard["run"] == <<~SHELL, "#{name} guard must diagnose and fail the required check")
      set -euo pipefail
      echo "pull request version gate is not ready: policy=$POLICY_RESULT version=$VERSION_RESULT ready=$VERSION_READY" >&2
      exit 1
    SHELL
    job.fetch("steps").drop(1).each do |step|
      assert(!step.key?("if"), "#{name} normal steps must retain implicit success gating after the guard")
    end
    ci_checkout = action_step(job, CHECKOUT_ACTION)
    assert(job.fetch("steps").index(ci_checkout) == 1, "#{name} checkout must follow the guard")
    assert(ci_checkout["uses"] == CHECKOUT_ACTION && ci_checkout["with"] == {
      "ref" => CI_REF,
      "persist-credentials" => false,
    }, "#{name} must test the exact event SHA without retaining credentials")
  end

  assert(macos["runs-on"] == "macos-15" && !macos.key?("container"), "macos runner must remain macos-15")
  assert(action_step(macos, "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020") == {
    "uses" => "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020",
    "with" => { "node-version" => 20, "cache" => "npm", "cache-dependency-path" => "tui/package-lock.json" },
  }, "macos Node tooling must remain unchanged")
  assert(action_step(macos, "actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9") == {
    "uses" => "actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9",
    "with" => {
      "path" => ".build",
      "key" => "macos-spm-${{ runner.os }}-${{ hashFiles('Package.resolved') }}",
      "restore-keys" => "macos-spm-${{ runner.os }}-",
    },
  }, "macos Swift cache must remain unchanged")
  assert(named_step(macos, "Install shellcheck")["run"] == "brew install shellcheck", "macos shellcheck installation must remain unchanged")
  assert(named_step(macos, "Quality gate")["run"] == "SKIP_SIGNED_APPCAST=1 bash Scripts/quality-gate.sh", "macos quality gate command must remain unchanged")

  assert(linux["runs-on"] == "ubuntu-latest" && linux["container"] == "swift:6.0", "linux runner and Swift container must remain unchanged")
  assert(action_step(linux, "actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9") == {
    "uses" => "actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9",
    "with" => {
      "path" => ".build",
      "key" => "linux-spm-${{ runner.os }}-${{ hashFiles('Package.resolved') }}",
      "restore-keys" => "linux-spm-${{ runner.os }}-",
    },
  }, "linux Swift cache must remain unchanged")
  assert(named_step(linux, "Install quality gate dependencies")["run"] == "apt-get update\napt-get install -y nodejs ruby shellcheck\n", "linux quality dependencies must remain unchanged")
  assert(named_step(linux, "Trust the checked-out workspace")["run"] == 'git config --global --add safe.directory "$GITHUB_WORKSPACE"', "linux safe-directory command must remain unchanged")
  assert(named_step(linux, "Quality gate")["run"] == "SKIP_MENUBAR_SMOKE=1 SKIP_TUI_SMOKE=1 SKIP_TUI_INPUT=1 SKIP_SIGNED_APPCAST=1 bash Scripts/quality-gate.sh", "linux quality gate command must remain unchanged")
end

workflow = Psych.safe_load(File.binread(ARGV.fetch(0)), permitted_classes: [], permitted_symbols: [], aliases: false)
validate(workflow)

mutations = {
  "PR target branch" => ->(value) { value.fetch("on").fetch("pull_request")["branches"] = ["develop"] },
  "PR activity list" => ->(value) { value.fetch("on").fetch("pull_request")["types"].delete("labeled") },
  "workflow write permission" => ->(value) { value.fetch("permissions")["contents"] = "write" },
  "cross-run concurrency" => ->(value) { value.fetch("concurrency")["group"] = "CI" },
  "token before policy" => ->(value) { value.fetch("jobs").fetch("version").delete("needs") },
  "fork acceptance" => ->(value) {
    step = value.fetch("jobs").fetch("policy").fetch("steps").first
    step["run"] = step.fetch("run").sub('[[ "$HEAD_REPOSITORY" != "$REPOSITORY" ]]', '[[ -z "$HEAD_REPOSITORY" ]]')
  },
  "untrusted association" => ->(value) {
    step = value.fetch("jobs").fetch("policy").fetch("steps").first
    step["run"] = step.fetch("run").sub("OWNER | MEMBER | COLLABORATOR)", "OWNER | MEMBER | COLLABORATOR | CONTRIBUTOR)")
  },
  "untrusted association fallthrough" => ->(value) {
    step = value.fetch("jobs").fetch("policy").fetch("steps").first
    step["run"] = step.fetch("run").sub('*) reject "author association is not trusted: $AUTHOR_ASSOCIATION" ;;', "*) ;;")
  },
  "Dependabot acceptance" => ->(value) {
    step = value.fetch("jobs").fetch("policy").fetch("steps").first
    step["run"] = step.fetch("run").sub('[[ "$ACTOR" == "dependabot[bot]" || "$AUTHOR_LOGIN" == "dependabot[bot]" ]]', '[[ -z "$ACTOR" ]]')
  },
  "release label conflict" => ->(value) {
    step = value.fetch("jobs").fetch("policy").fetch("steps").first
    step["run"] = step.fetch("run").sub("release_labels.length > 1", "release_labels.length > 2")
  },
  "unpinned App token action" => ->(value) {
    step_map(value.fetch("jobs").fetch("version")).fetch("Create version GitHub App token")["uses"] = "actions/create-github-app-token@v2"
  },
  "broadened App token repository" => ->(value) {
    step_map(value.fetch("jobs").fetch("version")).fetch("Create version GitHub App token").fetch("with")["repositories"] = "UpdateBar,homebrew-tap"
  },
  "merge-ref checkout" => ->(value) {
    step_map(value.fetch("jobs").fetch("version")).fetch("Checkout pull request head").fetch("with")["ref"] = "${{ github.ref }}"
  },
  "shallow version checkout" => ->(value) {
    step_map(value.fetch("jobs").fetch("version")).fetch("Checkout pull request head").fetch("with")["fetch-depth"] = 1
  },
  "merge-ref macOS test" => ->(value) {
    action_step(value.fetch("jobs").fetch("macos"), CHECKOUT_ACTION).fetch("with")["ref"] = "${{ github.ref }}"
  },
  "swapped version commits" => ->(value) {
    step_map(value.fetch("jobs").fetch("version")).fetch("Prepare pull request version")["run"] = 'bash Scripts/prepare-pr-version.sh "$HEAD_SHA" "$BASE_SHA" "$RELEASE_KIND" "$GITHUB_OUTPUT"'
  },
  "expanded commit allowlist" => ->(value) {
    step = step_map(value.fetch("jobs").fetch("version")).fetch("Commit prepared version")
    step["run"] = step.fetch("run").sub("  \"CHANGELOG.md\"", "  \"CHANGELOG.md\"\n  \"README.md\"")
  },
  "force push" => ->(value) {
    step = step_map(value.fetch("jobs").fetch("version")).fetch("Commit prepared version")
    step["run"] = step.fetch("run").sub('git push origin', 'git push --force origin')
  },
  "job-level skip bypass" => ->(value) {
    value.fetch("jobs").fetch("macos")["if"] = "${{ github.event_name == 'push' || needs.version.outputs.ready == 'true' }}"
  },
  "job tolerates guard failure" => ->(value) {
    value.fetch("jobs").fetch("linux")["continue-on-error"] = true
  },
  "missing direct policy dependency" => ->(value) {
    value.fetch("jobs").fetch("linux")["needs"] = ["version"]
  },
  "missing required-check guard" => ->(value) {
    value.fetch("jobs").fetch("macos").fetch("steps").shift
  },
  "non-failing required-check guard" => ->(value) {
    guard = value.fetch("jobs").fetch("linux").fetch("steps").first
    guard["run"] = guard.fetch("run").sub("exit 1", "exit 0")
  },
  "guard ignores policy failure" => ->(value) {
    guard = value.fetch("jobs").fetch("macos").fetch("steps").first
    guard["if"] = guard.fetch("if").sub("needs.policy.result != 'success' || ", "")
  },
  "normal checkout bypasses failed guard" => ->(value) {
    action_step(value.fetch("jobs").fetch("linux"), CHECKOUT_ACTION)["if"] = "${{ always() }}"
  },
  "changed macOS quality command" => ->(value) {
    value.fetch("jobs").fetch("macos").fetch("steps").find { |step| step["name"] == "Quality gate" }["run"] = "bash Scripts/quality-gate.sh"
  },
  "changed Linux quality command" => ->(value) {
    value.fetch("jobs").fetch("linux").fetch("steps").find { |step| step["name"] == "Quality gate" }["run"] = "bash Scripts/quality-gate.sh"
  },
}

mutations.each do |name, mutate|
  changed = copy(workflow)
  mutate.call(changed)
  assert(changed != workflow, "mutation did not alter workflow: #{name}")
  begin
    validate(changed)
  rescue RuntimeError
    next
  end
  raise "FAIL: validator accepted mutation: #{name}"
end

puts "CI workflow tests passed (#{mutations.length} security mutations rejected)"
RUBY

exit 0
