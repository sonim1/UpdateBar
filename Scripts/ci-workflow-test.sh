#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/ci.yml"
[[ -f "$WORKFLOW" ]] || { echo "CI workflow is missing" >&2; exit 1; }

ruby -rpsych -rjson -ropen3 -rtmpdir -rfileutils -rshellwords - "$WORKFLOW" <<'RUBY'
CHECKOUT_ACTION = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
TOKEN_ACTION = "actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1"
LANE_IF = "${{ always() }}"
GUARD_IF = "${{ always() && github.event_name == 'pull_request' && (needs.policy.result != 'success' || (needs.policy.outputs.trusted == 'true' && (needs.version.result != 'success' || needs.version.outputs.ready != 'true'))) }}"
CI_REF = "${{ github.event_name == 'pull_request' && github.event.pull_request.head.sha || github.sha }}"
CACHE_SCOPE = "${{ github.event_name == 'pull_request' && needs.policy.outputs.cache_scope || 'push' }}"

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

def run_policy_probe(policy_run, state: "open", merged: "false", head_repository: "sonim1/UpdateBar", association: "OWNER", actor: "sonim1", author: "sonim1")
  Dir.mktmpdir("updatebar-ci-policy-probe") do |directory|
    output = File.join(directory, "github-output")
    environment = {
      "GITHUB_OUTPUT" => output,
      "BASE_REF" => "main",
      "PR_STATE" => state,
      "PR_MERGED" => merged,
      "HEAD_REPOSITORY" => head_repository,
      "REPOSITORY" => "sonim1/UpdateBar",
      "AUTHOR_ASSOCIATION" => association,
      "ACTOR" => actor,
      "AUTHOR_LOGIN" => author,
      "LABELS_JSON" => "[]",
    }
    stdout, stderr, status = Open3.capture3(environment, "bash", "-c", policy_run)
    emitted = File.exist?(output) ? File.binread(output) : ""
    return { stdout: stdout, stderr: stderr, status: status, emitted: emitted }
  end
end

def git!(directory, *arguments)
  stdout, stderr, status = Open3.capture3("git", *arguments, chdir: directory)
  raise "fixture git #{arguments.join(' ')} failed: #{stderr}" unless status.success?

  stdout.strip
end

def build_version_fixture(root)
  remote = File.join(root, "origin.git")
  checkout = File.join(root, "checkout")
  FileUtils.mkdir_p(checkout)
  git!(root, "init", "--bare", remote)
  git!(checkout, "init")
  git!(checkout, "config", "user.name", "Fixture")
  git!(checkout, "config", "user.email", "fixture@example.invalid")
  git!(checkout, "checkout", "-b", "feature")
  FileUtils.mkdir_p(File.join(checkout, "Sources/UpdateBarCLI"))
  File.binwrite(File.join(checkout, "version.env"), "UPDATEBAR_VERSION=1.2.3\n")
  File.binwrite(File.join(checkout, "Sources/UpdateBarCLI/UpdateBarVersion.swift"), "version 1.2.3\n")
  File.binwrite(File.join(checkout, "CHANGELOG.md"), "## Unreleased\n\n- Existing entry\n")
  git!(checkout, "add", "--", "version.env", "Sources/UpdateBarCLI/UpdateBarVersion.swift", "CHANGELOG.md")
  git!(checkout, "commit", "-m", "Fixture head")
  git!(checkout, "remote", "add", "origin", remote)
  git!(checkout, "push", "-u", "origin", "feature")
  expected_head = git!(checkout, "rev-parse", "HEAD")

  File.binwrite(File.join(checkout, "version.env"), "UPDATEBAR_VERSION=1.2.4\n")
  File.binwrite(File.join(checkout, "Sources/UpdateBarCLI/UpdateBarVersion.swift"), "version 1.2.4\n")
  File.binwrite(File.join(checkout, "CHANGELOG.md"), "## Unreleased\n\n## 1.2.4\n\n- Existing entry\n")

  { root: root, remote: remote, checkout: checkout, expected_head: expected_head }
end

def remote_head(fixture)
  stdout, _stderr, status = Open3.capture3(
    "git", "--git-dir=#{fixture.fetch(:remote)}", "rev-parse", "--verify", "refs/heads/feature",
    chdir: fixture.fetch(:root),
  )
  status.success? ? stdout.strip : nil
end

def move_remote_head(fixture)
  mover = File.join(fixture.fetch(:root), "mover")
  git!(fixture.fetch(:root), "clone", "--branch", "feature", fixture.fetch(:remote), mover)
  git!(mover, "config", "user.name", "Fixture mover")
  git!(mover, "config", "user.email", "mover@example.invalid")
  File.binwrite(File.join(mover, "moved.txt"), "remote moved\n")
  git!(mover, "add", "--", "moved.txt")
  git!(mover, "commit", "-m", "Move remote head")
  git!(mover, "push", "origin", "feature")
  git!(mover, "rev-parse", "HEAD")
end

def run_version_commit_probe(commit_run, fixture)
  environment = {
    "HEAD_REF" => "feature",
    "EXPECTED_HEAD_SHA" => fixture.fetch(:expected_head),
    "VERSION" => "1.2.4",
  }
  stdout, stderr, status = Open3.capture3(
    environment, "bash", "-c", commit_run, chdir: fixture.fetch(:checkout),
  )
  { stdout: stdout, stderr: stderr, status: status }
end

def run_runtime_probes(workflow)
  jobs = workflow.fetch("jobs")
  policy_run = jobs.fetch("policy").fetch("steps").first.fetch("run")

  open_result = run_policy_probe(policy_run)
  assert(open_result.fetch(:status).success?, "open unmerged trusted PR policy probe must pass")
  assert(open_result.fetch(:emitted) == "trusted=false\nrelease_kind=patch\ncache_scope=trusted\ntrusted=true\n", "open unmerged policy probe must emit trusted patch outputs")

  dependabot_result = run_policy_probe(policy_run, actor: "dependabot[bot]", author: "dependabot[bot]", association: "CONTRIBUTOR")
  assert(dependabot_result.fetch(:status).success?, "Dependabot PR policy probe must enter read-only CI")
  assert(dependabot_result.fetch(:emitted) == "trusted=false\ncache_scope=untrusted\n", "Dependabot must never receive trusted version preparation")

  fork_result = run_policy_probe(policy_run, head_repository: "contributor/UpdateBar", association: "CONTRIBUTOR", actor: "contributor", author: "contributor")
  assert(fork_result.fetch(:status).success?, "fork PR policy probe must enter read-only CI")
  assert(fork_result.fetch(:emitted) == "trusted=false\ncache_scope=untrusted\n", "fork PR must never receive trusted version preparation")

  closed_result = run_policy_probe(policy_run, state: "closed", merged: "false")
  assert(!closed_result.fetch(:status).success? && closed_result.fetch(:status).exitstatus == 65, "closed PR policy probe must fail closed")
  assert(closed_result.fetch(:emitted) == "trusted=false\n", "closed PR policy probe must never emit trust")

  merged_result = run_policy_probe(policy_run, state: "open", merged: "true")
  assert(!merged_result.fetch(:status).success? && merged_result.fetch(:status).exitstatus == 65, "merged PR policy probe must fail closed")
  assert(merged_result.fetch(:emitted) == "trusted=false\n", "merged PR policy probe must never emit trust")

  commit_run = step_map(jobs.fetch("version")).fetch("Commit prepared version").fetch("run")
  Dir.mktmpdir("updatebar-ci-version-success") do |root|
    fixture = build_version_fixture(root)
    result = run_version_commit_probe(commit_run, fixture)
    assert(result.fetch(:status).success?, "exact-lease version update probe must pass: #{result.fetch(:stderr)}")
    local_head = git!(fixture.fetch(:checkout), "rev-parse", "HEAD")
    assert(local_head != fixture.fetch(:expected_head) && remote_head(fixture) == local_head, "exact lease must atomically advance the expected branch")
    assert(git!(fixture.fetch(:checkout), "rev-parse", "HEAD^") == fixture.fetch(:expected_head), "prepared version commit must directly descend from the event head")
  end

  Dir.mktmpdir("updatebar-ci-version-deleted") do |root|
    fixture = build_version_fixture(root)
    git!(fixture.fetch(:root), "--git-dir=#{fixture.fetch(:remote)}", "update-ref", "-d", "refs/heads/feature")
    result = run_version_commit_probe(commit_run, fixture)
    assert(!result.fetch(:status).success?, "deleted remote branch probe must fail")
    assert(remote_head(fixture).nil?, "deleted remote branch probe must never recreate the branch")
    assert(git!(fixture.fetch(:checkout), "rev-parse", "HEAD") == fixture.fetch(:expected_head), "deleted remote branch must be rejected before committing")
  end

  Dir.mktmpdir("updatebar-ci-version-moved") do |root|
    fixture = build_version_fixture(root)
    moved_head = move_remote_head(fixture)
    result = run_version_commit_probe(commit_run, fixture)
    assert(!result.fetch(:status).success?, "moved remote branch probe must fail")
    assert(remote_head(fixture) == moved_head, "moved remote branch probe must not overwrite the new head")
    assert(git!(fixture.fetch(:checkout), "rev-parse", "HEAD") == fixture.fetch(:expected_head), "moved remote branch must be rejected before committing")
  end

  Dir.mktmpdir("updatebar-ci-version-race") do |root|
    fixture = build_version_fixture(root)
    hook = File.join(fixture.fetch(:checkout), ".git/hooks/pre-push")
    File.binwrite(hook, <<~SHELL)
      #!/usr/bin/env bash
      set -euo pipefail
      git --git-dir=#{Shellwords.escape(fixture.fetch(:remote))} update-ref -d refs/heads/feature
    SHELL
    File.chmod(0o755, hook)
    result = run_version_commit_probe(commit_run, fixture)
    assert(!result.fetch(:status).success?, "deleted-after-validation branch probe must fail the exact lease")
    assert(remote_head(fixture).nil?, "exact lease must not recreate a branch deleted during push")
  end
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
  assert(jobs.keys == %w[policy version macos linux tui], "job graph must include the isolated TUI runtime matrix")
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
  tui = jobs.fetch("tui")

  assert(!policy.key?("needs"), "policy must be the first job in the PR dependency graph")
  assert(policy["if"] == "${{ github.event_name == 'pull_request' }}", "policy must be PR-only")
  assert(policy["runs-on"] == "ubuntu-24.04", "policy must use the pinned metadata runner")
  assert(policy["permissions"] == {}, "policy must have no repository permissions")
  assert(policy["outputs"] == {
    "trusted" => "${{ steps.policy.outputs.trusted }}",
    "release_kind" => "${{ steps.policy.outputs.release_kind }}",
    "cache_scope" => "${{ steps.policy.outputs.cache_scope }}",
  }, "policy must expose trust, release kind, and isolated cache scope")
  assert(policy.fetch("steps").length == 1, "policy must contain only its metadata validation step")
  policy_step = policy.fetch("steps").first
  assert(policy_step["name"] == "Validate pull request policy" && policy_step["id"] == "policy" && policy_step["shell"] == "bash", "policy validation step must remain explicit")
  assert(policy_step.keys.sort == %w[env id name run shell], "policy validation must not tolerate errors or receive extra inputs")
  assert(!policy.to_s.include?("uses") && !policy.to_s.include?("checkout") &&
    !policy.to_s.include?("secrets.") && !policy.to_s.match?(/token/i),
    "policy must not check out code or receive a token")
  assert(policy_step["env"] == {
    "BASE_REF" => "${{ github.event.pull_request.base.ref }}",
    "PR_STATE" => "${{ github.event.pull_request.state }}",
    "PR_MERGED" => "${{ github.event.pull_request.merged }}",
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
    "[[ \"$PR_STATE\" != \"open\" ]]",
    "[[ \"$PR_MERGED\" != \"false\" ]]",
    "[[ -z \"$HEAD_REPOSITORY\" ]]",
    "OWNER | MEMBER | COLLABORATOR)",
    '*) trusted_author=false ;;',
    '[[ "$HEAD_REPOSITORY" != "$REPOSITORY" ||',
    '"$ACTOR" == "dependabot[bot]" || "$AUTHOR_LOGIN" == "dependabot[bot]" ||',
    '"$trusted_author" != "true" ]]',
    "printf 'cache_scope=untrusted\\n' >> \"$GITHUB_OUTPUT\"",
    'labels & %w[release:minor release:major]',
    "release_labels.length > 1",
    'release_labels.empty? ? "patch" : release_labels.fetch(0).delete_prefix("release:")',
    "printf 'release_kind=%s\\n' \"$release_kind\" >> \"$GITHUB_OUTPUT\"",
    "printf 'cache_scope=trusted\\n' >> \"$GITHUB_OUTPUT\"",
    "printf 'trusted=true\\n' >> \"$GITHUB_OUTPUT\"",
  ].each do |fragment|
    assert(policy_run.include?(fragment), "policy is missing trust-boundary fragment: #{fragment}")
  end
  assert(!policy_run.include?("CONTRIBUTOR") && !policy_run.include?("FIRST_TIME_CONTRIBUTOR"), "untrusted author associations must remain read-only")
  assert(policy_run.index("printf 'trusted=false") < policy_run.index("[[ \"$BASE_REF\""), "policy must default to untrusted before validation")
  assert(policy_run.index("printf 'trusted=true") > policy_run.index("release_labels.length > 1"), "policy may trust only after state and label validation")

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
    "EXPECTED_HEAD_SHA" => "${{ github.event.pull_request.head.sha }}",
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
    'current_head="$(git rev-parse HEAD)"',
    '[[ "$current_head" != "$EXPECTED_HEAD_SHA" ]]',
    'git ls-remote --exit-code --refs origin "refs/heads/$HEAD_REF"',
    '[[ "$remote_lines" -ne 1',
    '"$remote_ref" != "refs/heads/$HEAD_REF"',
    '[[ "$remote_sha" != "$EXPECTED_HEAD_SHA" ]]',
  ].each do |fragment|
    assert(commit_run.include?(fragment), "version commit is missing safety fragment: #{fragment}")
  end
  expected_push = 'git push --force-with-lease="refs/heads/$HEAD_REF:$EXPECTED_HEAD_SHA" origin "HEAD:refs/heads/$HEAD_REF"'
  assert(commit_run.scan(/git add --/).length == 1, "version commit must stage exactly once")
  assert(commit_run.lines.map(&:strip).grep(/\Agit push /) == [expected_push], "version push must use the singular exact compare-and-swap lease")
  assert(commit_run.index('git diff --name-only -z') < commit_run.index('git add --'), "worktree allowlist must be checked before staging")
  assert(commit_run.index('git diff --cached --name-only -z') > commit_run.index('git add --'), "staged allowlist must be rechecked")
  assert(commit_run.index('git check-ref-format --branch "$HEAD_REF"') < commit_run.index('git ls-remote'), "head ref must be validated before remote lookup")
  assert(commit_run.index('git ls-remote') < commit_run.index('git add --'), "the exact remote head must be validated before staging")
  assert(commit_run.index('git ls-remote') < commit_run.index(expected_push), "the exact remote head must be validated before compare-and-swap push")

  { "macos" => macos, "linux" => linux, "tui" => tui }.each do |name, job|
    assert(job["needs"].is_a?(Array) && job["needs"].sort == %w[policy version], "#{name} must directly wait for policy and version")
    assert(job["if"] == LANE_IF, "#{name} must always materialize as a required check")
    assert(!job.key?("continue-on-error"), "#{name} must not tolerate a failing version guard")
    guard = job.fetch("steps").first
    assert(guard["name"] == "Enforce pull request version gate", "#{name} must start with the explicit version guard")
    assert(guard.keys.sort == %w[env if name run shell], "#{name} guard must contain only reviewed fields")
    assert(guard["if"] == GUARD_IF && guard["shell"] == "bash", "#{name} guard must run for every unready PR state")
    assert(guard["env"] == {
      "POLICY_RESULT" => "${{ needs.policy.result }}",
      "TRUSTED" => "${{ needs.policy.outputs.trusted }}",
      "VERSION_RESULT" => "${{ needs.version.result }}",
      "VERSION_READY" => "${{ needs.version.outputs.ready }}",
    }, "#{name} guard diagnostics must receive dependency state through the environment")
    assert(guard["run"] == <<~SHELL, "#{name} guard must diagnose and fail the required check")
      set -euo pipefail
      echo "pull request version gate is not ready: policy=$POLICY_RESULT trusted=$TRUSTED version=$VERSION_RESULT ready=$VERSION_READY" >&2
      exit 1
    SHELL
    job.fetch("steps").drop(1).each do |step|
      next if name == "macos" && step["name"] == "Upload E2E evidence"
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
    "with" => { "node-version" => 24 },
  }, "macos Node tooling must not share an npm cache across trust lanes")
  assert(action_step(macos, "actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9") == {
    "uses" => "actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9",
    "with" => {
      "path" => ".build",
      "key" => "macos-spm-#{CACHE_SCOPE}-${{ runner.os }}-${{ hashFiles('Package.resolved') }}",
      "restore-keys" => "macos-spm-#{CACHE_SCOPE}-${{ runner.os }}-",
    },
  }, "macos Swift cache must be isolated by trust lane")
  assert(named_step(macos, "Install shellcheck")["run"] == "brew install shellcheck", "macos shellcheck installation must remain unchanged")
  assert(named_step(macos, "Quality gate")["run"] == "SKIP_SIGNED_APPCAST=1 bash Scripts/quality-gate.sh", "macos quality gate command must remain unchanged")
  app_test = named_step(macos, "Test packaged app")
  assert(app_test == {
    "name" => "Test packaged app",
    "run" => 'bash Scripts/app-e2e.sh dist/UpdateBar.app "$RUNNER_TEMP/updatebar-app-e2e.xcresult"',
  }, "macos must execute packaged UI tests without tolerating failures")
  evidence = named_step(macos, "Upload E2E evidence")
  assert(evidence == {
    "name" => "Upload E2E evidence",
    "if" => "${{ always() }}",
    "uses" => "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
    "with" => {
      "name" => "packaged-app-e2e-#{CI_REF}",
      "path" => "${{ runner.temp }}/updatebar-app-e2e.xcresult",
      "if-no-files-found" => "warn",
      "retention-days" => 7,
    },
  }, "macos must retain exact-SHA E2E evidence even on failure with read-only permissions")
  assert(macos.fetch("steps").last(3) == [named_step(macos, "Quality gate"), app_test, evidence], "packaged UI tests must follow the quality gate that builds the app and block CI/release on failure")

  assert(linux["runs-on"] == "ubuntu-latest" && linux["container"] == "swift:6.0", "linux runner and Swift container must remain unchanged")
  assert(action_step(linux, "actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9") == {
    "uses" => "actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9",
    "with" => {
      "path" => ".build",
      "key" => "linux-spm-#{CACHE_SCOPE}-${{ runner.os }}-${{ hashFiles('Package.resolved') }}",
      "restore-keys" => "linux-spm-#{CACHE_SCOPE}-${{ runner.os }}-",
    },
  }, "linux Swift cache must be isolated by trust lane")
  assert(named_step(linux, "Install quality gate dependencies")["run"] == "apt-get update\napt-get install -y nodejs ruby shellcheck\n", "linux quality dependencies must remain unchanged")
  assert(named_step(linux, "Trust the checked-out workspace")["run"] == 'git config --global --add safe.directory "$GITHUB_WORKSPACE"', "linux safe-directory command must remain unchanged")
  assert(named_step(linux, "Quality gate")["run"] == "SKIP_MENUBAR_SMOKE=1 SKIP_TUI_SMOKE=1 SKIP_TUI_INPUT=1 SKIP_SIGNED_APPCAST=1 bash Scripts/quality-gate.sh", "linux quality gate command must remain unchanged")

  assert(tui["runs-on"] == "ubuntu-24.04", "TUI runtime checks must use an isolated Linux runner")
  assert(tui["timeout-minutes"] == 10, "TUI runtime checks must have a bounded timeout")
  assert(tui["strategy"] == {
    "fail-fast" => false,
    "matrix" => { "node-version" => ["22.13.0", "22.x", "24.x", "26.x"] },
  }, "TUI must test its minimum Node runtime and every supported release line independently")
  assert(tui.fetch("steps").length == 4, "TUI runtime checks must only guard, checkout, install Node, and run the smoke")
  assert(action_step(tui, "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020") == {
    "uses" => "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020",
    "with" => { "node-version" => "${{ matrix.node-version }}" },
  }, "TUI must use each matrix runtime without sharing an npm cache")
  assert(named_step(tui, "TUI runtime checks") == {
    "name" => "TUI runtime checks",
    "run" => "bash Scripts/tui-smoke-test.sh",
  }, "TUI matrix must execute the real install, typecheck, tests, lint, build, and package checks")
end

workflow = Psych.safe_load(File.binread(ARGV.fetch(0)), permitted_classes: [], permitted_symbols: [], aliases: false)
root = File.expand_path("../..", File.dirname(ARGV.fetch(0)))
package = JSON.parse(File.binread(File.join(root, "tui/package.json")))
lock = JSON.parse(File.binread(File.join(root, "tui/package-lock.json")))
assert(package.fetch("engines") == { "node" => "^22.13.0 || >=24.0.0" }, "TUI Node support must satisfy the locked runtime and development dependencies")
assert(lock.fetch("packages").fetch("").fetch("engines") == package.fetch("engines"), "TUI lockfile and package runtime requirements must agree")
validate(workflow)
run_runtime_probes(workflow)

mutations = {
  "packaged UI tests omitted" => ->(value) {
    value.fetch("jobs").fetch("macos").fetch("steps").reject! { |step| step["name"] == "Test packaged app" }
  },
  "packaged UI failure tolerated" => ->(value) {
    named_step(value.fetch("jobs").fetch("macos"), "Test packaged app")["continue-on-error"] = true
  },
  "packaged UI bypasses failed build" => ->(value) {
    named_step(value.fetch("jobs").fetch("macos"), "Test packaged app")["if"] = "${{ always() }}"
  },
  "packaged UI runs before packaging" => ->(value) {
    steps = value.fetch("jobs").fetch("macos").fetch("steps")
    steps[-3], steps[-2] = steps[-2], steps[-3]
  },
  "failed UI evidence omitted" => ->(value) {
    named_step(value.fetch("jobs").fetch("macos"), "Upload E2E evidence").delete("if")
  },
  "unpinned E2E upload" => ->(value) {
    named_step(value.fetch("jobs").fetch("macos"), "Upload E2E evidence")["uses"] = "actions/upload-artifact@v4"
  },
  "unsupported macOS Node runtime" => ->(value) {
    action_step(value.fetch("jobs").fetch("macos"), "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020").fetch("with")["node-version"] = 20
  },
  "missing minimum Node runtime" => ->(value) {
    value.fetch("jobs").fetch("tui").fetch("strategy").fetch("matrix").fetch("node-version").delete("22.13.0")
  },
  "fail-fast hides runtime failures" => ->(value) {
    value.fetch("jobs").fetch("tui").fetch("strategy")["fail-fast"] = true
  },
  "TUI merge-ref checkout" => ->(value) {
    action_step(value.fetch("jobs").fetch("tui"), CHECKOUT_ACTION).fetch("with")["ref"] = "${{ github.ref }}"
  },
  "TUI smoke omitted" => ->(value) {
    named_step(value.fetch("jobs").fetch("tui"), "TUI runtime checks")["run"] = "npm --prefix tui run build"
  },
  "PR target branch" => ->(value) { value.fetch("on").fetch("pull_request")["branches"] = ["develop"] },
  "PR activity list" => ->(value) { value.fetch("on").fetch("pull_request")["types"].delete("labeled") },
  "workflow write permission" => ->(value) { value.fetch("permissions")["contents"] = "write" },
  "cross-run concurrency" => ->(value) { value.fetch("concurrency")["group"] = "CI" },
  "token before policy" => ->(value) { value.fetch("jobs").fetch("version").delete("needs") },
  "fork privilege escalation" => ->(value) {
    step = value.fetch("jobs").fetch("policy").fetch("steps").first
    step["run"] = step.fetch("run").sub('[[ "$HEAD_REPOSITORY" != "$REPOSITORY" ||', '[[ -z "$HEAD_REPOSITORY" ||')
  },
  "closed PR acceptance" => ->(value) {
    step = value.fetch("jobs").fetch("policy").fetch("steps").first
    step["run"] = step.fetch("run").sub('[[ "$PR_STATE" != "open" ]]', '[[ -z "$PR_STATE" ]]')
  },
  "merged PR acceptance" => ->(value) {
    step = value.fetch("jobs").fetch("policy").fetch("steps").first
    step["run"] = step.fetch("run").sub('[[ "$PR_MERGED" != "false" ]]', '[[ -z "$PR_MERGED" ]]')
  },
  "untrusted association privilege escalation" => ->(value) {
    step = value.fetch("jobs").fetch("policy").fetch("steps").first
    step["run"] = step.fetch("run").sub('*) trusted_author=false ;;', '*) trusted_author=true ;;')
  },
  "Dependabot privilege escalation" => ->(value) {
    step = value.fetch("jobs").fetch("policy").fetch("steps").first
    step["run"] = step.fetch("run").sub('"$ACTOR" == "dependabot[bot]" || "$AUTHOR_LOGIN" == "dependabot[bot]" ||', '"$ACTOR" == "not-dependabot" || "$AUTHOR_LOGIN" == "not-dependabot" ||')
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
  "plain push" => ->(value) {
    step = step_map(value.fetch("jobs").fetch("version")).fetch("Commit prepared version")
    step["run"] = step.fetch("run").sub(
      'git push --force-with-lease="refs/heads/$HEAD_REF:$EXPECTED_HEAD_SHA" origin "HEAD:refs/heads/$HEAD_REF"',
      'git push origin "HEAD:refs/heads/$HEAD_REF"',
    )
  },
  "broad force-with-lease" => ->(value) {
    step = step_map(value.fetch("jobs").fetch("version")).fetch("Commit prepared version")
    step["run"] = step.fetch("run").sub(
      'git push --force-with-lease="refs/heads/$HEAD_REF:$EXPECTED_HEAD_SHA" origin "HEAD:refs/heads/$HEAD_REF"',
      'git push --force-with-lease origin "HEAD:refs/heads/$HEAD_REF"',
    )
  },
  "lease without event SHA" => ->(value) {
    step = step_map(value.fetch("jobs").fetch("version")).fetch("Commit prepared version")
    step["run"] = step.fetch("run").sub(
      '--force-with-lease="refs/heads/$HEAD_REF:$EXPECTED_HEAD_SHA"',
      '--force-with-lease="refs/heads/$HEAD_REF"',
    )
  },
  "missing remote head lookup" => ->(value) {
    step = step_map(value.fetch("jobs").fetch("version")).fetch("Commit prepared version")
    step["run"] = step.fetch("run").sub('git ls-remote --exit-code --refs origin "refs/heads/$HEAD_REF"', 'printf "missing remote lookup\\n"')
  },
  "remote head mismatch accepted" => ->(value) {
    step = step_map(value.fetch("jobs").fetch("version")).fetch("Commit prepared version")
    step["run"] = step.fetch("run").sub('[[ "$remote_sha" != "$EXPECTED_HEAD_SHA" ]]', '[[ -z "$remote_sha" ]]')
  },
  "invalid head ref accepted" => ->(value) {
    step = step_map(value.fetch("jobs").fetch("version")).fetch("Commit prepared version")
    step["run"] = step.fetch("run").sub('git check-ref-format --branch "$HEAD_REF"', 'git check-ref-format "refs/heads/main"')
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

puts "CI workflow tests passed (#{mutations.length} security mutations rejected; 9 runtime probes passed)"
RUBY

exit 0
